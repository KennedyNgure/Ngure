// ============================================================
// PLATFORM DOWNLOAD — conditional-import shim
// ------------------------------------------------------------
// Conditions are checked IN ORDER and the first true one wins,
// so WEB must come before IO.
//
//   - Flutter WEB (JS or Wasm) : browser download
//   - io (Android/iOS/desktop) : temp file + OS share sheet
//   - anything else            : stub that throws
//
// Keep this file in the SAME folder as download_helper.dart.
// ============================================================

export 'platform_download_stub.dart'
if (dart.library.js_interop) 'platform_download_web.dart'
if (dart.library.io) 'platform_download_io.dart';