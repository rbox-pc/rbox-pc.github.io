import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

final class XInputGamepad extends Struct {
  @Uint16()
  external int buttons;
  @Uint8()
  external int leftTrigger;
  @Uint8()
  external int rightTrigger;
  @Int16()
  external int leftX;
  @Int16()
  external int leftY;
  @Int16()
  external int rightX;
  @Int16()
  external int rightY;
}

final class XInputState extends Struct {
  @Uint32()
  external int packet;
  external XInputGamepad gamepad;
}

/// Four XInput-compatible USB/Bluetooth gamepads. DirectInput-only devices
/// are not covered by this API and need a separate backend.
class WindowsGamepads {
  WindowsGamepads() {
    if (!Platform.isWindows) return;
    for (final name in ['xinput1_4.dll', 'xinput1_3.dll', 'xinput9_1_0.dll']) {
      try {
        _getState = DynamicLibrary.open(name).lookupFunction<
            Uint32 Function(Uint32, Pointer<XInputState>),
            int Function(int, Pointer<XInputState>)>('XInputGetState');
        _state = calloc<XInputState>();
        return;
      } catch (_) { /* Try the next installed Windows API version. */ }
    }
  }

  int Function(int, Pointer<XInputState>)? _getState;
  Pointer<XInputState> _state = nullptr;

  static int buttonMask(int buttons, int x, int y, int lt, int rt) {
    var mask = 0;
    void set(bool pressed, int id) { if (pressed) mask |= 1 << id; }
    set((buttons & 0x1000) != 0, 0); // Xbox A -> Libretro B
    set((buttons & 0x4000) != 0, 1); // Xbox X -> Y
    set((buttons & 0x0020) != 0, 2); // Back -> Select / coin
    set((buttons & 0x0010) != 0, 3);
    set((buttons & 0x0001) != 0 || y > 10000, 4);
    set((buttons & 0x0002) != 0 || y < -10000, 5);
    set((buttons & 0x0004) != 0 || x < -10000, 6);
    set((buttons & 0x0008) != 0 || x > 10000, 7);
    set((buttons & 0x2000) != 0, 8); // Xbox B -> A
    set((buttons & 0x8000) != 0, 9); // Xbox Y -> X
    set((buttons & 0x0100) != 0, 10);
    set((buttons & 0x0200) != 0, 11);
    set(lt > 30, 12);
    set(rt > 30, 13);
    set((buttons & 0x0040) != 0, 14);
    set((buttons & 0x0080) != 0, 15);
    return mask;
  }

  List<int> poll() {
    final read = _getState;
    if (read == null) return List.filled(4, 0);
    return List.generate(4, (port) {
      if (read(port, _state) != 0) return 0;
      final pad = _state.ref.gamepad;
      return buttonMask(pad.buttons, pad.leftX, pad.leftY,
          pad.leftTrigger, pad.rightTrigger);
    });
  }

  void dispose() {
    if (_state != nullptr) calloc.free(_state);
    _state = nullptr;
    _getState = null;
  }
}
