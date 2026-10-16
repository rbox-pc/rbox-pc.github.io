import 'dart:convert';
import 'dart:io';
import 'libretro_player.dart';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const RetroBoxApp());

const _systems = <String, ({String subtitle, IconData icon, List<String> extensions})>{
  'Atari 2600': (subtitle: 'Classic Atari games', icon: Icons.sports_esports, extensions: ['a26', 'bin']),
  'NES': (subtitle: 'Nintendo Entertainment System', icon: Icons.videogame_asset, extensions: ['nes']),
  'SNES': (subtitle: 'Super Nintendo', icon: Icons.gamepad, extensions: ['sfc', 'smc']),
  'Sega Genesis': (subtitle: '16-bit Sega games', icon: Icons.sports_esports, extensions: ['md', 'gen', 'smd']),
  'Arcade': (subtitle: 'Classic arcade games', icon: Icons.casino, extensions: ['zip']),
};

class RetroBoxApp extends StatelessWidget {
  const RetroBoxApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RetroBox',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF101219),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF65B4FF), brightness: Brightness.dark),
        ),
        home: const RetroBoxHome(),
      );
}

class GameEntry {
  final String system;
  final String title;
  final String romPath;
  final String? coverPath;
  final String? cheatPath;

  const GameEntry({required this.system, required this.title, required this.romPath, this.coverPath, this.cheatPath});

  factory GameEntry.fromJson(Map<String, dynamic> j) => GameEntry(
        system: j['system'] as String,
        title: j['title'] as String,
        romPath: j['romPath'] as String,
        coverPath: j['coverPath'] as String?,
        cheatPath: j['cheatPath'] as String?,
      );

  Map<String, dynamic> toJson() => {'system': system, 'title': title, 'romPath': romPath, 'coverPath': coverPath, 'cheatPath': cheatPath};
}

class RetroBoxHome extends StatefulWidget {
  const RetroBoxHome({super.key});

  @override
  State<RetroBoxHome> createState() => _RetroBoxHomeState();
}

