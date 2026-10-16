import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retrobox/libretro_player.dart';

void main() {
  testWidgets('Missing core presents startup error instead of endless loading', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibretroPlayer(
      title: 'Missing ROM', romPath: 'does-not-exist.nes', system: 'NES')));
    await tester.pump();
    expect(find.textContaining('startup error:'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
