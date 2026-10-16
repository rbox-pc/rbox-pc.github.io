// Windows Libretro frontend: reuse the proven FCEUmm bridge across console cores.
// Uses the already compiled fceumm_libretro.dll; no ROMs or cores are bundled.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

final class RetroSystemInfo extends Struct {
  external Pointer<Utf8> libraryName;
  external Pointer<Utf8> libraryVersion;
  external Pointer<Utf8> validExtensions;
  @Uint8()
  external int needFullpath;
  @Uint8()
  external int blockExtract;
}

final class RetroGameInfo extends Struct {
  external Pointer<Utf8> path;
  external Pointer<Void> data;
  @Size()
  external int size;
  external Pointer<Utf8> meta;
}

final class RetroGeometry extends Struct {
  @Uint32()
  external int baseWidth;
  @Uint32()
  external int baseHeight;
  @Uint32()
  external int maxWidth;
  @Uint32()
  external int maxHeight;
  @Float()
  external double aspectRatio;
}
final class RetroTiming extends Struct {
  @Double()
  external double fps;
  @Double()
  external double sampleRate;
}
final class RetroAvInfo extends Struct {
  external RetroGeometry geometry;
  external RetroTiming timing;
}

// Libretro video output callback: data, width, height, pitch (bytes).
typedef _VideoNative = Void Function(Pointer<Void>, Uint32, Uint32, Size);
typedef _AudioNative = Void Function(Int16, Int16);
typedef _AudioBatchNative = Size Function(Pointer<Int16>, Size);
typedef _InputPollNative = Void Function();
typedef _InputStateNative = Int16 Function(Uint32, Uint32, Uint32, Uint32);
typedef _EnvironmentNative = Uint8 Function(Uint32, Pointer<Void>);

class LibretroCore {
  LibretroCore._(this._dll) {
    _setEnvironment = _dll.lookupFunction<Void Function(Pointer<NativeFunction<_EnvironmentNative>>), void Function(Pointer<NativeFunction<_EnvironmentNative>>)>('retro_set_environment');
    _setVideo = _dll.lookupFunction<Void Function(Pointer<NativeFunction<_VideoNative>>), void Function(Pointer<NativeFunction<_VideoNative>>)>('retro_set_video_refresh');
    _setAudio = _dll.lookupFunction<Void Function(Pointer<NativeFunction<_AudioNative>>), void Function(Pointer<NativeFunction<_AudioNative>>)>('retro_set_audio_sample');
    _setAudioBatch = _dll.lookupFunction<Void Function(Pointer<NativeFunction<_AudioBatchNative>>), void Function(Pointer<NativeFunction<_AudioBatchNative>>)>('retro_set_audio_sample_batch');
    _setInputPoll = _dll.lookupFunction<Void Function(Pointer<NativeFunction<_InputPollNative>>), void Function(Pointer<NativeFunction<_InputPollNative>>)>('retro_set_input_poll');
    _setInputState = _dll.lookupFunction<Void Function(Pointer<NativeFunction<_InputStateNative>>), void Function(Pointer<NativeFunction<_InputStateNative>>)>('retro_set_input_state');
    _init = _dll.lookupFunction<Void Function(), void Function()>('retro_init');
    _deinit = _dll.lookupFunction<Void Function(), void Function()>('retro_deinit');
    _load = _dll.lookupFunction<Uint8 Function(Pointer<RetroGameInfo>), int Function(Pointer<RetroGameInfo>)>('retro_load_game');
    _unload = _dll.lookupFunction<Void Function(), void Function()>('retro_unload_game');
    _getInfo = _dll.lookupFunction<Void Function(Pointer<RetroSystemInfo>), void Function(Pointer<RetroSystemInfo>)>('retro_get_system_info');
    _getAvInfo = _dll.lookupFunction<Void Function(Pointer<RetroAvInfo>), void Function(Pointer<RetroAvInfo>)>('retro_get_system_av_info');
    _getMemoryData = _dll.lookupFunction<Pointer<Void> Function(Uint32), Pointer<Void> Function(int)>('retro_get_memory_data');
    _getMemorySize = _dll.lookupFunction<Size Function(Uint32), int Function(int)>('retro_get_memory_size');
    _serializeSize = _dll.lookupFunction<Size Function(), int Function()>('retro_serialize_size');
    _serialize = _dll.lookupFunction<Uint8 Function(Pointer<Void>, Size), int Function(Pointer<Void>, int)>('retro_serialize');
    _unserialize = _dll.lookupFunction<Uint8 Function(Pointer<Void>, Size), int Function(Pointer<Void>, int)>('retro_unserialize');
    _run = _dll.lookupFunction<Void Function(), void Function()>('retro_run');
  }

