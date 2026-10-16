import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'libretro_core.dart';
import 'windows_gamepads.dart';
import 'windows_audio.dart';

class LibretroPlayer extends StatefulWidget {
  const LibretroPlayer({super.key, required this.title, required this.romPath, required this.system});
  final String title, romPath, system;
  @override
  State<LibretroPlayer> createState() => _LibretroPlayerState();
}

class _LibretroPlayerState extends State<LibretroPlayer> {
  LibretroCore? _core;
  WindowsAudio? _audio;
  Timer? _timer;
  Timer? _saveTimer;
  ui.Image? _image;
  bool _decoding = false;
  String? _error;
  final _focus = FocusNode();
  final _gamepads = WindowsGamepads();
  static final _keys = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.arrowUp: 4, LogicalKeyboardKey.arrowDown: 5,
    LogicalKeyboardKey.arrowLeft: 6, LogicalKeyboardKey.arrowRight: 7,
    LogicalKeyboardKey.keyZ: 0, LogicalKeyboardKey.keyX: 8,
    LogicalKeyboardKey.keyA: 1, LogicalKeyboardKey.keyS: 9,
    LogicalKeyboardKey.keyQ: 10, LogicalKeyboardKey.keyW: 11,
    LogicalKeyboardKey.enter: 3, LogicalKeyboardKey.shiftRight: 2,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final id = _keys[event.logicalKey];
    final core = _core;
    if (id == null || core == null) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      core.buttons &= ~(1 << id);
    } else {
      core.buttons |= 1 << id;
    }
    return KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      final core = LibretroCore.open(widget.system);
      final documents = await getApplicationDocumentsDirectory();
      if (!mounted) return;
      final root = '${documents.path}${Platform.pathSeparator}RetroBoxLibrary';
      core.load(widget.romPath,
        systemDirectory: '$root${Platform.pathSeparator}bios',
        saveDirectory: '$root${Platform.pathSeparator}saves${Platform.pathSeparator}${widget.system}');
      _core = core;
      try { _audio = WindowsAudio(core.sampleRate.round()); }
      catch (e) { _notice('Audio unavailable: $e'); }
      _saveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        try { core.saveSram(); } catch (e) { _notice('Save failed: $e'); }
      });
      _timer = Timer.periodic(Duration(microseconds: (1000000 / core.fps).round()), (_) {
        if (!mounted || _decoding) return;
        try {
          core.gamepads = _focus.hasFocus ? _gamepads.poll() : List.filled(4, 0);
          core.runFrame();
          _audio?.push(core.takeAudio());
          final pixels = core.latestFrame;
          if (pixels == null) return;
          _decoding = true;
          ui.decodeImageFromPixels(pixels, core.frameWidth, core.frameHeight,
              ui.PixelFormat.rgba8888, (image) {
            _decoding = false;
            if (!mounted) { image.dispose(); return; }
            setState(() { _image?.dispose(); _image = image; });
          });
        } catch (e) {
          _timer?.cancel();
          setState(() => _error = '$e');
        }
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _notice(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _stateAction(bool save) {
    if (_core == null) return;
    try {
      if (save) { _core!.saveState(); } else { _core!.loadState(); }
      _notice(save ? 'Game state saved' : 'Game state restored');
    } catch (e) { _notice('$e'); }
  }

  Widget _button(String label, int id) => Listener(
    onPointerDown: (_) => _core?.buttons |= (1 << id),
    onPointerUp: (_) => _core?.buttons &= ~(1 << id),
    onPointerCancel: (_) => _core?.buttons &= ~(1 << id),
    child: Container(width: 54, height: 50, alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.blueGrey.shade700, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title), actions: [
      IconButton(tooltip: 'Save state', onPressed: () => _stateAction(true), icon: const Icon(Icons.save)),
      IconButton(tooltip: 'Load state', onPressed: () => _stateAction(false), icon: const Icon(Icons.restore)),
    ]),
    body: _error != null ? Center(child: SelectableText('${widget.system} startup error:\n$_error')) :
      Focus(
        focusNode: _focus, autofocus: true, onKeyEvent: _onKey,
        onFocusChange: (focused) { if (!focused) _core?.buttons = 0; },
        child: Column(children: [
        Expanded(child: Center(child: _image == null
          ? const CircularProgressIndicator()
          : RawImage(image: _image, filterQuality: FilterQuality.none, fit: BoxFit.contain))),
        Text('${widget.system} · Arrows: move · Z/X/A/S/Q/W: buttons · Enter: Start · Right Shift: Select · XInput gamepads supported', style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Column(children: [
            _button('↑', 4),
            Row(children: [_button('←', 6), const SizedBox(width: 54), _button('→', 7)]),
            _button('↓', 5),
          ]),
          Column(children: [
            Row(children: [_button('SELECT', 2), const SizedBox(width: 6), _button('START', 3)]),
            const SizedBox(height: 12),
            Row(children: [
              _button('B', 0), const SizedBox(width: 8), _button('A', 8),
              if (widget.system == 'Sega Genesis' || widget.system == 'Arcade') ...[
                const SizedBox(width: 8), _button('C / X', 9),
              ],
            ]),
          ]),
        ]),
        const SizedBox(height: 28),
      ])),
  );

  @override
  void dispose() {
    _timer?.cancel();
    _saveTimer?.cancel();
    _focus.dispose();
    _gamepads.dispose();
    _core?.dispose();
    _audio?.dispose();
    _image?.dispose();
    super.dispose();
  }
}
