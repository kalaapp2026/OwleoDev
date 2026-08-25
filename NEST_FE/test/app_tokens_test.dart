import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_theme.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';

/// Resolves `context.palette` under a given ThemeData, using Theme directly rather than
/// MaterialApp - MaterialApp picks between theme/darkTheme via ThemeMode and platform
/// brightness, which would make this assert something other than what it claims to.
Future<AppPalette> _resolve(WidgetTester tester, ThemeData theme) async {
  late AppPalette captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Theme(
        data: theme,
        child: Builder(builder: (context) {
          captured = context.palette;
          return const SizedBox.shrink();
        }),
      ),
    ),
  );
  return captured;
}

void main() {
  // The palette is only useful if it resolves through the theme. An unregistered ThemeExtension
  // fails silently at the call site - the `?? AppPalette.dark` fallback swallows it - so light
  // mode would quietly render dark colours. This checks the wiring, not the values.
  testWidgets('dark theme exposes the dark palette', (tester) async {
    expect((await _resolve(tester, AppTheme.dark)).bg, AppPalette.dark.bg);
  });

  testWidgets('light theme exposes the light palette', (tester) async {
    expect((await _resolve(tester, AppTheme.light)).bg, AppPalette.light.bg);
  });

  test('status colours are mutually distinct', () {
    // These encode meaning in a dense list; two statuses sharing a colour would make e.g.
    // "partial" and "overdue" indistinguishable at a glance.
    for (final p in [AppPalette.dark, AppPalette.light]) {
      expect({p.notPaid, p.paidManual, p.gateway, p.partial, p.due}.length, 5);
    }
  });

  test('lerp produces a valid palette rather than throwing', () {
    // Theme transitions interpolate extensions; a missing field in lerp() would surface as a
    // crash mid-animation on the very first light/dark switch.
    final mid = AppPalette.dark.lerp(AppPalette.light, 0.5);
    expect(mid.bg, isNot(AppPalette.dark.bg));
    expect(mid.bg, isNot(AppPalette.light.bg));
  });
}
