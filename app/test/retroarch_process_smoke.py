"""Run the packaged engine, not a substitute, with an original diagnostic NES ROM.

The ROM only sets a blue background and loops. It contains no third-party game
data. This checks loading, stdin SAVE_STATE/QUIT and the exact .state.auto path;
it does not establish that a commercial game, controller or audio works.
"""
import pathlib
import subprocess
import sys
import tempfile
import time


def run(engine: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory(prefix="retrobox-engine-") as temporary:
        root = pathlib.Path(temporary)
        # Original 6502 diagnostic, NROM-128. Disable interrupts/rendering,
        # initialize one palette entry, enable background and loop forever.
        program = bytes.fromhex(
            "78 d8 a2 ff 9a e8 8e 00 20 8e 01 20 "
            "2c 02 20 10 fb a9 3f 8d 06 20 a9 00 8d 06 20 "
            "a9 21 8d 07 20 a9 08 8d 01 20 4c 26 80"
        )
        prg = bytearray([0xEA] * 16384)
        prg[:len(program)] = program
        for offset in (0x3FFA, 0x3FFC, 0x3FFE):
            prg[offset:offset + 2] = bytes([0x00, 0x80])
        rom = root / "diagnostic.nes"
        rom.write_bytes(b"NES\x1a" + bytes([1, 1]) + bytes(10) + prg + bytes(8192))
        state = root / "diagnostic.state"
        config = root / "smoke.cfg"
        config.write_text(
            'video_driver = "gdi"\nvideo_fullscreen = false\n'
            'audio_enable = false\npause_nonactive = false\n'
            'stdin_cmd_enable = true\nnetwork_cmd_enable = false\n'
            'state_slot = -1\nsavestate_auto_save = false\n'
            'savestate_auto_load = false\nconfig_save_on_exit = false\n'
            'menu_driver = "rgui"\nui_companion_start_on_boot = false\n',
            encoding="utf-8",
        )
        log = root / "smoke.log"
        with log.open("wb") as output:
            process = subprocess.Popen(
                [str(engine), "--verbose", "--config", str(config), "-S", str(state),
                 "-L", str(engine.parent / "cores/fceumm_libretro.dll"), str(rom)],
                cwd=engine.parent, stdin=subprocess.PIPE, stdout=output, stderr=output,
            )
            try:
                deadline = time.monotonic() + 30
                expected = pathlib.Path(str(state) + ".auto")
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise RuntimeError(f"Engine exited before saving: {process.returncode}")
                    process.stdin.write(b"SAVE_STATE\n")
                    process.stdin.flush()
                    time.sleep(0.25)
                    if expected.exists() and expected.stat().st_size > 0:
                        break
                else:
                    raise RuntimeError("SAVE_STATE did not produce diagnostic.state.auto")
                process.stdin.write(b"QUIT\n")
                process.stdin.flush()
                result = process.wait(timeout=15)
                if result != 0:
                    raise RuntimeError(f"QUIT returned {result}")
                print(f"Engine opened original diagnostic ROM; SAVE_STATE wrote {expected.stat().st_size} bytes; QUIT returned 0.")
            except BaseException:
                if process.poll() is None:
                    process.kill()  # CI diagnostic only; never user game data.
                    process.wait()
                print(log.read_text(encoding="utf-8", errors="replace"))
                raise


if __name__ == "__main__":
    run(pathlib.Path(sys.argv[1]).resolve())