  final DynamicLibrary _dll;
  late final void Function(Pointer<NativeFunction<_EnvironmentNative>>) _setEnvironment;
  late final void Function(Pointer<NativeFunction<_VideoNative>>) _setVideo;
  late final void Function(Pointer<NativeFunction<_AudioNative>>) _setAudio;
  late final void Function(Pointer<NativeFunction<_AudioBatchNative>>) _setAudioBatch;
  late final void Function(Pointer<NativeFunction<_InputPollNative>>) _setInputPoll;
  late final void Function(Pointer<NativeFunction<_InputStateNative>>) _setInputState;
  late final void Function() _init, _deinit, _unload, _run;
  late final int Function(Pointer<RetroGameInfo>) _load;
  late final void Function(Pointer<RetroSystemInfo>) _getInfo;
  late final void Function(Pointer<RetroAvInfo>) _getAvInfo;
  double fps = 60, sampleRate = 44100;
  final _audioSamples = <int>[];
  late final Pointer<Void> Function(int) _getMemoryData;
  late final int Function(int) _getMemorySize;
  late final int Function() _serializeSize;
  late final int Function(Pointer<Void>, int) _serialize, _unserialize;
  Pointer<Utf8> _systemDirectory = nullptr, _saveDirectory = nullptr;
  String? _saveBase;
  // Libretro may retain retro_game_info ROM pointers until retro_unload_game.
  Pointer<Uint8> _romData = nullptr;
  Pointer<Utf8> _romPath = nullptr;
  bool _loaded = false;
  bool _initialized = false;
  int buttons = 0;
  List<int> gamepads = List.filled(4, 0);
  Uint8List? latestFrame;
  int frameWidth = 0, frameHeight = 0;
  int _pixelFormat = 0; // 0 = XRGB1555, 1 = XRGB8888, 2 = RGB565
  static LibretroCore? _active;

  static const dllNames = <String, String>{
    'Atari 2600': 'stella2014_libretro.dll',
    'NES': 'fceumm_libretro.dll',
    'SNES': 'snes9x2010_libretro.dll',
    'Sega Genesis': 'genesis_plus_gx_libretro.dll',
    'Arcade': 'fbneo_libretro.dll',
  };

  static LibretroCore open(String system) {
    if (!Platform.isWindows) throw UnsupportedError('This prototype requires Windows.');
    final dllName = dllNames[system];
    if (dllName == null) throw UnsupportedError('Unknown console: $system');
    final candidates = [
      'emulator\\$dllName',
      '${File(Platform.resolvedExecutable).parent.path}\\$dllName',
      '${File(Platform.resolvedExecutable).parent.path}\\emulator\\$dllName',
    ];
    final path = candidates.where((p) => File(p).existsSync()).firstOrNull;
    if (path == null) throw StateError('Windows core missing: $dllName. Place a compatible x64 Libretro DLL in the emulator folder. Android .so cores cannot run on Windows.');
    return LibretroCore._(DynamicLibrary.open(File(path).absolute.path));
  }

  static int _environment(int cmd, Pointer<Void> data) {
    final core = _active;
    if (core == null) return 0;
    switch (cmd & 0xffff) {
      case 3: // GET_CAN_DUPE
        if (data != nullptr) data.cast<Uint8>().value = 1;
        return 1;
      case 9: // GET_SYSTEM_DIRECTORY: retained until deinit.
        if (data == nullptr || core._systemDirectory == nullptr) return 0;
        data.cast<Pointer<Utf8>>().value = core._systemDirectory;
        return 1;
      case 31: // GET_SAVE_DIRECTORY
        if (data == nullptr || core._saveDirectory == nullptr) return 0;
        data.cast<Pointer<Utf8>>().value = core._saveDirectory;
        return 1;
      case 10: // SET_PIXEL_FORMAT
        if (data == nullptr) return 0;
        final format = data.cast<Int32>().value;
        if (format < 0 || format > 2) return 0;
        core._pixelFormat = format;
        return 1;
      case 17: // GET_VARIABLE_UPDATE
        if (data != nullptr) data.cast<Uint8>().value = 0;
        return 1;
      case 15: // GET_VARIABLE: no override, use core defaults
        return 0;
      default:
        return 0; // Optional environment extensions unsupported in prototype.
    }
  }

