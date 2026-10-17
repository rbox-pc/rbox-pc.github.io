import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'windows_controls.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

const bundledCores = <String, String>{
  'Atari 2600': 'stella_libretro.dll',
  'NES': 'fceumm_libretro.dll',
  'SNES': 'bsnes_libretro.dll',
  'Sega Genesis': 'blastem_libretro.dll',
  'Arcade': 'mame_libretro.dll',
};

String configValue(String value) {
  if (value.contains('"') || value.contains('\n') || value.contains('\r')) {
    throw const FormatException('Ruta no válida para la configuración');
  }
  return '"${value.replaceAll('\\', '/')}"';
}

class RetroArchPlayer extends StatefulWidget {
  final String title, romPath, system;
  final String? cheatPath;
  final bool spanish;
  const RetroArchPlayer({super.key, required this.title, required this.romPath, required this.system, this.cheatPath, this.spanish = true});
  @override
  State<RetroArchPlayer> createState() => _RetroArchPlayerState();
}

class _RetroArchPlayerState extends State<RetroArchPlayer> {
  Process? _process;
  RawDatagramSocket? _commands;
  int _commandPort = 0;
  IOSink? _log;
  String _status = 'Preparando juego…';
  bool _running = false;
  bool _starting = true;
  bool _smooth = true;
  String? _engineOverride;
  final _windows = GameWindows();
  StreamSubscription<PadEvent>? _padEvents;
  bool _exitVisible = false, _paused = false;
  DateTime? _lastStart;
  File? _autoState;
  String tr(String en, String es) => widget.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    _padEvents = WindowsControls.instance.events.stream.listen(_onPad);
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  Future<Directory> _root() async {
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory('${documents.path}/RetroBoxLibrary');
    await root.create(recursive: true);
    return root;
  }

