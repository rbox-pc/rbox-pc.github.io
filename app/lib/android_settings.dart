part of 'main.dart';

extension AndroidSettings on _RetroBoxHomeState {
  Future<Map<String,dynamic>> _preferences() async {
    final root = await _libraryDir();
    final file = File('${root.path}/engine.json');
    return await file.exists() ? Map<String,dynamic>.from(jsonDecode(await file.readAsString()) as Map) : <String,dynamic>{};
  }

  Future<void> _loadPreferences() async {
    final settings = await _preferences();
    if (!mounted) return;
    setState(() { _spanish = settings['spanish'] as bool? ?? true; _music = settings['music'] as bool? ?? true; });
    if (_music) MenuMusic.play();
  }

  Future<void> _writePreferences(Map<String,dynamic> settings) async {
    final root = await _libraryDir();
    await File('${root.path}/engine.json').writeAsString(jsonEncode(settings), flush: true);
  }

  Future<bool> _confirm(String title, String message) async => await showDialog<bool>(context: context, builder: (context) => AlertDialog(
    title: Text(title), content: Text(message), actions: [TextButton(onPressed: () => Navigator.pop(context,false), child: Text(tr('CANCEL','CANCELAR'))), TextButton(onPressed: () => Navigator.pop(context,true), child: Text(tr('CONFIRM','CONFIRMAR')))],
  )) ?? false;

  Future<void> _manageGames() async {
    if (!mounted) return;
    final game = await showDialog<GameEntry>(context: context, builder: (context) => SimpleDialog(
      title: Text(tr('Delete Imported Games','Eliminar juegos importados')),
      children: _games.map((game) => SimpleDialogOption(onPressed: () => Navigator.pop(context,game), child: Text('${game.system} · ${game.title}'))).toList(),
    ));
    if (game == null || !await _confirm(tr('Delete game?','¿Eliminar juego?'),game.title)) return;
    final root = await _libraryDir();
    final updated = _games.where((entry) => entry.romPath != game.romPath).toList();
    await _saveLibrary(root,updated);
    // The imported copy is removed; the original selected file stays on the user's drive.
    final file = File(game.romPath);
    if (file.absolute.path.startsWith('${root.absolute.path}${Platform.pathSeparator}') && await file.exists()) await file.delete();
    if (mounted) setState(() { _games = updated; _selected = 0; });
  }

  Future<void> _manageSaves() async {
    final root = await _libraryDir();
    final files = <File>[];
    for (final folder in ['saves','states']) {
      final directory = Directory('${root.path}/$folder');
      if (await directory.exists()) files.addAll(await directory.list(recursive:true).where((entry) => entry is File).cast<File>().toList());
    }
    if (!mounted) return;
    final selected = await showDialog<File>(context: context,builder: (context) => SimpleDialog(
      title: Text(tr('Manage Game Saves','Administrar partidas guardadas')),
      children: files.isEmpty ? [Padding(padding: const EdgeInsets.all(20),child: Text(tr('No saved games yet','Todavía no hay partidas guardadas')))] : files.map((file) => SimpleDialogOption(onPressed: () => Navigator.pop(context,file), child: Text(file.path.substring(root.path.length+1)))).toList(),
    ));
    if (selected != null && await _confirm(tr('Delete save?','¿Borrar partida?'),_baseName(selected.path))) await selected.delete();
  }

  Future<void> _clearSaves() async {
    if (!await _confirm(tr('Clear ALL Game Saves','Borrar TODAS las partidas guardadas'),tr('This permanently removes saved progress.','Esto elimina permanentemente las partidas guardadas.'))) return;
    final root = await _libraryDir();
    for (final name in ['saves','states']) {
      final dir = Directory('${root.path}/$name');
      if (await dir.exists()) await dir.delete(recursive:true);
    }
  }

  Future<void> _importWindowsCore(String system) async {
    final selected = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['dll']);
    if (selected?.path == null) return;
    final root = await _libraryDir();
    final destination = File('${root.path}/cores/${system.replaceAll(' ','_')}.dll');
    await destination.parent.create(recursive:true);
    await File(selected!.path!).copy(destination.path);
    final settings = await _preferences();
    final cores = Map<String,dynamic>.from(settings['cores'] as Map? ?? {});
    cores[system] = destination.path; settings['cores'] = cores;
    await _writePreferences(settings);
    if (mounted) setState(() => _message = '${tr('Core imported','Core importado')}: $system');
  }

  Future<void> _androidSettings() async {
    final settings = await _preferences();
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (context) => StatefulBuilder(builder: (context,update) => AlertDialog(
      title: Text(tr('SETTINGS','AJUSTES')),
      content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(tr('Language: English','Idioma: Español')), onTap: () async { setState(() => _spanish = !_spanish); update(() {}); final latest = await _preferences(); latest['spanish'] = _spanish; await _writePreferences(latest); }),
        SwitchListTile(title: Text(tr('Music','Música')), value: _music, onChanged: (value) async { setState(() => _music = value); update(() {}); if (value) { MenuMusic.play(); } else { MenuMusic.stop(); } final latest = await _preferences(); latest['music'] = value; await _writePreferences(latest); }),
        SwitchListTile(title: Text(tr('Smooth image','Suavizar imagen')), value: settings['smooth'] as bool? ?? true, onChanged: (value) async { update(() => settings['smooth'] = value); final latest = await _preferences(); latest['smooth'] = value; await _writePreferences(latest); }),
        ListTile(title: Text(tr('Controllers','Mandos')), subtitle: Text(tr('SDL2 automatic mapping · Select + Down: Exit menu · Start twice: Pause','Mapeo SDL2 automático · Select + abajo: Menú de salida · Start dos veces: Pausa'))),
        for (final system in _systems.keys) ListTile(title: Text('${tr('Import core','Importar core')}: $system'), onTap: () => _importWindowsCore(system)),
        ListTile(title: Text(tr('Delete Imported Games','Eliminar juegos importados')), onTap: () { Navigator.pop(context); _manageGames(); }),
        ListTile(title: Text(tr('Manage Game Saves','Administrar partidas guardadas')), onTap: () { Navigator.pop(context); _manageSaves(); }),
        ListTile(title: Text(tr('Clear ALL Game Saves','Borrar TODAS las partidas guardadas')), onTap: () { Navigator.pop(context); _clearSaves(); }),
        ListTile(title: Text(tr('Reset RetroBox','Restablecer RetroBox')), onTap: () async { Navigator.pop(context); if (!await _confirm(tr('Reset RetroBox?','¿Restablecer RetroBox?'),tr('Delete imported games, settings and saves?','¿Eliminar juegos importados, ajustes y partidas?'))) return; final root = await _libraryDir(); await root.delete(recursive:true); if (mounted) setState(() { _games = []; _selected = 0; _current = 0; _message = null; }); await _loadPreferences(); }),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('← Back to Games','← Volver a los juegos')))],
    )));
  }
}
