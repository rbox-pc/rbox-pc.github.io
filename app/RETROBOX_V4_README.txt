RetroBox v4 - NES integration prototype (Windows)

This is a FIRST-PASS UNTESTED build. It reuses FCEUmm through Libretro and Dart FFI.
It is not yet production-ready and does not implement licensing, audio, save states,
or iOS runtime support. The original Android v114 is unaffected.

1. Back up your existing C:\RetroBox-iOS\retrobox folder.
2. Extract this ZIP to a SEPARATE folder, e.g. C:\RetroBox-iOS\retrobox-v4.
3. Create the 'emulator' subfolder inside retrobox-v4.
4. Copy your existing working fceumm_libretro.dll from
   C:\RetroBox-iOS\retrobox\emulator\fceumm_libretro.dll
   into retrobox-v4\emulator\fceumm_libretro.dll.
5. Open PowerShell in retrobox-v4, then run:
   flutter pub get
   flutter run -d windows
6. Open NES, select Contra. Report any build/runtime errors verbatim.

IMPORTANT: The ZIP does NOT include the DLL, ROMs, BIOS or any copyrighted games.
Video is rendered as Flutter RGBA images; on-screen NES controls are experimental.
Audio is deliberately disabled until core video/input work. Avoid using this as a
release build. No security hardening has been added yet; it must be integrated
with platform-specific verification and a server-verified entitlement system.

Technical caution: Libretro callbacks run synchronously. Native core faults can
terminate the process. This is a test integration, not a hardened emulator host.
