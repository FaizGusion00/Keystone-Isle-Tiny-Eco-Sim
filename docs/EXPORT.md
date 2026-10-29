# Exporting Keystone Isle

Engine: Godot 4.7.2-stable, Compatibility renderer. Bundle / package id: `com.faizgusion.keystoneisle`.
All presets live in `export_presets.cfg` (committed, no secrets). Outputs go to `build/` (gitignored) or any
path you pass on the command line. Data files are included via `include_filter="data/*.json"`; `tests/`, `docs/`, `tools/` are excluded.

```sh
G=/path/to/Godot_v4.7.2-stable
$G --headless --path . --import            # first time / after asset changes
```

## Windows
`$G --headless --path . --export-release "Windows Desktop" build/KeystoneIsle.exe`
Produces a single exe (pck embedded). Unsigned; sign with `signtool` for distribution.

## macOS
`$G --headless --path . --export-release "macOS" build/KeystoneIsle-macOS.zip`
Produces a universal `.app` in a zip. Built on Linux it is **unsigned / not notarized**; on a Mac run
`codesign` + `notarytool` (or configure them in the preset) before shipping. Gatekeeper will otherwise warn.

## Android
Requirements: JDK 17+, Android SDK (platform-tools, build-tools 35+, platform 35/36), set in Godot Editor
Settings (`export/android/java_sdk_path`, `android_sdk_path`). `rendering/textures/vram_compression/import_etc2_astc=true` is enabled in project.godot (required).

Debug keystore (never commit it — `*.keystore`/`*.jks` are gitignored):
```sh
keytool -genkeypair -v -keystore debug.keystore -storepass android -alias androiddebugkey \
  -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
```
Point Godot at it via Editor Settings (`export/android/debug_keystore`) or env vars
`GODOT_ANDROID_KEYSTORE_DEBUG_PATH/_USER/_PASSWORD`. Then:
`$G --headless --path . --export-debug "Android" build/KeystoneIsle-debug.apk`
Verify: `apksigner verify --print-certs build/KeystoneIsle-debug.apk`.
Release: create an upload keystore, use `GODOT_ANDROID_KEYSTORE_RELEASE_*` env vars, and export an AAB
(enable Gradle build) for Google Play. minSdk 24, ABIs arm64-v8a + armeabi-v7a.

## iOS
Needs a Mac with Xcode to build/sign. On any OS Godot can emit the Xcode project:
set `application/app_store_team_id` locally (do **not** commit your Team ID), enable
`application/export_project_only=true`, then
`$G --headless --path . --export-release "iOS" build/ios/KeystoneIsle.ipa`
which writes `KeystoneIsle.xcodeproj` + pck + frameworks into `build/ios/`. Open in Xcode, pick the team,
archive, and upload.

## Verified status (2026-10-30, Linux box)
| Target | Result |
|---|---|
| Windows | exe exported (~112 MB), not run on Windows |
| Android | debug APK exported, signed with debug key, `apksigner verify` OK; not installed on a device |
| macOS | zip with `Keystone Isle.app` exported; unsigned, not launched on a Mac |
| iOS | Xcode project generated using a placeholder Team ID; not built in Xcode |
