part of 'main.dart';

const _androidLabels = ['ATARI 2600','NES','SUPER NES','SEGA GENESIS','ARCADE'];
const _androidArt = ['atari', 'nes', 'snes', 'sega', 'arcade'];
const _accent = Color(0xFF46C2FF);

class RetroButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;
  final VoidCallback? onFocus;
  const RetroButton({super.key, required this.child, this.onPressed, this.selected = false, this.onFocus});
  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (value) { setState(() => focused = value); if (value) widget.onFocus?.call(); },
    child: OutlinedButton(
      onPressed: widget.onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: focused ? const Color(0xFF2B3642) : const Color(0xFF171A20),
        side: BorderSide(color: focused || widget.selected ? _accent : const Color(0xFF2B313A), width: focused ? 3 : 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      child: widget.child,
    ),
  );
}

extension AndroidHome on _RetroBoxHomeState {
  String tr(String en, String es) => _spanish ? es : en;
  List<GameEntry> get currentGames => _games.where((game) => game.system == _systems.keys.elementAt(_current)).toList();

  void _changeSystem(int index) => _refresh(() { _current = index; _selected = 0; });

  Future<void> _play(GameEntry game) async {
    MenuMusic.stop();
    try {
      String? selectedCheats;
      if (game.cheatPath != null) {
        final useCheats = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
          title: Text(game.title), content: Text(tr('Use cheats?', '¿Usar trucos?')),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('NO', 'NO'))),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('YES', 'SÍ')))],
        )) ?? false;
        if (useCheats) selectedCheats = await _selectCheats(game);
      }
      if (!mounted) return;
      _playing = true;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RetroArchPlayer(
        title: game.title, romPath: game.romPath, system: game.system,
        cheatPath: selectedCheats, spanish: _spanish,
      )));
    } finally { _playing = false; if (_music) MenuMusic.play(); }
  }

  Future<String?> _selectCheats(GameEntry game) async {
    final source = File(game.cheatPath!);
    if (!source.path.toLowerCase().endsWith('.cht')) {
      if (mounted) await showDialog<void>(context: context,builder: (context) => AlertDialog(
        title: Text(tr('Cheat format','Formato de trucos')),
        content: Text(tr('This core uses RetroArch .cht files. The imported file is preserved. The game will start without cheats.','Este core usa archivos .cht de RetroArch. El archivo importado se conserva. El juego comenzará sin trucos.')),
        actions: [TextButton(onPressed: () => Navigator.pop(context),child: const Text('OK'))],
      ));
      return null;
    }
    var text = await source.readAsString();
    final count = int.tryParse(RegExp(r'(?m)^cheats\s*=\s*"?(\d+)').firstMatch(text)?.group(1) ?? '') ?? 0;
    if (count < 1 || count > 1000) return null;
    final enabled = List<bool>.filled(count,false);
    final names = List<String>.generate(count,(i) => RegExp('(?m)^cheat${i}_desc\\s*=\\s*"([^"\\r\\n]*)"').firstMatch(text)?.group(1) ?? '${tr('Cheat','Truco')} ${i+1}');
    if (!mounted) return null;
    final apply = await showDialog<bool>(context: context,builder: (context) => StatefulBuilder(builder: (context,update) => AlertDialog(
      title: Text(tr('Choose cheats','Elige los trucos')),
      content: SizedBox(width: 520,height: 300,child: ListView.builder(itemCount: count,itemBuilder: (_,i) => CheckboxListTile(title: Text(names[i]),value: enabled[i],onChanged: (value) => update(() => enabled[i] = value ?? false)))),
      actions: [TextButton(onPressed: () => Navigator.pop(context,false),child: Text(tr('CANCEL','CANCELAR'))),TextButton(onPressed: () => Navigator.pop(context,true),child: Text(tr('PLAY','JUGAR')))],
    )));
    if (apply != true) return null;
    for (var i = 0; i < count; i++) {
      final pattern = RegExp('(?m)^cheat${i}_enable\\s*=.*');
      final value = 'cheat${i}_enable = ${enabled[i]}';
      text = pattern.hasMatch(text) ? text.replaceAll(pattern,value) : '$text\n$value';
    }
    final root = await _libraryDir();
    final file = File('${root.path}/selected-cheats.cht');
    await file.writeAsString(text,flush:true);
    return file.path;
  }

  Future<void> _sourcePicker() async {
    final source = await showDialog<String>(context: context, builder: (context) => SimpleDialog(
      title: Text(tr('ADD YOUR GAMES', 'AGREGAR JUEGOS')),
      children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(context, 'file'), child: Padding(padding: const EdgeInsets.all(15), child: Text(tr('USB / DEVICE STORAGE', 'USB / ALMACENAMIENTO')))),
        SimpleDialogOption(onPressed: () => Navigator.pop(context, 'url'), child: Padding(padding: const EdgeInsets.all(15), child: Text(tr('WEBSITE / LINK', 'SITIO WEB / ENLACE')))),
      ],
    ));
    if (source == 'file') {
      final chosen = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['zip','nes','sfc','smc','md','gen','smd','a26','bin']);
      if (chosen == null) return;
      final bytes = await chosen.readAsBytes();
      if (_extension(chosen.name) == 'zip') {
        // An Arcade ROM is already a ZIP. A package has category folders inside.
        final archive = ZipDecoder().decodeBytes(bytes);
        final isPackage = archive.any((entry) => RegExp(r'(^|/)(roms|covers|cheats|cores|emulators|bios|system)/', caseSensitive: false).hasMatch(entry.name.replaceAll('\\', '/'))) || archive.any((entry) => ['nes','sfc','smc','md','gen','smd','a26','dll'].contains(_extension(entry.name)));
        if (isPackage) { await _importZip(bytes); } else { await _importRom(chosen.path); }
      } else { await _importRom(chosen.path); }
    } else if (source == 'url') { await _urlImport(); }
  }

  Future<void> _urlImport() async {
    final input = TextEditingController();
    final url = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(tr('WEBSITE / LINK', 'SITIO WEB / ENLACE')),
      content: TextField(controller: input, autofocus: true, decoration: const InputDecoration(hintText: 'https://')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('CANCEL', 'CANCELAR'))),
        TextButton(onPressed: () => Navigator.pop(context, input.text.trim()), child: Text(tr('OPEN', 'ABRIR')))],
    ));
    input.dispose();
    if (url == null || url.isEmpty) return;
    _refresh(() { _busy = true; _message = tr('Downloading…', 'Descargando…'); });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      var uri = Uri.parse(url.contains('://') ? url : 'https://$url');
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!['https','http'].contains(uri.scheme)) throw const FormatException('HTTP/HTTPS requerido');
        final response = await (await client.getUrl(uri)).close();
        if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
        final content = BytesBuilder(copy: false);
        var received = 0;
        await for (final bytes in response.timeout(const Duration(seconds: 60))) {
          received += bytes.length;
          if (received > 500 * 1024 * 1024) throw const FormatException('Máximo 500 MB');
          content.add(bytes);
          if (mounted) _refresh(() => _message = '${tr('Downloading','Descargando')}: ${response.contentLength > 0 ? '${(received * 100 / response.contentLength).floor()}%' : '${received ~/ 1024} KB'}');
        }
        final bytes = content.takeBytes();
        if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
          if (mounted) _refresh(() => _busy = false);
          await _importZip(bytes);
          return;
        }
        final html = utf8.decode(bytes, allowMalformed: true);
        final match = RegExp(r'''(?:href\s*=\s*["'])([^"']+\.zip(?:\?[^"']*)?)|https?://[^\s"'<>]+\.zip(?:\?[^\s"'<>]*)?''', caseSensitive: false).firstMatch(html);
        if (match == null) throw const FormatException('No se encontró un enlace ZIP en la página');
        uri = uri.resolve((match.group(1) ?? match.group(0)!).replaceAll('&amp;', '&'));
      }
      throw const FormatException('Demasiadas páginas intermedias');
    } catch (error) {
      if (mounted) _refresh(() => _message = '${tr('Import failed','No se pudo importar')}: $error');
    } finally { client.close(force: true); if (mounted) _refresh(() => _busy = false); }
  }

  void _pad(PadEvent event) {
    if (!mounted || _playing) return;
    if (ModalRoute.of(context)?.isCurrent != true) {
      final focus = FocusManager.instance.primaryFocus;
      if (event.button == 11) focus?.previousFocus();
      if (event.button == 12) focus?.nextFocus();
      if ([0,6].contains(event.button) && focus?.context != null) Actions.maybeInvoke(focus!.context!, const ActivateIntent());
      return;
    }
    if (event.button == 11) { _refresh(() => _inGames = false); return; }
    if (event.button == 12) { _refresh(() => _inGames = true); return; }
    if ([13,14].contains(event.button)) {
      final direction = event.button == 13 ? -1 : 1;
      if (!_inGames) { _changeSystem((_current + direction).clamp(0,4)); }
      else if (currentGames.isNotEmpty) {
        _refresh(() => _selected = (_selected + direction).clamp(0,currentGames.length-1));
        if (_carousel.hasClients) _carousel.animateTo((_selected * 196.0).clamp(0,_carousel.position.maxScrollExtent), duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
      }
    }
    if ([0,6].contains(event.button) && !_busy && currentGames.isNotEmpty) {
      if (_inGames) { _play(currentGames[_selected.clamp(0,currentGames.length-1)]); }
      else { _refresh(() => _inGames = true); }
    }
  }

  Widget _cover(GameEntry game) {
    final cover = game.coverPath;
    return cover != null && File(cover).existsSync()
      ? Image.file(File(cover), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.videogame_asset, size: 60, color: _accent))
      : const Icon(Icons.videogame_asset, size: 60, color: _accent);
  }

  Future<void> _exitApp() async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(tr('EXIT RETROBOX?', '¿SALIR DE RETROBOX?')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('CANCEL', 'CANCELAR'))), TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('EXIT', 'SALIR')))],
    ));
    if (yes == true) { MenuMusic.stop(); exit(0); }
  }

  Widget _androidHome() {
    final games = currentGames;
    final system = _systems.keys.elementAt(_current);
    return Scaffold(body: Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final button = key == LogicalKeyboardKey.arrowLeft ? 13 : key == LogicalKeyboardKey.arrowRight ? 14 : key == LogicalKeyboardKey.arrowUp ? 11 : key == LogicalKeyboardKey.arrowDown ? 12 : key == LogicalKeyboardKey.enter ? 6 : null;
        if (button == null) return KeyEventResult.ignored;
        _pad(PadEvent(0,button,{button}));
        return KeyEventResult.handled;
      },
      child: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/android/${_games.isEmpty ? 'retrobox_arcade_background' : 'retrobox_library_background'}.png', fit: BoxFit.fill),
        Padding(padding: const EdgeInsets.fromLTRB(30, 11, 30, 10), child: Column(children: [
          SizedBox(height: 44, child: Row(children: [
            const Expanded(child: FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text.rich(TextSpan(children: [TextSpan(text: 'RETRO', style: TextStyle(color: Colors.white)), TextSpan(text: 'BOX', style: TextStyle(color: Color(0xFF23C4FF)))]), style: TextStyle(fontSize: 29, fontWeight: FontWeight.bold)))),
            RetroButton(onPressed: _busy ? null : _sourcePicker, child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.add,size: 16),const SizedBox(width: 6),Text(tr('ADD YOUR GAMES','AGREGAR JUEGOS'))])),
            const SizedBox(width: 8),
            RetroButton(onPressed: _busy ? null : _engineSettings, child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.settings,size: 16),const SizedBox(width: 6),Text(tr('SETTINGS','AJUSTES'))])),
            const SizedBox(width: 8),
            RetroButton(onPressed: _exitApp, child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.power_settings_new,size: 16),const SizedBox(width: 6),Text(tr('EXIT','SALIR'))])),
          ])),
          Container(height: 23, alignment: Alignment.centerLeft, color: const Color(0x7D000000), padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('$system  •  ${games.length} ${tr('games','juegos')}  •  START = ${tr('Play','Jugar')}  •  ${tr('SETTINGS = Options','AJUSTES = Opciones')}', style: const TextStyle(color: Color(0xFFA9B0BA), fontSize: 13))),
          const SizedBox(height: 5),
          SizedBox(height: 70, child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5,(index) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: RetroButton(
            selected: _current == index, onPressed: () { _changeSystem(index); _inGames = true; },
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Image.asset('assets/android/system_${_androidArt[index]}_realistic.png', width: index == 1 ? 64 : 70, height: 34, fit: BoxFit.contain), Text(_androidLabels[index], style: const TextStyle(fontSize: 11.5), maxLines: 1)]),
          )))))))),
          Expanded(child: games.isEmpty ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: _sourcePicker, child: Center(child: Text(_games.isEmpty ? '' : tr('No $system games added\n\n＋ ADD YOUR GAMES','No hay juegos de $system\n\n＋ AGREGA TUS JUEGOS'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))) : LayoutBuilder(builder: (context, constraints) {
            final height = (constraints.maxHeight-16).clamp(130.0,310.0);
            final width = (height * .77).clamp(150.0,220.0);
            return ListView.separated(controller: _carousel, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), scrollDirection: Axis.horizontal,
              itemCount: games.length, separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context,index) => Center(child: SizedBox(width: width, height: height, child: RetroButton(
                selected: _inGames && _selected == index, onFocus: () => _refresh(() { _selected = index; _inGames = true; }),
                onPressed: () => _play(games[index]),
                child: Column(children: [Expanded(child: _cover(games[index])), const SizedBox(height: 3), SizedBox(height: 48, child: Center(child: Text(displayGameName(games[index].system,_baseName(games[index].romPath)), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))))]),
              ))),
            );
          })),
          if (_message != null) Container(color: Colors.black87, padding: const EdgeInsets.all(5), child: Text(_message!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
          if (_busy) const LinearProgressIndicator(),
          if (games.isNotEmpty) Container(height: 66, padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: const Color(0xCC081018), border: Border.all(color: const Color(0x6639C8FF)), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [Expanded(child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: games.length, itemBuilder: (_,index) => Opacity(opacity: index == _selected ? 1 : .35, child: SizedBox(width: 66, child: Padding(padding: const EdgeInsets.all(4), child: _cover(games[index])))))), SizedBox(width: 130, child: Text('${games.length} ${tr('GAMES','JUEGOS')}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)))])),
          SizedBox(height: 34, child: Center(child: Text('< >  ${tr('Browse','Navegar')}     START  ${tr('Play','Jugar')}     ${tr('SETTINGS  Options','AJUSTES  Opciones')}', style: const TextStyle(color: Color(0xFFBEC6D2), fontSize: 12)))),
        ])),
      ]),
    ));
  }
}
