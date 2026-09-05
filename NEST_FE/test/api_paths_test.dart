import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against a path built by string interpolation losing its variable.
///
/// This is not hypothetical. Four calls in the fees API shipped as `/students//fee-profile` -
/// the `$membershipId` had been dropped, leaving an empty segment - so opening a student's fee
/// detail, their statement, the statement download and their Other fees all failed. The bug is
/// invisible in review (`//` reads as a typo, not a missing value), the analyzer has nothing to
/// object to, and it only surfaces when a human taps the row.
///
/// An empty path segment is never intentional in this codebase, so the whole `lib/` tree is
/// scanned rather than one file.
void main() {
  test('no API path contains an empty segment from a dropped interpolation', () {
    // A quoted path starting with "/" that then contains "//". Deliberately not matching "://",
    // which is a URL scheme and perfectly legitimate.
    final emptySegment = RegExp(r'''['"]/[^'"\s]*(?<!:)//''');

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // Skip comments - a doc comment may legitimately quote a URL.
        final trimmed = lines[i].trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        if (emptySegment.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These paths have an empty segment, which usually means a "\$id" was lost:\n'
          '${offenders.join('\n')}',
    );
  });
}
