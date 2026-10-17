import 'package:flutter_test/flutter_test.dart';
import 'package:retrobox/retroarch_player.dart';
import 'package:retrobox/game_names.dart';

void main() {
  test('Android v115 title aliases preserve recognizable game names', () {
    expect(displayGameName('Arcade','snowbros.zip'),'Snow Bros.');
    expect(displayGameName('Atari 2600','Pole Positition (USA).a26'),'Pole Position');
    expect(displayGameName('NES','Contra (USA) [!].nes'),'Contra');
  });
  test('All five systems have a bundled Windows core', () {
    expect(bundledCores.keys, containsAll(['Atari 2600', 'NES', 'SNES', 'Sega Genesis', 'Arcade']));
    expect(bundledCores.values.toSet().length, 5);
    expect(bundledCores.values.every((name) => name.endsWith('_libretro.dll')), isTrue);
  });
  test('Config paths preserve spaces and normalize Windows separators', () {
    expect(configValue(r'C:\Users\Roberto Flores\ROMs'), '"C:/Users/Roberto Flores/ROMs"');
  });
  test('Config values reject injected newlines and quote delimiters', () {
    expect(() => configValue('ROM\nvideo_fullscreen = false'), throwsFormatException);
    expect(() => configValue('ROM"'), throwsFormatException);
  });
}
