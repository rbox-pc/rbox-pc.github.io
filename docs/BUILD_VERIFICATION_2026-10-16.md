# Windows prototype verification — 2026-10-16

Source tested: 5601d9ed75fc6861bc6a190b3782c539c4188d82.
[GitHub Actions run](https://github.com/rbox-pc/rbox-pc.github.io/actions/runs/38921423894)

Confirmed successful steps:
- Dependency resolution with Flutter 3.47.7 / Dart 3.13.5.
- Dart analysis.
- Windows C11 diagnostic DLL compilation.
- Flutter tests, including diagnostic native bridge tests and controller mapping tests.
- Windows x64 release build.
- Upload of RetroBox-Windows-x64-prototype artifact, 12,003,895 bytes.

Artifact SHA-256: 50633c8844f5f89a9534644d02cab8b086e7f4468c34ed4157411f8279e1b279.
Artifact retention ends 2026-10-30.

The diagnostic DLL exercises supplied memory/audio/video callbacks and saves.
It is a test fixture, not a real console core, and is not part of the release artifact.
Passing these checks does not verify audible sound from real games, real controllers,
actual Atari/Arcade compatibility, Store licensing, payments, or installation on the user's PC.

Runtime core DLLs and BIOS must be supplied separately for prototype testing.
Production licensing and billing remain unimplemented; this build must not be
presented as a commercially ready RetroBox release.
