import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:retrobox/main.dart';

class TestPaths extends PathProviderPlatform {
  final String path;
  TestPaths(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('retrobox-home-test-');
    PathProviderPlatform.instance = TestPaths(root.path);
  });
  tearDown(() async { if (await root.exists()) await root.delete(recursive: true); });

  for (final size in [const Size(1280,720), const Size(800,450)]) {
    testWidgets('Android console carousel fits $size without billing', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: const RetroBoxApp()));
      await tester.runAsync(() async {
        final loader = FontLoader('RetroBoxSans')..addFont(rootBundle.load('assets/android/Roboto.ttf'));
        await loader.load();
        final context = tester.element(find.byType(RetroBoxHome));
        for (final name in ['retrobox_arcade_background','retrobox_library_background','system_atari_realistic','system_nes_realistic','system_snes_realistic','system_sega_realistic','system_arcade_realistic']) {
          await precacheImage(AssetImage('assets/android/$name.png'),context);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final name in ['ATARI 2600','NES','SUPER NES','SEGA GENESIS','ARCADE']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('＋  AGREGAR JUEGOS'),findsOneWidget);
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final folder = Directory('build/ui-preview');
        await folder.create(recursive:true);
        await File('${folder.path}/home-${size.width.toInt()}.png').writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(find.textContaining('Licencia'),findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.text('⚙  AJUSTES'));
        // File-backed preferences finish in the real async zone before animation pumps.
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Música'), findsOneWidget);
      expect(find.text('Administrar partidas guardadas'),findsOneWidget);
      expect(find.textContaining('Google Play'),findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