  static void _video(Pointer<Void> data, int width, int height, int pitch) {
    final core = _active;
    if (core == null || data == nullptr || width == 0 || height == 0 || width > 1024 || height > 1024) return;
    final bytes = data.cast<Uint8>().asTypedList(pitch * height);
    final out = Uint8List(width * height * 4);
    final format = core._pixelFormat;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = y * pitch + x * (format == 1 ? 4 : 2);
        final i = (y * width + x) * 4;
        if (format == 1) {
          out[i] = bytes[p + 2]; out[i + 1] = bytes[p + 1]; out[i + 2] = bytes[p];
        } else {
          final v = bytes[p] | (bytes[p + 1] << 8);
          if (format == 2) {
            out[i] = ((v >> 11) & 31) * 255 ~/ 31;
            out[i + 1] = ((v >> 5) & 63) * 255 ~/ 63;
            out[i + 2] = (v & 31) * 255 ~/ 31;
          } else {
            out[i] = ((v >> 10) & 31) * 255 ~/ 31;
            out[i + 1] = ((v >> 5) & 31) * 255 ~/ 31;
            out[i + 2] = (v & 31) * 255 ~/ 31;
          }
        }
        out[i + 3] = 255;
      }
    }
    core.latestFrame = out;
    core.frameWidth = width;
    core.frameHeight = height;
  }

  static void _audio(int left, int right) {
    final core = _active;
    if (core != null && core._audioSamples.length < 32768) {
      core._audioSamples.add(left); core._audioSamples.add(right);
    }
  }
  static int _audioBatch(Pointer<Int16> samples, int frames) {
    final core = _active;
    if (core != null && samples != nullptr && frames > 0 && frames <= 16384 && core._audioSamples.length + frames * 2 <= 32768) {
      core._audioSamples.addAll(samples.asTypedList(frames * 2));
    }
    return frames;
  }

  Int16List takeAudio() {
    final samples = Int16List.fromList(_audioSamples);
    _audioSamples.clear();
    return samples;
  }
  static void _poll() {}
  static int _input(int port, int device, int index, int id) {
    final core = _active;
    if (core == null || port >= 4 || (device & 0xff) != 1 || id >= 16) return 0;
    final mask = core.gamepads[port] | (port == 0 ? core.buttons : 0);
    return (mask & (1 << id)) != 0 ? 1 : 0;
  }

  void load(String romPath, {required String systemDirectory, required String saveDirectory}) {
    if (_active != null) throw StateError('Another Libretro session is active.');
    if (!File(romPath).existsSync()) throw FileSystemException('ROM not found', romPath);
    _active = this;
    try {
      Directory(systemDirectory).createSync(recursive: true);
      Directory(saveDirectory).createSync(recursive: true);
      _systemDirectory = systemDirectory.toNativeUtf8();
      _saveDirectory = saveDirectory.toNativeUtf8();
      _saveBase = '$saveDirectory${Platform.pathSeparator}${File(romPath).uri.pathSegments.last}';
      _setEnvironment(Pointer.fromFunction<_EnvironmentNative>(_environment, 0));
      _setVideo(Pointer.fromFunction<_VideoNative>(_video));
      _setAudio(Pointer.fromFunction<_AudioNative>(_audio));
      _setAudioBatch(Pointer.fromFunction<_AudioBatchNative>(_audioBatch, 0));
      _setInputPoll(Pointer.fromFunction<_InputPollNative>(_poll));
      _setInputState(Pointer.fromFunction<_InputStateNative>(_input, 0));
      _init();
      _initialized = true;
      final systemInfo = calloc<RetroSystemInfo>();
      _getInfo(systemInfo);
      final fullPath = systemInfo.ref.needFullpath != 0;
      calloc.free(systemInfo);
      final info = calloc<RetroGameInfo>();
      _romPath = romPath.toNativeUtf8();
      int romSize = 0;
      if (!fullPath) {
        final bytes = File(romPath).readAsBytesSync();
        romSize = bytes.length;
        _romData = calloc<Uint8>(romSize);
        _romData.asTypedList(romSize).setAll(0, bytes);
      }
      try {
        info.ref.path = _romPath;
        info.ref.data = _romData.cast<Void>();
        info.ref.size = romSize;
        info.ref.meta = nullptr;
        if (_load(info) == 0) throw StateError('Libretro core rejected this ROM.');
        _loaded = true;
        _restoreSram();
        final av = calloc<RetroAvInfo>();
        try {
          _getAvInfo(av);
          final timing = av.ref.timing;
          if (timing.fps.isFinite && timing.fps >= 10 && timing.fps <= 240) fps = timing.fps;
          if (timing.sampleRate.isFinite && timing.sampleRate >= 8000 && timing.sampleRate <= 192000) sampleRate = timing.sampleRate;
        } finally { calloc.free(av); }
      } finally {
        // Only the temporary retro_game_info struct can be freed here.
        // ROM buffer and path stay alive until retro_unload_game.
        calloc.free(info);
      }
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  void runFrame() {
    if (_loaded) _run();
  }

  void _restoreSram() {
    final file = File('$_saveBase.srm');
    if (!file.existsSync()) return;
    final size = _getMemorySize(0);
    final memory = _getMemoryData(0);
    final bytes = file.readAsBytesSync();
    if (size > 0 && memory != nullptr && bytes.length == size) {
      memory.cast<Uint8>().asTypedList(size).setAll(0, bytes);
    }
  }

  void saveSram() {
    if (!_loaded) return;
    final size = _getMemorySize(0);
    final memory = _getMemoryData(0);
    if (size > 0 && size <= 64 * 1024 * 1024 && memory != nullptr) {
      _writeSave(File('$_saveBase.srm'), memory.cast<Uint8>().asTypedList(size));
    }
  }

  void _writeSave(File file, List<int> bytes) {
    final temporary = File('${file.path}.tmp');
    temporary.writeAsBytesSync(bytes, flush: true);
    temporary.renameSync(file.path);
  }

  void saveState() {
    if (!_loaded) throw StateError('No game running');
    final size = _serializeSize();
    if (size <= 0 || size > 64 * 1024 * 1024) throw StateError('This core does not support a valid save state');
    final buffer = calloc<Uint8>(size);
    try {
      if (_serialize(buffer.cast<Void>(), size) == 0) throw StateError('Core could not save this state');
      _writeSave(File('$_saveBase.state'), buffer.asTypedList(size));
    } finally { calloc.free(buffer); }
    saveSram();
  }

  void loadState() {
    if (!_loaded) throw StateError('No game running');
    final file = File('$_saveBase.state');
    if (!file.existsSync()) throw StateError('No saved state for this game');
    final size = file.lengthSync();
    if (size <= 0 || size > 64 * 1024 * 1024) throw StateError('Invalid state file');
    final bytes = file.readAsBytesSync();
    final buffer = calloc<Uint8>(size);
    try {
      buffer.asTypedList(size).setAll(0, bytes);
      if (_unserialize(buffer.cast<Void>(), size) == 0) throw StateError('Core rejected state; use the same core version');
    } finally { calloc.free(buffer); }
  }

  void dispose() {
    try { saveSram(); } catch (e) { stderr.writeln('Could not save SRAM: $e'); }
    if (_loaded) { _unload(); _loaded = false; }
    if (_initialized) { _deinit(); _initialized = false; }
    if (_romData != nullptr) { calloc.free(_romData); _romData = nullptr; }
    if (_romPath != nullptr) { calloc.free(_romPath); _romPath = nullptr; }
    if (_systemDirectory != nullptr) { calloc.free(_systemDirectory); _systemDirectory = nullptr; }
    if (_saveDirectory != nullptr) { calloc.free(_saveDirectory); _saveDirectory = nullptr; }
    if (identical(_active, this)) _active = null;
  }
}
