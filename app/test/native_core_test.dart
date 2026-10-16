import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:retrobox/libretro_core.dart';

void main() {
  test('Native bridge retains ROM, translates pixels/audio, supports player 2 and persists saves', () {
    final root = Directory.systemTemp.createTempSync('retrobox-bridge-');
    final rom = File('${root.path}/test.nes')..writeAsBytesSync([42]);
    LibretroCore open() {
      final core = LibretroCore.fromPath('test/native/core_fixture.dll');
      core.load(rom.path, systemDirectory: '${root.path}/bios', saveDirectory: '${root.path}/saves');
      return core;
    }
    LibretroCore? core;
    try {
      core = open();
      expect(core.fps, 50);
      expect(core.sampleRate, 48000);
      core.gamepads[1] = 1 << 8;
      core.runFrame();
      expect(core.latestFrame, [255,0,0,255,0,255,0,255]);
      expect(core.takeAudio(), [100,-100,200,-200]);
      core.saveState();
      core.saveSram();
      expect(File('${root.path}/saves/test.nes.srm').readAsBytesSync().take(2), [42,1]);
      core.gamepads[1] = 0;
      core.runFrame();
      core.loadState();
      core.saveSram();
      expect(File('${root.path}/saves/test.nes.srm').readAsBytesSync()[1], 1);
      core.dispose();
      core = open();
      core.saveSram();
      expect(File('${root.path}/saves/test.nes.srm').readAsBytesSync().take(2), [42,1]);
    } finally {
      core?.dispose();
      root.deleteSync(recursive: true);
    }
  }, skip: !Platform.isWindows || !File('test/native/core_fixture.dll').existsSync());
}
