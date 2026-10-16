import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

final class WaveFormat extends Struct {
  @Uint16()
  external int format;
  @Uint16()
  external int channels;
  @Uint32()
  external int rate;
  @Uint32()
  external int bytesPerSecond;
  @Uint16()
  external int blockAlign;
  @Uint16()
  external int bits;
  @Uint16()
  external int extra;
}

final class WaveHeader extends Struct {
  external Pointer<Int16> data;
  @Uint32()
  external int length;
  @Uint32()
  external int recorded;
  @UintPtr()
  external int user;
  @Uint32()
  external int flags;
  @Uint32()
  external int loops;
  external Pointer<WaveHeader> next;
  @UintPtr()
  external int reserved;
}

/// Bounded pool: native audio buffers stay allocated until the driver finishes.
class WindowsAudio {
  WindowsAudio(int rate) {
    if (!Platform.isWindows) throw UnsupportedError('Windows audio only');
    if (rate < 8000 || rate > 192000) throw ArgumentError.value(rate, 'rate');
    final dll = DynamicLibrary.open('winmm.dll');
    final open = dll.lookupFunction<Uint32 Function(Pointer<Pointer<Void>>, Uint32,
        Pointer<WaveFormat>, UintPtr, UintPtr, Uint32),
        int Function(Pointer<Pointer<Void>>, int, Pointer<WaveFormat>, int, int, int)>('waveOutOpen');
    _prepare = dll.lookupFunction<Uint32 Function(Pointer<Void>, Pointer<WaveHeader>, Uint32),
        int Function(Pointer<Void>, Pointer<WaveHeader>, int)>('waveOutPrepareHeader');
    _write = dll.lookupFunction<Uint32 Function(Pointer<Void>, Pointer<WaveHeader>, Uint32),
        int Function(Pointer<Void>, Pointer<WaveHeader>, int)>('waveOutWrite');
    _unprepare = dll.lookupFunction<Uint32 Function(Pointer<Void>, Pointer<WaveHeader>, Uint32),
        int Function(Pointer<Void>, Pointer<WaveHeader>, int)>('waveOutUnprepareHeader');
    _reset = dll.lookupFunction<Uint32 Function(Pointer<Void>), int Function(Pointer<Void>)>('waveOutReset');
    _close = dll.lookupFunction<Uint32 Function(Pointer<Void>), int Function(Pointer<Void>)>('waveOutClose');
    final format = calloc<WaveFormat>();
    final handle = calloc<Pointer<Void>>();
    try {
      format.ref.format = 1;
      format.ref.channels = 2;
      format.ref.rate = rate;
      format.ref.bytesPerSecond = rate * 4;
      format.ref.blockAlign = 4;
      format.ref.bits = 16;
      final result = open(handle, 0xffffffff, format, 0, 0, 0);
      if (result != 0) throw StateError('Audio device could not open ($result)');
      _handle = handle.value;
      for (var i = 0; i < 8; i++) {
        final header = calloc<WaveHeader>();
        header.ref.data = calloc<Int16>(8192);
        _headers.add(header);
      }
    } finally { calloc.free(format); calloc.free(handle); }
  }

  Pointer<Void> _handle = nullptr;
  final _headers = <Pointer<WaveHeader>>[];
  late final int Function(Pointer<Void>, Pointer<WaveHeader>, int) _prepare, _write, _unprepare;
  late final int Function(Pointer<Void>) _reset, _close;

  void push(Int16List samples) {
    if (_handle == nullptr || samples.isEmpty) return;
    var offset = 0;
    while (offset < samples.length) {
      Pointer<WaveHeader>? available;
      for (final header in _headers) {
        if ((header.ref.flags & 0x10) != 0) continue; // WHDR_INQUEUE
        if ((header.ref.flags & 2) != 0 && _unprepare(_handle, header, sizeOf<WaveHeader>()) != 0) continue;
        available = header;
        break;
      }
      if (available == null) return; // Drop rather than grow latency unboundedly.
      final count = (samples.length - offset).clamp(0, 8192);
      available.ref.data.asTypedList(count).setRange(0, count, samples, offset);
      available.ref.length = count * 2;
      available.ref.flags = 0;
      if (_prepare(_handle, available, sizeOf<WaveHeader>()) != 0) return;
      if (_write(_handle, available, sizeOf<WaveHeader>()) != 0) return;
      offset += count;
    }
  }

  void dispose() {
    if (_handle == nullptr) return;
    if (_reset(_handle) != 0) return; // Never free memory still owned by the driver.
    for (final header in _headers) {
      if ((header.ref.flags & 2) != 0 && _unprepare(_handle, header, sizeOf<WaveHeader>()) != 0) continue;
      calloc.free(header.ref.data);
      calloc.free(header);
    }
    _headers.clear();
    _close(_handle);
    _handle = nullptr;
  }
}
