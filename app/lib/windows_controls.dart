import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Same SDL controller mapping used by the game engine, including Switch Pro.
class WindowsControls {
  static final instance = WindowsControls();
  DynamicLibrary? _sdl;
  Timer? _timer;
  final _controllers = <int, Pointer<Void>>{};
  final _previous = <int, Set<int>>{};
  final events = StreamController<PadEvent>.broadcast();

  void start() {
    if (!Platform.isWindows) return;
    try {
      final sdl = DynamicLibrary.open('${File(Platform.resolvedExecutable).parent.path}/SDL2.dll');
      _sdl = sdl;
      final hint = sdl.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>), int Function(Pointer<Utf8>, Pointer<Utf8>)>('SDL_SetHint');
      final name = 'SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS'.toNativeUtf8();
      final value = '1'.toNativeUtf8();
      hint(name, value);
      calloc.free(name);
      calloc.free(value);
      final init = sdl.lookupFunction<Int32 Function(Uint32), int Function(int)>('SDL_InitSubSystem');
      if (init(0x2000 | 0x200) != 0) return;
      _timer = Timer.periodic(const Duration(milliseconds: 25), (_) => _poll());
    } catch (_) { /* Keyboard and mouse stay available if SDL cannot start. */ }
  }

  void _poll() {
    final sdl = _sdl;
    if (sdl == null) return;
    sdl.lookupFunction<Void Function(), void Function()>('SDL_PumpEvents')();
    sdl.lookupFunction<Void Function(), void Function()>('SDL_GameControllerUpdate')();
    final count = sdl.lookupFunction<Int32 Function(), int Function()>('SDL_NumJoysticks')();
    final isController = sdl.lookupFunction<Int32 Function(Int32), int Function(int)>('SDL_IsGameController');
    final open = sdl.lookupFunction<Pointer<Void> Function(Int32), Pointer<Void> Function(int)>('SDL_GameControllerOpen');
    final attached = sdl.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('SDL_GameControllerGetAttached');
    final close = sdl.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('SDL_GameControllerClose');
    for (final index in _controllers.keys.toList()) {
      if (attached(_controllers[index]!) == 0) {
        close(_controllers.remove(index)!);
        _previous.remove(index);
      }
    }
    for (var i = 0; i < count && i < 8; i++) {
      if (!_controllers.containsKey(i) && isController(i) != 0) {
        final controller = open(i);
        if (controller != nullptr) _controllers[i] = controller;
      }
    }
    final button = sdl.lookupFunction<Uint8 Function(Pointer<Void>, Int32), int Function(Pointer<Void>, int)>('SDL_GameControllerGetButton');
    for (final entry in _controllers.entries) {
      final down = <int>{for (var b = 0; b < 15; b++) if (button(entry.value, b) != 0) b};
      final previous = _previous[entry.key] ?? <int>{};
      for (final b in down.difference(previous)) {
        events.add(PadEvent(entry.key, b, down));
      }
      _previous[entry.key] = down;
    }
  }

  void dispose() {
    _timer?.cancel();
    final sdl = _sdl;
    if (sdl != null) {
      final close = sdl.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('SDL_GameControllerClose');
      for (final pointer in _controllers.values) { close(pointer); }
      sdl.lookupFunction<Void Function(Uint32), void Function(int)>('SDL_QuitSubSystem')(0x2000 | 0x200);
    }
    events.close();
  }
}

class PadEvent {
  final int controller, button;
  final Set<int> down;
  const PadEvent(this.controller, this.button, this.down);
  bool get exitCombo => down.contains(4) && down.contains(12); // BACK + DPAD_DOWN
}

/// Raise the library for its Android-style exit dialog; restore the game on cancel.
class GameWindows {
  final _user = Platform.isWindows ? DynamicLibrary.open('user32.dll') : null;
  int library = 0;
  int game = 0;

  void captureLibrary() {
    library = _user?.lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow')() ?? 0;
  }

  void findGame(int pid) {
    final user = _user;
    if (user == null) return;
    final processId = calloc<Uint32>();
    final getPid = user.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
    final visible = user.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');
    final callback = NativeCallable<Int32 Function(IntPtr, IntPtr)>.isolateLocal((int hwnd, int _) {
      getPid(hwnd, processId);
      if (processId.value == pid && visible(hwnd) != 0) { game = hwnd; return 0; }
      return 1;
    }, exceptionalReturn: 0);
    user.lookupFunction<Int32 Function(Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>, IntPtr), int Function(Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>, int)>('EnumWindows')(callback.nativeFunction, 0);
    callback.close();
    calloc.free(processId);
  }

  void showLibrary() { _show(game, 0); _show(library, 9); _focus(library); }
  void showGame() { _show(game, 9); _focus(game); }
  void _show(int handle, int action) { if (handle != 0) _user?.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow')(handle, action); }
  void _focus(int handle) { if (handle != 0) _user?.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow')(handle); }
}

class MenuMusic {
  static Pointer<Utf16>? _path;
  static Future<void> play() async {
    if (!Platform.isWindows) return;
    try {
      if (_path == null) {
        final folder = await getTemporaryDirectory();
        final file = File('${folder.path}/retrobox-menu.wav');
        final bytes = await rootBundle.load('assets/android/menu_music.wav');
        await file.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
        _path = file.path.toNativeUtf16();
      }
      DynamicLibrary.open('winmm.dll').lookupFunction<Int32 Function(Pointer<Utf16>, IntPtr, Uint32), int Function(Pointer<Utf16>, int, int)>('PlaySoundW')(_path!, 0, 0x20000 | 0x1 | 0x8 | 0x2);
    } catch (_) {}
  }
  static void stop() {
    if (!Platform.isWindows) return;
    DynamicLibrary.open('winmm.dll').lookupFunction<Int32 Function(Pointer<Utf16>, IntPtr, Uint32), int Function(Pointer<Utf16>, int, int)>('PlaySoundW')(nullptr, 0, 0);
  }
}
