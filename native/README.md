# RetroBox Windows native Libretro bridge — implementation plan

The production frontend currently launches bundled retroarch.exe. This folder is the migration boundary, NOT a working replacement engine yet.

## Required native interface
- C ABI with rb_create, rb_load_core, rb_load_game, rb_run_frame, rb_set_input, rb_reset, rb_serialize, rb_unserialize, rb_unload_game, rb_destroy.
- Load only explicit core DLL paths with LoadLibraryW/GetProcAddress. Check required libretro exports and API version.
- Supply retro_environment callback with documented handling of pixel formats, logging, system/save directories, controller descriptors, variable queries, disk control, and VFS requests as needed per core.
- Supply video callback with 0RGB1555, RGB565 and XRGB8888 support; audio sample/batch callbacks; input poll/state callbacks.
- Run emulation on a dedicated thread. Keep rendering/audio queues bounded and synchronize save state operations.
- Preserve per-system saves and states under RetroBoxLibrary; never silently overwrite Android saves.
- Validate each core independently: Stella, FCEUmm, bsnes, BlastEm, MAME. MAME requires special attention to ROM sets and BIOS.
- SDL controller mapping: record SDL button IDs, axis deadzones, device IDs, connect/disconnect, navigation zone and focus.
- Write JSONL structured logs with UTC timestamp, session ID, build SHA, platform, core path/hash, ROM size/hash (no personal file paths in shared reports), load result, frame count, video dimensions, audio underflows, FPS, save result and shutdown reason.
- On Windows native exceptions, generate minidumps using MiniDumpWriteDump with user opt-in and size cap; redact personal paths in export bundles.
- Create deterministic CI smoke tests using legal test ROMs; assert successful core load, >=120 frames, nonempty video, audio callback, input callback, state roundtrip, and clean unload.
- Keep current RetroArch-based version functional until the native bridge passes the full matrix.
- Verify GPL and individual core licenses before any commercial distribution.

## Current diagnostics
- controller-diagnostic.log: SDL button and analog axes.
- navigation-diagnostic.log: controller zone and menu transitions.
- last-session.log: RetroArch stdout/stderr.
- engine-diagnostic.jsonl: launch metadata, PID and exit code.
- engine-exceptions.log: Dart launch exceptions.

Do not describe this document as a compiled engine or proof that the native migration is finished.
