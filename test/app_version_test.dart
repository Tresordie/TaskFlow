import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/version.dart';

/// The release convention is "bump both places together", and v1.12.45 proved
/// that a convention living only in a doc is not a convention: `pubspec.yaml`
/// got reverted by a cleanup pass while `version.dart` moved on, so the repo
/// shipped a release whose Windows file metadata said 1.12.44.
///
/// `flutter test` runs with the package root as the working directory, so this
/// can read the real manifest.
void main() {
  test('pubspec.yaml version matches kAppVersion', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(
      match!.group(1),
      kAppVersion,
      reason: 'bump pubspec.yaml and lib/core/version.dart in the same commit',
    );
  });
}
