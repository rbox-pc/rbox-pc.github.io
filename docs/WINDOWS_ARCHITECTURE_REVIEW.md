# RetroBox Windows: source audit and implementation decision
Reviewed 2026-10-16.

## Source of truth
- Native baseline: RetroBox_v6_Atari_Memory_Fix_Source(1).zip, Flutter + Dart FFI.
- RetroBox_PC_GPG_v113_SOURCE (3).zip contains an Android/Gradle-based PC/GPG project and substantial historical files. It is not the native Windows executable baseline.
- Android v115 remains a reference for import conventions and business behavior, not a Windows binary.
- Inspected v115 PlayBillingManager: monthly, annual, monthly-distributor and annual-distributor; selects base-plan entries without promotional offer IDs; uses getFormattedPrice from Google Play.
- Google-localized prices do not automatically populate Microsoft's catalogue. Windows needs its own Store product configuration and price retrieval.
- Trial: no trial without promo; valid promo gives seven days through Turbify. Never replace with a 30-day local timer.

## Alternatives checked against upstream sources
| Project | What it provides | Fit for RetroBox |
| --- | --- | --- |
| [RetroArch](https://github.com/libretro/RetroArch) | Mature libretro frontend, Windows audio/input/save handling, many cores | Strongest existing reference for five-system compatibility. A fork or integration is a substantial product change; GPL and each core's licence need separate consideration. |
| [Mesen](https://github.com/SourMesen/Mesen2) | Multi-system emulator; upstream README lists NES/SNES/GB/GBA/PCE/SMS/GG/WonderSwan | Does not provide the complete requested five-system set as listed. Upstream now points to MesenCE. GPLv3. |
| [ares](https://github.com/ares-emulator/ares) | Accuracy-oriented multi-system native emulator, CLI, Windows builds | Useful alternative component with permissive main licence, but replacing the frontend requires integration and full system/third-party coverage checks. |
| Current RetroBox native frontend | Existing library ZIP import and direct libretro interface | Preserves current project and branding with less migration, but prototype maturity is far below RetroArch. Requires native tests and real gameplay validation. |

Implementation decision for this branch: stabilize the existing frontend first and use upstream libretro ABI as the compatibility contract. Do not rewrite emulator internals. Treat RetroArch as the reference for missing behavior and testing, not as evidence that this prototype already has equivalent compatibility.

## Distribution constraint
No core DLLs, ROMs or BIOS are shipped by CI. In particular, [Genesis Plus GX's upstream README](https://github.com/libretro/Genesis-Plus-GX) explicitly describes a non-commercial licence. Its prototype filename is not authorization to bundle it in a subscription app. [RetroArch COPYING](https://github.com/libretro/RetroArch/blob/master/COPYING) and [ares LICENSE](https://github.com/ares-emulator/ares/blob/master/LICENSE) must be checked with the exact components and distribution plan before release.

## Done in source
Keyboard, four XInput player ports, SRAM and explicit states, BIOS directory callbacks, WinMM stereo buffering, reported core FPS, BIOS import, native diagnostic fixture and Windows CI.

## Release gates still open
- Successful Windows build and diagnostic tests.
- Actual Atari/Jungle Hunt, NES, SNES, Genesis and Arcade tests with exact Windows x64 cores.
- Sound, controller assignments, focus loss, unplug/reconnect, four-player games.
- DirectInput-only controller support and remapping.
- Cheat selection/execution and game-specific mappings.
- Turbify Windows identity, signed entitlements, promo validation and purchase verification. Android Play Integrity is not a Windows implementation.
- Microsoft Store product IDs and Partner Center setup; four plans and localized Store prices.
- MSIX identity, signing and Store submission.
- Licence-compatible core distribution and source/notice packaging.

## PC acceptance test
Back up Documents/RetroBoxLibrary first. Use a fresh app folder.
1. Put compatible x64 core DLLs under emulator beside retrobox.exe.
2. Import a user-owned ZIP with roms/covers/cheats/bios; check Contra.nes.png matches Contra.nes.
3. Test every console, sound, 10 minutes of frame pacing and pause/focus behavior.
4. Save state, close game, reopen, restore; test SRAM independently.
5. Connect up to four XInput-compatible controllers and verify independent players in a supported game.
6. Repeat after replacing the app executable, leaving the data directory intact.

Passing CI is evidence about build and diagnostic invariants, not proof that real games or Store billing work.
