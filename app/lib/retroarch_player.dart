import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  const RetroArchPlayer({super.key, required this.title, required this.romPath, required this.system});
  @override
  State<RetroArchPlayer> createState() => _RetroArchPlayerState();
}

class _RetroArchPlayerState extends State<RetroArchPlayer> {
  Process? _process;
  IOSink? _log;
  String _status = 'Preparando juego…';
  bool _running = false;
  bool _starting = true;
  bool _smooth = true;
  String? _engineOverride;

  @override
  void initState() {
    super.initState();
    _launch();
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
    await File(selected.path).copy(destination.path);
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
      // CLI paths are individual arguments. Never invoke a command shell.
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
        'input_exit_emulator': '"escape"',
        'input_quit_gamepad_combo': '4',
        'quit_press_twice': 'false',
        'stdin_cmd_enable': 'true',
        'network_cmd_enable': 'false',
        'menu_driver': '"rgui"',
        'rgui_show_start_screen': 'false',
        'ui_companion_start_on_boot': 'false',
        'desktop_menu_enable': 'false',
        'savefile_directory': configValue('${root.path}/saves/${widget.system}'),
        'savestate_directory': configValue('${root.path}/states/${widget.system}'),
        'system_directory': configValue('${root.path}/bios'),
        'joypad_autoconfig_dir': configValue('${engine.parent.path}/autoconfig'),
        'autosave_interval': '10',
      };
      await Directory('${root.path}/saves/${widget.system}').create(recursive: true);
      await Directory('${root.path}/states/${widget.system}').create(recursive: true);
      await config.writeAsString(values.entries.map((e) => '${e.key} = ${e.value}').join('\n'), flush: true);
      final log = File('${root.path}/logs/last-session.log').openWrite();
      _log = log;
      final process = await Process.start(engine.path,
          ['--verbose', '--config', config.path, '-L', core.path, widget.romPath],
          workingDirectory: engine.parent.path);
      _process = process;
      final output = process.stdout.listen(log.add);
      final errors = process.stderr.listen(log.add);
      if (mounted) setState(() { _running = true; _starting = false; _status = 'Jugando. Esc o Start + Select para volver.'; });
      final code = await process.exitCode;
      await output.asFuture<void>();
      await errors.asFuture<void>();
      await log.flush();
      await log.close();
      _log = null;
      _process = null;
      if (!mounted) return;
      setState(() { _running = false; _status = code == 0 ? 'Partida cerrada. Puedes elegir otro juego.' : 'El motor terminó con código $code. Registro: ${root.path}/logs/last-session.log'; });
      if (code == 0) Navigator.of(context).pop();
    } catch (error) {
      if (_process == null) {
        await _log?.close();
        _log = null;
      }
      if (mounted) setState(() { _starting = false; _running = _process != null; _status = '$error'; });
    }
  }

  Future<void> _quit() async {
    try {
      _process?.stdin.writeln('QUIT');
      await _process?.stdin.flush();
      if (mounted) setState(() => _status = 'Cerrando partida y guardando… Si el motor no responde, usa Esc en su ventana.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Usa Esc en la ventana del juego para salir. $error');
    }
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
            const Text('Salir: Esc · Mando: Start + Select\nGuardar estado: F2 · Cargar estado: F4\nMenú avanzado: F1', textAlign: TextAlign.center),
            SwitchListTile(title: const Text('Suavizar imagen'), subtitle: const Text('Se aplica al iniciar la siguiente partida.'), value: _smooth,
              onChanged: _running || _starting ? null : (value) => setState(() => _smooth = value)),
            if (_running) FilledButton.icon(onPressed: _quit, icon: const Icon(Icons.home), label: const Text('Volver a la biblioteca')),
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
