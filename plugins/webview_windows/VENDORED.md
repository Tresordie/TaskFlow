# Vendored: webview_windows 0.4.0

This plugin is vendored from pub.dev `webview_windows 0.4.0` (jnschulze,
WebView2-based webview for Windows — the mermaid/SVG renderer dependency of
the AI Parse page).

**Why vendored:** upstream uses `std::format` / `<format>` (C++20 library
feature) in 4 places. `<format>` requires MSVC ≥ 14.32 (VS2022 17.2+); this
repo's build environment ships toolset 14.30 (VS2022 17.0), where the
compilation fails with `error C2039: "format": 不是 "std" 的成员`. The 4 call
sites were rewritten as plain string concatenation — behavior identical.

Patches applied (search "Vendored patch"):
- `windows/webview_bridge.cc` — method-channel names via `std::to_string`.
- `windows/webview.cc` — `SetCacheDisabled` JSON via manual concatenation.
- `windows/webview_windows_plugin.cc` — creation-error message with
  `snprintf` hex HRESULT.

When upstream publishes a release compatible with older toolsets (or this
repo upgrades to MSVC ≥ 14.32), drop this directory and return to the
hosted dependency `webview_windows: ^0.4.0`.

Upstream: https://github.com/jnschulze/flutter-webview-windows
License: see LICENSE.