  Future<Map<String, dynamic>> _settings(Directory root) async {
    final file = File('${root.path}/engine.json');
    return await file.exists()
        ? Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map)
        : <String, dynamic>{};
  }

  Future<void> _chooseEngine() async {
    final selected = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['exe']);
    if (selected == null) return;
    final root = await _root();
    final settings = await _settings(root);
    settings['engine'] = selected.path;
    await File('${root.path}/engine.json').writeAsString(jsonEncode(settings), flush: true);
    _engineOverride = selected.path;
    await _launch();
  }

  Future<void> _importCore() async {
    final selected = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['dll']);
    if (selected == null) return;
    final root = await _root();
    final destination = File('${root.path}/cores/${widget.system.replaceAll(' ', '_')}.dll');
    await destination.parent.create(recursive: true);
    await File(selected.path!).copy(destination.path);
    final settings = await _settings(root);
    final cores = Map<String, dynamic>.from(settings['cores'] as Map? ?? {});
    cores[widget.system] = destination.path;
    settings['cores'] = cores;
    await File('${root.path}/engine.json').writeAsString(jsonEncode(settings), flush: true);
    if (mounted) setState(() => _status = 'Core importado para ${widget.system}. Pulsa Jugar.');
  }

  Future<void> _launch() async {
    if (_running || _process != null) return;
    if (mounted) setState(() { _starting = true; _status = 'Preparando juego…'; });
    try {
      final root = await _root();
      final settings = await _settings(root);
      _smooth = settings['smooth'] as bool? ?? true;
      final engine = File(_engineOverride ?? settings['engine'] as String? ??
          '${File(Platform.resolvedExecutable).parent.path}/engine/retroarch.exe');
      if (!await engine.exists()) {
        throw const FileSystemException('No se encontró el motor. Selecciona retroarch.exe de tu paquete de prueba.');
      }
      final overrides = Map<String, dynamic>.from(settings['cores'] as Map? ?? {});
      final core = File(overrides[widget.system] as String? ??
          '${engine.parent.path}/cores/${bundledCores[widget.system]}');
      if (!await core.exists()) throw FileSystemException('Falta el core de ${widget.system}', core.path);
      if (!await File(widget.romPath).exists()) throw FileSystemException('No se encontró la ROM', widget.romPath);
      for (final name in ['saves', 'states', 'bios', 'logs']) {
        await Directory('${root.path}/$name').create(recursive: true);
      }
      final filename = widget.romPath.replaceAll('\\','/').split('/').last;
      final dot = filename.lastIndexOf('.');
      final stem = dot > 0 ? filename.substring(0,dot) : filename;
      final statePath = '${root.path}/states/${widget.system}/$stem.state';
      _autoState = File(statePath);
      var resume = false;
      if (await _autoState!.exists() && mounted) {
        resume = await showDialog<bool>(context: context,builder: (context) => AlertDialog(
          title: Text(widget.title), content: Text(tr('Continue saved game?', '¿Continuar la partida guardada?')),
          actions: [TextButton(onPressed: () => Navigator.pop(context,false), child: Text(tr('NEW GAME','NUEVA PARTIDA'))), TextButton(onPressed: () => Navigator.pop(context,true), child: Text(tr('CONTINUE','CONTINUAR')))],
        )) ?? false;
      }
      final cheatDir = Directory('${root.path}/active-cheats');
      if (await cheatDir.exists()) await cheatDir.delete(recursive:true);
      final cheat = widget.cheatPath;
      if (cheat != null) {
        if (!cheat.toLowerCase().endsWith('.cht')) throw const FormatException('Este core necesita trucos en formato RetroArch .cht. El archivo original permanece importado.');
        final identities = File('${engine.parent.path}/CORE_IDENTITIES.json');
        if (!await identities.exists()) throw const FileSystemException('Faltan los datos de identificación del core para cargar trucos.');
        final metadata = jsonDecode(await identities.readAsString()) as Map<String,dynamic>;
        final coreName = metadata[core.path.replaceAll('\\','/').split('/').last] as String?;
        if (coreName == null || coreName.contains('/') || coreName.contains('\\')) throw const FormatException('Core importado sin identidad de trucos. Usa F1 para cargar su archivo de trucos.');
        final target = File('${cheatDir.path}/$coreName/$stem.cht');
        await target.parent.create(recursive:true);
        await File(cheat).copy(target.path);
      }

      // CLI paths are individual arguments. Never invoke a command shell.
      final reservation = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4,0);
      _commandPort = reservation.port;
      reservation.close();
      _commands = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4,0);
      final ready = Completer<void>();
      _commands!.listen((event) {
        if (event == RawSocketEvent.read) {
          final data = _commands?.receive();
          if (data != null && utf8.decode(data.data,allowMalformed:true).contains('PLAYING') && !ready.isCompleted) ready.complete();
        }
      });
      final config = File('${root.path}/session.cfg');
      final values = <String, String>{
        'config_save_on_exit': 'false',
        'video_fullscreen': 'true',
        'video_windowed_fullscreen': 'true',
        'video_force_aspect': 'true',
        'aspect_ratio_index': '22',
        'video_scale_integer': (!_smooth).toString(),
        'video_smooth': _smooth.toString(),
        'input_joypad_driver': '"sdl2"',
        'input_autodetect_enable': 'true',
        'input_exit_emulator': '"nul"',
        'input_quit_gamepad_combo': '0',
        'quit_press_twice': 'false',
        'stdin_cmd_enable': 'false',
        'network_cmd_enable': 'true',
        'network_cmd_port': _commandPort.toString(),
        'menu_driver': '"rgui"',
        'rgui_show_start_screen': 'false',
        'ui_companion_start_on_boot': 'false',
        'desktop_menu_enable': 'false',
        'savefile_directory': configValue('${root.path}/saves/${widget.system}'),
        'savestate_directory': configValue('${root.path}/states/${widget.system}'),
        'system_directory': configValue('${root.path}/bios'),
        'joypad_autoconfig_dir': configValue('${engine.parent.path}/autoconfig'),
        'autosave_interval': '10',
        'state_slot': '0',
        'savestate_auto_save': 'false',
        'savestate_auto_load': 'false',
        'savestate_auto_index': 'false',
        'savestate_file_compression': 'true',
        'sort_savestates_enable': 'false',
        'sort_savefiles_enable': 'false',
        'sort_savestates_by_content_enable': 'false',
        'sort_savefiles_by_content_enable': 'false',
        'cheat_database_path': configValue('${root.path}/active-cheats'),
        'apply_cheats_after_load': (widget.cheatPath != null).toString(),
      };
      await Directory('${root.path}/saves/${widget.system}').create(recursive: true);
      await Directory('${root.path}/states/${widget.system}').create(recursive: true);
      await config.writeAsString(values.entries.map((e) => '${e.key} = ${e.value}').join('\n'), flush: true);
      final log = File('${root.path}/logs/last-session.log').openWrite();
      _log = log;
      _windows.captureLibrary();
      final process = await Process.start(engine.path,
          ['--verbose', '--config', config.path, '-L', core.path, widget.romPath],
          workingDirectory: engine.parent.path);
      _process = process;
      Timer(const Duration(seconds: 2), () { if (_process == process) _windows.findGame(process.pid); });
      final output = process.stdout.listen(log.add).asFuture<void>();
      final errors = process.stderr.listen(log.add).asFuture<void>();
      unawaited(() async {
        for (var i = 0; i < 150 && _process == process && !ready.isCompleted; i++) {
          await _command('GET_STATUS');
          await Future<void>.delayed(const Duration(milliseconds:100));
        }
        if (resume && ready.isCompleted && _process == process) await _command('LOAD_STATE');
      }());
      if (mounted) setState(() { _running = true; _starting = false; _status = 'Jugando. Select + abajo abre el menú de salida.'; });
      final code = await process.exitCode;
      await output;
      await errors;
      await log.flush();
      await log.close();
      _log = null;
      _process = null;
      _commands?.close(); _commands = null;
      if (!mounted) return;
      setState(() { _running = false; _status = code == 0 ? 'Partida cerrada. Puedes elegir otro juego.' : 'El motor terminó con código $code. Registro: ${root.path}/logs/last-session.log'; });
      if (code == 0) Navigator.of(context).pop();
    } catch (error) {
      if (_process == null) {
        _commands?.close(); _commands = null;
        await _log?.close();
        _log = null;
      }
      if (mounted) setState(() { _starting = false; _running = _process != null; _status = '$error'; });
    }
  }

  Future<void> _quit() async {
    try {
      await _command('QUIT');
      if (mounted) setState(() => _status = 'Cerrando partida y guardando… Si el motor no responde, usa Esc en su ventana.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Usa Esc en la ventana del juego para salir. $error');
    }
  }

  @override
  void dispose() {
    _padEvents?.cancel();
    super.dispose();
  }

  void _onPad(PadEvent event) {
    if (!_running && ModalRoute.of(context)?.isCurrent == true) return;
    if (_exitVisible || !_running) {
      final focus = FocusManager.instance.primaryFocus;
      if (event.button == 11) focus?.previousFocus();
      if (event.button == 12) focus?.nextFocus();
      if ([0,6].contains(event.button) && focus?.context != null) Actions.maybeInvoke(focus!.context!, const ActivateIntent());
      return;
    }
    if (event.exitCombo) { _exitMenu(); return; }
    if (event.button == 6) {
      final now = DateTime.now();
      if (_lastStart != null && now.difference(_lastStart!).inMilliseconds <= 500) {
        _lastStart = null;
        _command('PAUSE_TOGGLE');
        _paused = !_paused;
      } else { _lastStart = now; }
    }
  }

  Future<void> _command(String command) async {
    _commands?.send(utf8.encode(command),InternetAddress.loopbackIPv4,_commandPort);
  }

  Future<void> _exitMenu() async {
    if (!_running || _exitVisible) return;
    _exitVisible = true;
    final wasPaused = _paused;
    if (!wasPaused) { await _command('PAUSE_TOGGLE'); _paused = true; }
    final process = _process;
    if (process != null) _windows.findGame(process.pid);
    _windows.showLibrary();
    if (!mounted) return;
    final choice = await showDialog<int>(context: context, barrierDismissible: false, builder: (context) => AlertDialog(
      title: Text(tr('EXIT GAME', 'SALIR DEL JUEGO')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextButton(onPressed: () => Navigator.pop(context,0), child: Text(tr('Save & Exit','Guardar y salir'))),
        TextButton(autofocus: true,onPressed: () => Navigator.pop(context,1), child: Text(tr('Exit Without Saving','Salir sin guardar'))),
        TextButton(onPressed: () => Navigator.pop(context,2), child: Text(tr('Cancel','Cancelar'))),
      ]),
    ));
    if (choice == 0) {
      final state = _autoState!;
      final before = await state.exists() ? await state.lastModified() : null;
      await _command('SAVE_STATE');
      var saved = false;
      for (var i = 0; i < 100 && _running; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (await state.exists()) {
          final modified = await state.lastModified();
          if (before == null || modified.isAfter(before)) { saved = true; break; }
        }
      }
      if (!saved) {
        if (mounted) setState(() => _status = tr('Save was not confirmed. The game remains open.','No se confirmó el guardado. La partida sigue abierta.'));
        _exitVisible = false;
        if (!wasPaused) { await _command('PAUSE_TOGGLE'); _paused = false; }
        _windows.showGame();
        return;
      }
      await _quit();
    } else if (choice == 1) { await _quit(); }
    else {
      if (!wasPaused) { await _command('PAUSE_TOGGLE'); _paused = false; }
      _windows.showGame();
    }
    _exitVisible = false;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_running && !_starting,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(padding: const EdgeInsets.all(24), child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_esports, size: 64),
            const SizedBox(height: 20),
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            const Text('Menú de salida: Select + abajo · Start dos veces: pausa\nGuardar estado: F2 · Cargar estado: F4\nMenú avanzado: F1', textAlign: TextAlign.center),
            SwitchListTile(title: const Text('Suavizar imagen'), subtitle: const Text('Se aplica al iniciar la siguiente partida.'), value: _smooth,
              onChanged: _running || _starting ? null : (value) => setState(() => _smooth = value)),
            if (_running) FilledButton.icon(onPressed: _exitMenu, icon: const Icon(Icons.home), label: const Text('Volver a la biblioteca')),
            if (!_running && !_starting) ...[
              FilledButton(onPressed: _launch, child: const Text('Jugar')),
              TextButton(onPressed: _chooseEngine, child: const Text('Seleccionar motor RetroArch')),
              TextButton(onPressed: _importCore, child: Text('Importar core de ${widget.system}')),
            ],
          ],
        )),
      )),
    ),
  );
}
