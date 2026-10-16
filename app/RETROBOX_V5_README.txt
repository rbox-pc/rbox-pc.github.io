RetroBox v5 — Windows five-console Libretro prototype

WHAT CHANGED
- Reuses the successful FCEUmm Libretro frontend for Atari 2600, NES, SNES, Sega Genesis, and Arcade.
- Selects core by console and accepts the ROM path already stored in your library.
- Supports both Libretro need_fullpath and memory-data loading (core-dependent).
- Retains v4 interface, import library, cover art and on-screen input.
- Shows clear missing-DLL errors instead of claiming that Android .so files work on Windows.

SETUP
1. Extract to a NEW folder. Do not overwrite working v4 or Android v114.
2. Copy existing working fceumm_libretro.dll into the emulator subfolder.
3. Other systems need WINDOWS x64 DLLs with the exact filenames in emulator/README.txt.
4. From the extracted folder run: flutter pub get ; flutter run -d windows
5. Test NES Contra first, then test each additional system after installing its DLL.

KNOWN LIMITATIONS
- Only NES has been verified on the user's PC. Other systems are UNTESTED pending native DLLs.
- Audio not enabled; video crop and controller mappings still need refinement.
- FBNeo ROM sets must match the core version; BIOS (e.g. Neo Geo) may be needed.
- Existing importer extracts ZIPs; Arcade ZIP sets may need preservation as ZIP files.
- No iOS binaries, paid licensing, Play Integrity, Apple App Attest or anti-cloning protection.
- Cores/ROMs/BIOS not bundled. Non-commercial core licenses prevent bundling some
  cores in a paid product without separate authorization.
- Windows FFI native crashes can terminate the process. Prototype only.