class _RetroBoxHomeState extends State<RetroBoxHome> {
  List<GameEntry> _games = [];
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<Directory> _libraryDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}RetroBoxLibrary');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _loadLibrary() async {
    try {
      final root = await _libraryDir();
      final index = File('${root.path}${Platform.pathSeparator}library.json');
      if (!await index.exists()) return;
      final decoded = jsonDecode(await index.readAsString()) as List<dynamic>;
      if (mounted) setState(() => _games = decoded.map((e) => GameEntry.fromJson(e as Map<String, dynamic>)).toList());
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not load library: $e');
    }
  }

  Future<void> _saveLibrary(Directory root, List<GameEntry> games) async {
    final index = File('${root.path}${Platform.pathSeparator}library.json');
    await index.writeAsString(jsonEncode(games.map((g) => g.toJson()).toList()), flush: true);
  }

  String _baseName(String path) => path.replaceAll('\\', '/').split('/').last;
  String _stem(String path) {
    final name = _baseName(path);
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String _extension(String path) {
    final name = _baseName(path).toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1);
  }

  String? _systemFor(String path) {
    final normalized = '/${path.replaceAll('\\', '/').toLowerCase()}/';
    if (normalized.contains('/nes/') || normalized.contains('/nintendo/')) return 'NES';
    if (normalized.contains('/snes/') || normalized.contains('/super nintendo/')) return 'SNES';
    if (normalized.contains('/sega/') || normalized.contains('/genesis/') || normalized.contains('/megadrive/')) return 'Sega Genesis';
    if (normalized.contains('/atari/') || normalized.contains('/atari 2600/')) return 'Atari 2600';
    if (normalized.contains('/arcade/') || normalized.contains('/mame/') || normalized.contains('/fbneo/')) return 'Arcade';
    final ext = _extension(path);
    if (ext == 'nes') return 'NES';
    if (ext == 'sfc' || ext == 'smc') return 'SNES';
    if (['md', 'gen', 'smd'].contains(ext)) return 'Sega Genesis';
    if (ext == 'a26') return 'Atari 2600';
    // .bin and .zip are ambiguous without a console folder.
    return null;
  }

  bool _isSafePath(String path) {
    final clean = path.replaceAll('\\', '/');
    return !clean.startsWith('/') && !RegExp(r'^[A-Za-z]:').hasMatch(clean) && !clean.split('/').contains('..');
  }

  Future<void> _importZip() async {
    if (_busy) return;
    final chosen = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (chosen == null) return;
    setState(() { _busy = true; _message = 'Importing ZIP...'; });
    try {
      final bytes = await chosen.readAsBytes();
      if (bytes.length > 500 * 1024 * 1024) throw const FormatException('ZIP exceeds 500 MB demo limit');
      final archive = ZipDecoder().decodeBytes(bytes);
      final root = await _libraryDir();
      final files = <String, String>{};
      final roms = <({String system, String title, String path})>[];
      var extractedBytes = 0;
      var skipped = 0;

      for (final item in archive) {
        if (!item.isFile) continue;
        final original = item.name.replaceAll('\\', '/');
        if (!_isSafePath(original)) { skipped++; continue; }
        final ext = _extension(original);
        final lower = original.toLowerCase();
        final isCover = ['png', 'jpg', 'jpeg', 'webp'].contains(ext);
        final isCheat = ['cht', 'ini', 'xml', 'json'].contains(ext) && (lower.contains('cheat') || ext == 'cht');
        final system = _systemFor(original);
        final isRom = system != null && _systems[system]!.extensions.contains(ext);
        if (!isCover && !isCheat && !isRom) { skipped++; continue; }
        extractedBytes += item.size;
        if (extractedBytes > 1024 * 1024 * 1024) throw const FormatException('Extracted content exceeds 1 GB demo limit');
        final data = item.readBytes();
        if (data == null) { skipped++; continue; }
        // Use a stable, sanitized destination name; never trust paths from inside the ZIP.
        final safeName = original.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final folder = isRom ? 'roms' : isCover ? 'covers' : 'cheats';
        final destination = File('${root.path}${Platform.pathSeparator}$folder${Platform.pathSeparator}$safeName');
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(data, flush: true);
        files[original.toLowerCase()] = destination.path;
        if (isRom) roms.add((system: system, title: _stem(original), path: destination.path));
      }

      // Android ZIP convention: covers/NES/Game.nes.png -> roms/NES/Game.nes
      // Match by full ROM filename first, then by title without extension.
      String keyFor(String name) => _baseName(name).toLowerCase();
      final coverLookup = <String, String>{};
      final cheatLookup = <String, String>{};
      for (final entry in files.entries) {
        final name = keyFor(entry.key);
        final ext = _extension(name);
        if (['png', 'jpg', 'jpeg', 'webp'].contains(ext)) {
          coverLookup['${_systemFor(entry.key) ?? ''}|${_stem(name)}'] = entry.value; // e.g. Game.nes
        } else if (['cht', 'ini', 'xml', 'json'].contains(ext) && entry.key.contains('cheat')) {
          cheatLookup['${_systemFor(entry.key) ?? ''}|${_stem(name)}'] = entry.value;
        }
      }
      String? findCover(String title, String system) {
        final extension = _systems[system]!.extensions;
        for (final ext in extension) {
          final exact = coverLookup['$system|${title.toLowerCase()}.$ext'];
          if (exact != null) return exact;
        }
        return coverLookup['$system|${title.toLowerCase()}'];
      }
      String? findCheat(String title, String system) {
        for (final ext in _systems[system]!.extensions) {
          final exact = cheatLookup['$system|${title.toLowerCase()}.$ext'];
          if (exact != null) return exact;
        }
        return cheatLookup['$system|${title.toLowerCase()}'];
      }

      // Update existing records as well, without duplicating their ROMs.
      final updated = <GameEntry>[];
      final newKeys = roms.map((r) => '${r.system}|${r.title.toLowerCase()}').toSet();
      for (final old in _games) {
        if (newKeys.contains('${old.system}|${old.title.toLowerCase()}')) continue;
        updated.add(GameEntry(
          system: old.system, title: old.title, romPath: old.romPath,
          coverPath: findCover(old.title, old.system) ?? old.coverPath,
          cheatPath: findCheat(old.title, old.system) ?? old.cheatPath,
        ));
      }
      for (final rom in roms) {
        updated.add(GameEntry(
          system: rom.system,
          title: rom.title,
          romPath: rom.path,
          coverPath: findCover(rom.title, rom.system),
          cheatPath: findCheat(rom.title, rom.system),
        ));
      }
      updated.sort((a, b) {
        final systemCompare = a.system.compareTo(b.system);
        return systemCompare != 0 ? systemCompare : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
      final matchedCovers = updated.where((g) => g.coverPath != null).length;
      final matchedCheats = updated.where((g) => g.cheatPath != null).length;
      await _saveLibrary(root, updated);
      if (mounted) setState(() { _games = updated; _message = 'Imported ${roms.length} ROM(s). Matched $matchedCovers cover(s), $matchedCheats cheat file(s). Skipped $skipped unsupported file(s).'; });
    } catch (e) {
      if (mounted) setState(() => _message = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('RetroBox'), centerTitle: true, actions: [
          IconButton(tooltip: 'Import ZIP', onPressed: _busy ? null : _importZip, icon: const Icon(Icons.folder_zip_outlined)),
        ]),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          const Text('Your retro consoles', style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Choose a console to view its game library.', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 18),
          FilledButton.icon(onPressed: _busy ? null : _importZip, icon: const Icon(Icons.file_upload_outlined), label: Text(_busy ? 'Importing...' : 'Import games ZIP')),
          if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(_message!, style: const TextStyle(color: Colors.white70))),
          const SizedBox(height: 10),
          ..._systems.entries.map((entry) => Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                  leading: Icon(entry.value.icon, color: const Color(0xFF65B4FF), size: 32),
                  title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${entry.value.subtitle} · ${_games.where((g) => g.system == entry.key).length} games'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameLibraryScreen(system: entry.key, games: _games.where((g) => g.system == entry.key).toList()))),
                ),
              )),
        ]),
      );
}

class GameLibraryScreen extends StatelessWidget {
  final String system;
  final List<GameEntry> games;
  const GameLibraryScreen({super.key, required this.system, required this.games});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(system)),
        body: games.isEmpty
            ? const Center(child: Text('No games imported yet.\nGo back and tap Import games ZIP.', textAlign: TextAlign.center))
            : ListView.builder(
                itemCount: games.length,
                itemBuilder: (context, index) {
                  final game = games[index];
                  final cover = game.coverPath == null ? null : File(game.coverPath!);
                  return ListTile(
                    leading: cover != null && cover.existsSync()
                        ? Image.file(cover, width: 50, height: 60, fit: BoxFit.cover)
                        : const Icon(Icons.videogame_asset, size: 38),
                    title: Text(game.title),
                    subtitle: Text('ROM imported${game.cheatPath != null ? ' · Cheats found' : ''}'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LibretroPlayer(title: game.title, romPath: game.romPath, system: game.system))),
                  );
                },
              ),
      );
}
