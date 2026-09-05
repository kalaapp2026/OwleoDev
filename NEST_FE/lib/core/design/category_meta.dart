import 'package:flutter/widgets.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';

/// The seven disciplines a course can belong to.
///
/// The wire values are the backend's `CourseCategory` enum names. [unknown] is not a real
/// category and is never offered in a picker - it exists so a category added to the backend
/// later deserialises into something renderable instead of throwing in the middle of a list.
enum CourseCategory {
  dance('DANCE', 'Dance'),
  music('MUSIC', 'Music'),
  fineArts('FINE_ARTS', 'Fine Arts'),
  literature('LITERATURE', 'Literature'),
  theatre('THEATRE', 'Theatre'),
  fashion('FASHION', 'Fashion'),
  others('OTHERS', 'Others'),
  unknown('', 'Others');

  const CourseCategory(this.wire, this.label);

  final String wire;
  final String label;

  static CourseCategory fromWire(String? value) {
    for (final c in values) {
      if (c.wire == value) return c;
    }
    return CourseCategory.unknown;
  }

  /// The categories actually offered when creating a course - [unknown] is deliberately absent.
  static const List<CourseCategory> selectable = [
    dance,
    music,
    fineArts,
    literature,
    theatre,
    fashion,
    others,
  ];

  /// The three shown as their own filter chips, with the rest folded into a "More" dropdown.
  /// Order and membership match the prototype's PRIMARY_CATEGORIES.
  static const List<CourseCategory> primary = [dance, music, theatre];

  static List<CourseCategory> get more =>
      selectable.where((c) => !primary.contains(c)).toList(growable: false);
}

/// A category's accent, its soft fill, and the dimmed variant used for pressed/secondary states.
@immutable
class CategoryMeta {
  const CategoryMeta({required this.color, required this.soft, required this.dim});

  final Color color;
  final Color soft;
  final Color dim;
}

/// Resolves a category to its colours against the live palette.
///
/// Four of the seven categories reuse an accent the palette already had (Dance takes gold, Music
/// takes primary, Fashion takes gateway, Others takes the muted neutral) rather than inventing
/// new hues - the prototype does the same, which is why the palette only needed violet, coral and
/// magenta adding.
extension CategoryMetaLookup on CourseCategory {
  CategoryMeta meta(AppPalette p) {
    switch (this) {
      case CourseCategory.dance:
        return CategoryMeta(color: p.gold, soft: p.goldSoft, dim: p.goldDim);
      case CourseCategory.music:
        return CategoryMeta(color: p.primary, soft: p.primarySoft, dim: p.primaryDim);
      case CourseCategory.fineArts:
        return CategoryMeta(color: p.violet, soft: p.violetSoft, dim: p.violet);
      case CourseCategory.literature:
        return CategoryMeta(color: p.coral, soft: p.coralSoft, dim: p.coral);
      case CourseCategory.theatre:
        return CategoryMeta(color: p.magenta, soft: p.magentaSoft, dim: p.magenta);
      case CourseCategory.fashion:
        return CategoryMeta(color: p.gateway, soft: p.gatewaySoft, dim: p.gateway);
      case CourseCategory.others:
      case CourseCategory.unknown:
        return CategoryMeta(color: p.textMuted, soft: p.surfaceHigh, dim: p.textMuted);
    }
  }
}

/// `context.categoryMeta(course.category)` at call sites that already have a context.
extension CategoryMetaContext on BuildContext {
  CategoryMeta categoryMeta(CourseCategory category) => category.meta(palette);
}
