import 'dart:io';
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
      await tester.pumpWidget(const RetroBoxApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final name in ['Atari 2600','NES','SNES','Sega Genesis','Arcade']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('＋  AGREGAR JUEGOS'),findsOneWidget);
      expect(find.textContaining('Licencia'),findsNothing);
      await tester.tap(find.text('⚙  AJUSTES'));
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
