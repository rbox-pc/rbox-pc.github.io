import 'package:flutter_test/flutter_test.dart';
import 'package:retrobox/windows_gamepads.dart';

void main() {
  test('XInput uses Libretro SNES positions, start and select', () {
    expect(WindowsGamepads.buttonMask(0x1000 | 0x2000 | 0x0030, 0, 0, 0, 0),
        (1 << 0) | (1 << 8) | (1 << 2) | (1 << 3));
  });
  test('analog stick dead zone prevents drift; positive Y means up', () {
    expect(WindowsGamepads.buttonMask(0, 9000, -9000, 30, 30), 0);
    expect(WindowsGamepads.buttonMask(0, -20000, 20000, 255, 0),
        (1 << 6) | (1 << 4) | (1 << 12));
  });
}
