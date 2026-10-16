# RetroBox Windows development progress

Base: RetroBox_v6_Atari_Memory_Fix_Source(1).zip. Separate Windows branch.

Implemented, pending Windows CI and gameplay verification:
- Keyboard input: arrows, Z/X/A/S/Q/W, Enter, right Shift; clears on focus loss.
- Four XInput-compatible USB/Bluetooth controllers; independent player ports.
- SRAM restoration, periodic SRAM flush (30 seconds) and flush when closing a game.
- Save/load state buttons; invalid or rejected states report an error.
- BIOS and save directory callbacks with retained native string pointers.
- Replaced stale counter test; added controller mapping/dead-zone tests.

Build artifacts intentionally exclude cores, ROMs and BIOS.
Put compatible Windows x64 Libretro DLLs in emulator beside retrobox.exe:
Atari: stella2014_libretro.dll; NES: fceumm_libretro.dll;
SNES: snes9x2010_libretro.dll; Genesis: genesis_plus_gx_libretro.dll;
Arcade: fbneo_libretro.dll. Commercial distribution licenses require review.

Data remains in Documents/RetroBoxLibrary. BIOS goes in bios, saves in saves/<system>.
Do not replace core versions without backing up states; states can be core-version-specific.

Still pending: audio output, DirectInput-only gamepads, cheat execution, BIOS ZIP import,
Turbify device licensing and Microsoft Store billing/MSIX packaging.
Business rules: 4 plans (monthly/annual, with/without promo); 7-day trial
via Turbify with valid promo; no trial without promo; no 30-day trial.
No payment buttons or placeholder license checks are presented as functional.
NES was previously reported working by the user; all added features need real PC tests.
