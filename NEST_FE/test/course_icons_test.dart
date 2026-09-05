import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/course_icons.dart';

void main() {
  group('icon set integrity', () {
    test('every icon key is unique across the whole set', () {
      final keys = <String>[];
      for (final list in courseIconsByCategory.values) {
        keys.addAll(list.map((s) => s.key));
      }
      // Keys are persisted on course rows. A duplicate would mean two categories' art fighting
      // over one stored value, and whichever lost would render the wrong glyph.
      expect(keys.toSet().length, keys.length,
          reason: 'duplicate icon keys: ${keys.where((k) => keys.where((o) => o == k).length > 1).toSet()}');
    });

    test('every selectable category has art, led by its general icon', () {
      for (final category in CourseCategory.selectable) {
        final icons = iconsForCategory(category);
        expect(icons, isNotEmpty, reason: '${category.label} has no icons');
        // The picker's first cell is the "whole category" fallback, and is what a course gets
        // before anyone chooses something specific - so it has to actually be first.
        expect(icons.first.key, endsWith('_general'),
            reason: '${category.label} does not lead with a general icon');
      }
    });

    test('every icon body is non-empty and carries no unsubstituted colour token', () {
      for (final list in courseIconsByCategory.values) {
        for (final spec in list) {
          expect(spec.body.trim(), isNotEmpty, reason: '${spec.key} has an empty body');
          expect(spec.label.trim(), isNotEmpty, reason: '${spec.key} has no label');
        }
      }
    });
  });

  group('icon resolution', () {
    test('a known key resolves to its own art', () {
      expect(resolveCourseIcon(iconKey: 'guitar', category: CourseCategory.music).key, 'guitar');
    });

    test('an unknown or absent key falls back to the category general icon', () {
      // Art can be retired between releases; a course still pointing at it must render something
      // sensible rather than leaving a hole in the list.
      expect(resolveCourseIcon(iconKey: 'retired_glyph', category: CourseCategory.dance).key,
          'dance_general');
      expect(resolveCourseIcon(iconKey: null, category: CourseCategory.theatre).key,
          'theatre_general');
    });

    test('a key from another category still resolves - the store, not the picker, is the truth', () {
      // Changing a course's category does not rewrite its icon, so this combination is reachable
      // and must not fall back and silently discard the admin's choice.
      expect(resolveCourseIcon(iconKey: 'guitar', category: CourseCategory.fashion).key, 'guitar');
    });
  });

  group('category wire format', () {
    test('round-trips every selectable category', () {
      for (final category in CourseCategory.selectable) {
        expect(CourseCategory.fromWire(category.wire), category);
      }
    });

    test('an unrecognised category degrades to unknown rather than throwing', () {
      expect(CourseCategory.fromWire('ASTROPHYSICS'), CourseCategory.unknown);
      expect(CourseCategory.fromWire(null), CourseCategory.unknown);
    });

    test('unknown is never offered as a choice', () {
      expect(CourseCategory.selectable, isNot(contains(CourseCategory.unknown)));
    });

    test('primary and more together cover every selectable category exactly once', () {
      final combined = [...CourseCategory.primary, ...CourseCategory.more];
      expect(combined.toSet(), CourseCategory.selectable.toSet());
      expect(combined.length, CourseCategory.selectable.length);
    });
  });

  group('rendering', () {
    testWidgets('every icon in the set builds without throwing', (tester) async {
      for (final list in courseIconsByCategory.values) {
        for (final spec in list) {
          await tester.pumpWidget(MaterialApp(
            home: Center(child: CourseIcon(spec: spec, color: const Color(0xFF2FE0C6))),
          ));
          expect(find.byType(CourseIcon), findsOneWidget, reason: '${spec.key} failed to build');
        }
      }
    });

    testWidgets('a translucent colour still renders', (tester) async {
      // The SVG stroke attribute is RGB-only, so alpha travels as a colour filter instead - this
      // is the path that silently painted fully opaque before that was handled.
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: CourseIcon.forCourse(
            iconKey: 'tabla',
            category: CourseCategory.music,
            color: const Color(0x802FE0C6),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('category colours', () {
    test('each category resolves to a distinct accent, except the two neutral ones', () {
      const palette = AppPalette.dark;
      final accents = <CourseCategory, Color>{
        for (final c in CourseCategory.selectable) c: c.meta(palette).color,
      };
      // Others is the deliberate neutral; every other category must be visually separable,
      // since the colour is the only thing distinguishing them in a dense list.
      final coloured = Map.of(accents)..remove(CourseCategory.others);
      expect(coloured.values.toSet().length, coloured.length,
          reason: 'two categories share an accent: $coloured');
    });

    test('unknown borrows the neutral treatment rather than a real category accent', () {
      const palette = AppPalette.dark;
      expect(CourseCategory.unknown.meta(palette).color,
          CourseCategory.others.meta(palette).color);
    });
  });
}
