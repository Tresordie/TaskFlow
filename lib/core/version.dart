/// The application version shown in Settings → About.
///
/// Kept in lockstep with the `version:` field of `pubspec.yaml` — the
/// release pipeline bumps both together (v1.4.27). Deliberately NOT read
/// via package_info_plus: on Windows that pulls the exe's VERSIONINFO
/// asynchronously and would add a dependency just to render one string,
/// while a compile-time constant is synchronous, testable and can never
/// drift from what was actually shipped.
///
/// Displaying the real version matters for support: before v1.4.27 the
/// About card was hard-coded to "v1.0.0", making it impossible to tell
/// whether a reported bug was observed on the latest build.
const String kAppVersion = '1.4.99';
