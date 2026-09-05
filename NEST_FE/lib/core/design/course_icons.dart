/// The academy's own icon set - hand-drawn to sit alongside Material's stroke weight, because no
/// off-the-shelf library covers Indian classical instruments and dance forms next to their
/// Western counterparts.
///
/// Each entry is an SVG body on a 24x24 canvas. The wrapper below supplies the shared
/// presentation (`fill="none"`, round caps/joins, 1.7 stroke); a child that wants to be a solid
/// dot rather than an outline overrides it locally with `fill="%C%" stroke="none"`, where `%C%`
/// is substituted for the resolved colour at paint time.
///
/// Keys are persisted on the course row, so renaming one silently blanks every course already
/// using it. Add new keys; don't repurpose old ones.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nest_fe/core/design/category_meta.dart';

const String _colorToken = '%C%';

/// One selectable icon: the key stored on the course, a human label for the picker, and the art.
@immutable
class CourseIconSpec {
  const CourseIconSpec(this.key, this.label, this.body);

  final String key;
  final String label;
  final String body;
}

// ---------------------------------------------------------------------------
// Music - Indian classical
// ---------------------------------------------------------------------------

const _musicGeneral = CourseIconSpec('music_general', 'Music', '''
<path d="M9 18 V5 L20 3 V16" />
<circle cx="7" cy="18" r="2.4" />
<circle cx="18" cy="16" r="2.4" />''');

const _sitar = CourseIconSpec('sitar', 'Sitar', '''
<ellipse cx="7" cy="18" rx="4.2" ry="3" />
<line x1="9.5" y1="15.3" x2="16.5" y2="4" />
<rect x="15" y="2" width="3" height="2.4" rx="0.5" />
<line x1="6.3" y1="14.5" x2="10" y2="6.3" />
<line x1="8" y1="16.3" x2="11.6" y2="8.3" />''');

const _tabla = CourseIconSpec('tabla', 'Tabla', '''
<ellipse cx="7" cy="8" rx="4" ry="2" />
<path d="M3 8 L3.6 16 Q3.8 18 7 18 Q10.2 18 10.4 16 L11 8" />
<circle cx="7" cy="8" r="1.1" fill="$_colorToken" stroke="none" />
<ellipse cx="17" cy="6.5" rx="4.6" ry="2.2" />
<path d="M12.4 6.5 L13 17 Q13.2 19 17 19 Q20.8 19 21 17 L21.6 6.5" />
<circle cx="17" cy="6.5" r="1.3" fill="$_colorToken" stroke="none" />''');

const _veena = CourseIconSpec('veena', 'Veena', '''
<ellipse cx="4" cy="17" rx="3" ry="2.4" />
<ellipse cx="20" cy="7" rx="2.4" ry="1.9" />
<line x1="6.4" y1="16" x2="18" y2="8" />
<line x1="9" y1="14.2" x2="10.3" y2="13.4" />
<line x1="11.6" y1="12.6" x2="12.9" y2="11.8" />
<line x1="14.2" y1="11" x2="15.5" y2="10.2" />''');

const _harmonium = CourseIconSpec('harmonium', 'Harmonium', '''
<rect x="3" y="10" width="14" height="8" rx="1.2" />
<line x1="5" y1="10" x2="5" y2="13.2" />
<line x1="7.3" y1="10" x2="7.3" y2="13.2" />
<line x1="9.6" y1="10" x2="9.6" y2="13.2" />
<line x1="11.9" y1="10" x2="11.9" y2="13.2" />
<line x1="14.2" y1="10" x2="14.2" y2="13.2" />
<path d="M17 11 L21 9 L21 19 L17 17" />
<line x1="18" y1="12" x2="20" y2="11" />
<line x1="18" y1="15" x2="20" y2="14" />''');

const _bansuri = CourseIconSpec('bansuri', 'Bansuri', '''
<rect x="3" y="10.5" width="17" height="3" rx="1.5" />
<circle cx="7" cy="12" r="0.5" fill="$_colorToken" stroke="none" />
<circle cx="10" cy="12" r="0.5" fill="$_colorToken" stroke="none" />
<circle cx="13" cy="12" r="0.5" fill="$_colorToken" stroke="none" />
<circle cx="16" cy="12" r="0.5" fill="$_colorToken" stroke="none" />
<circle cx="20.2" cy="12" r="1" fill="$_colorToken" stroke="none" />''');

const _tanpura = CourseIconSpec('tanpura', 'Tanpura', '''
<ellipse cx="7" cy="19" rx="4.4" ry="2.8" />
<line x1="9.6" y1="16.6" x2="15" y2="3.5" />
<rect x="13.6" y="2" width="2.8" height="2.2" rx="0.5" />
<line x1="6.5" y1="16" x2="9.7" y2="7" />
<line x1="8" y1="17.5" x2="11.2" y2="8.5" />''');

// ---------------------------------------------------------------------------
// Music - Western
// ---------------------------------------------------------------------------

const _guitar = CourseIconSpec('guitar', 'Guitar', '''
<circle cx="9" cy="16" r="4.2" />
<circle cx="9" cy="9.6" r="2.6" />
<circle cx="9" cy="16" r="1.3" />
<line x1="9" y1="4.5" x2="9" y2="9.6" />
<line x1="7" y1="3" x2="11" y2="3" />
<circle cx="7" cy="3" r="0.5" fill="$_colorToken" stroke="none" />
<circle cx="9" cy="3" r="0.5" fill="$_colorToken" stroke="none" />
<circle cx="11" cy="3" r="0.5" fill="$_colorToken" stroke="none" />''');

const _pianoKeys = CourseIconSpec('piano_keys', 'Piano', '''
<rect x="2.5" y="6" width="19" height="12" rx="1.4" />
<line x1="7" y1="6" x2="7" y2="18" />
<line x1="11.3" y1="6" x2="11.3" y2="18" />
<line x1="15.6" y1="6" x2="15.6" y2="18" />
<rect x="5.5" y="6" width="2.2" height="7" fill="$_colorToken" stroke="none" />
<rect x="10" y="6" width="2.2" height="7" fill="$_colorToken" stroke="none" />
<rect x="14.3" y="6" width="2.2" height="7" fill="$_colorToken" stroke="none" />
<rect x="18.6" y="6" width="2.2" height="7" fill="$_colorToken" stroke="none" />''');

// The bow is drawn at 70% stroke so it reads as a separate, thinner object crossing the body.
const _violin = CourseIconSpec('violin', 'Violin', '''
<circle cx="9" cy="15.5" r="3.4" />
<circle cx="9" cy="9.8" r="2.3" />
<path d="M8 3 q1 -1.4 2 0" />
<path d="M7.3 13.5 q-0.8 1.2 0 2.4" />
<path d="M10.7 13.5 q0.8 1.2 0 2.4" />
<line x1="9" y1="6.1" x2="9" y2="9.8" />
<line x1="2.5" y1="20" x2="17" y2="5" stroke-width="1.19" />''');

const _drumKit = CourseIconSpec('drum_kit', 'Drums', '''
<ellipse cx="12" cy="9" rx="7" ry="3" />
<path d="M5 9 L6 17 Q6 19.5 12 19.5 Q18 19.5 18 17 L19 9" />
<line x1="7" y1="4" x2="10.5" y2="8.5" stroke-width="1.445" />
<line x1="17" y1="4" x2="13.5" y2="8.5" stroke-width="1.445" />''');

const _mic = CourseIconSpec('mic', 'Vocals', '''
<rect x="9" y="2.5" width="6" height="10" rx="3" />
<path d="M6 11 a6 6 0 0 0 12 0" />
<line x1="12" y1="17" x2="12" y2="21" />
<line x1="8.5" y1="21" x2="15.5" y2="21" />''');

const _speaker = CourseIconSpec('speaker', 'Audio', '''
<rect x="6" y="2.5" width="12" height="19" rx="2" />
<circle cx="12" cy="8" r="2.3" />
<circle cx="12" cy="16" r="3.4" />
<circle cx="12" cy="16" r="1.1" fill="$_colorToken" stroke="none" />''');

// ---------------------------------------------------------------------------
// Dance - Indian classical
// ---------------------------------------------------------------------------

const _danceGeneral = CourseIconSpec('dance_general', 'Dance', '''
<circle cx="12" cy="4" r="1.8" />
<line x1="12" y1="5.8" x2="12" y2="14" />
<line x1="12" y1="8" x2="6" y2="4" />
<line x1="12" y1="8" x2="18" y2="4" />
<line x1="12" y1="14" x2="7" y2="21" />
<line x1="12" y1="14" x2="17" y2="21" />''');

const _bharatanatyam = CourseIconSpec('bharatanatyam', 'Bharatanatyam', '''
<circle cx="12" cy="4" r="1.8" />
<line x1="12" y1="5.8" x2="12" y2="12" />
<line x1="12" y1="7.5" x2="6" y2="5" />
<line x1="12" y1="7.5" x2="18" y2="5" />
<circle cx="6" cy="5" r="0.6" fill="$_colorToken" stroke="none" />
<circle cx="18" cy="5" r="0.6" fill="$_colorToken" stroke="none" />
<line x1="12" y1="12" x2="7" y2="17" />
<line x1="12" y1="12" x2="17" y2="17" />
<line x1="7" y1="17" x2="7" y2="21" />
<line x1="17" y1="17" x2="17" y2="21" />''');

const _kathak = CourseIconSpec('kathak', 'Kathak', '''
<circle cx="12" cy="4" r="1.8" />
<line x1="12" y1="5.8" x2="12" y2="11" />
<line x1="12" y1="7" x2="4" y2="9" />
<line x1="12" y1="7" x2="20" y2="5" />
<path d="M6 20 Q12 12 18 20 Q12 17 6 20 Z" />
<circle cx="6.5" cy="19.6" r="0.5" fill="$_colorToken" stroke="none" />
<circle cx="17.5" cy="19.6" r="0.5" fill="$_colorToken" stroke="none" />''');

const _odissi = CourseIconSpec('odissi', 'Odissi', '''
<circle cx="13" cy="4" r="1.8" />
<path d="M13 5.8 Q10 9 13 12 Q16 15 12 18" />
<line x1="13" y1="7" x2="8" y2="4.5" />
<line x1="13" y1="9" x2="18.5" y2="10" />
<line x1="12" y1="18" x2="9" y2="21" />
<line x1="12" y1="18" x2="15" y2="21" />''');

const _ghungroo = CourseIconSpec('ghungroo', 'Ghungroo', '''
<path d="M3 12 Q12 6 21 12" />
<circle cx="5" cy="12.8" r="1.3" />
<circle cx="8.6" cy="10.5" r="1.3" />
<circle cx="12.3" cy="9.7" r="1.3" />
<circle cx="16" cy="10.5" r="1.3" />
<circle cx="19.5" cy="12.8" r="1.3" />''');

// ---------------------------------------------------------------------------
// Dance - Western
// ---------------------------------------------------------------------------

const _ballet = CourseIconSpec('ballet', 'Ballet', '''
<path d="M4 19 Q4 21 7 21 L14 21 Q17 21 17 18 Q17 14 12 13 L6 11 Q4 12 4 15 Z" />
<line x1="8" y1="13" x2="15" y2="7" />
<line x1="9.3" y1="15.5" x2="16.3" y2="9.5" />''');

const _contemporary = CourseIconSpec('contemporary', 'Contemporary', '''
<circle cx="12" cy="4" r="1.8" />
<path d="M12 5.8 Q8 9 12 12 Q16 15 10 18" />
<path d="M12 7 Q6 5 4 9" />
<path d="M12 8 Q18 10 19 15" />
<line x1="10" y1="18" x2="7" y2="21" />
<line x1="10" y1="18" x2="13" y2="21" />''');

const _hiphop = CourseIconSpec('hiphop', 'Hip-Hop', '''
<circle cx="9" cy="5" r="1.8" />
<path d="M7.4 4.6 a2.2 1.5 0 0 1 3.6 -0.6" />
<line x1="9" y1="6.8" x2="14" y2="14" />
<line x1="14" y1="14" x2="16" y2="19" />
<line x1="9" y1="8" x2="4" y2="6" />
<line x1="12" y1="10" x2="18" y2="8" />
<line x1="12" y1="10" x2="8" y2="16" />''');

const _ballroom = CourseIconSpec('ballroom', 'Ballroom', '''
<circle cx="7" cy="5" r="1.6" />
<line x1="7" y1="6.6" x2="7" y2="14" />
<line x1="7" y1="8" x2="12" y2="9" />
<line x1="7" y1="14" x2="5" y2="20" />
<line x1="7" y1="14" x2="9" y2="20" />
<circle cx="17" cy="5" r="1.6" />
<line x1="17" y1="6.6" x2="17" y2="14" />
<line x1="17" y1="8" x2="12" y2="9" />
<line x1="17" y1="14" x2="15" y2="20" />
<line x1="17" y1="14" x2="19" y2="20" />''');

// ---------------------------------------------------------------------------
// Fine Arts
// ---------------------------------------------------------------------------

const _fineArtsGeneral = CourseIconSpec('finearts_general', 'Fine Arts', '''
<rect x="3" y="3" width="18" height="18" rx="1.4" />
<path d="M3 16 L8 10 L12 14 L16 9 L21 15" />
<circle cx="8" cy="7" r="1.3" />''');

const _palette = CourseIconSpec('palette', 'Palette', '''
<path d="M12 3 C7 3 3 6.6 3 11.2 C3 15 5.8 17 8.4 17 C9.8 17 10 15.8 9.3 15 C8.6 14.2 9.1 12.9 10.4 12.9 H14 C17.3 12.9 20 10.5 20 7.7 C20 5 16.6 3 12 3 Z" />
<circle cx="7.6" cy="9.4" r="0.9" fill="$_colorToken" stroke="none" />
<circle cx="7.6" cy="13" r="0.9" fill="$_colorToken" stroke="none" />
<circle cx="11.4" cy="7.2" r="0.9" fill="$_colorToken" stroke="none" />
<circle cx="15.4" cy="8.4" r="0.9" fill="$_colorToken" stroke="none" />''');

const _paintbrush = CourseIconSpec('paintbrush', 'Brush', '''
<path d="M17 3 L21 7 L11 17 L7 17 L7 13 Z" />
<path d="M7 17 Q5 19 4 21" />''');

const _easel = CourseIconSpec('easel', 'Easel', '''
<line x1="12" y1="2" x2="19" y2="20" />
<line x1="12" y1="2" x2="5" y2="20" />
<line x1="7" y1="14" x2="17" y2="14" />
<rect x="8" y="8" width="8" height="6" rx="0.6" />
<line x1="9" y1="20" x2="15" y2="20" />''');

const _camera = CourseIconSpec('camera', 'Camera', '''
<rect x="3" y="7" width="18" height="13" rx="2" />
<path d="M8 7 L9.5 4.5 h5 L16 7" />
<circle cx="12" cy="13.5" r="3.6" />''');

// ---------------------------------------------------------------------------
// Literature
// ---------------------------------------------------------------------------

const _literatureGeneral = CourseIconSpec('literature_general', 'Literature', '''
<path d="M5 3 H17 a2 2 0 0 1 2 2 V21 L12 18.5 L5 21 Z" />
<line x1="5" y1="3" x2="5" y2="21" />''');

const _bookopen = CourseIconSpec('bookopen', 'Reading', '''
<path d="M12 6 C10 4.5 6.5 4 3.5 4.5 V19 C6.5 18.5 10 19 12 20.5 C14 19 17.5 18.5 20.5 19 V4.5 C17.5 4 14 4.5 12 6 Z" />
<line x1="12" y1="6" x2="12" y2="20.5" />''');

const _quill = CourseIconSpec('quill', 'Quill', '''
<path d="M20 3 C13 3 4 9 4 18 L7 21 C11 15 16 9 20 3 Z" />
<line x1="4" y1="18" x2="2" y2="22" />''');

const _scroll = CourseIconSpec('scroll', 'Scroll', '''
<path d="M5 3 a2 2 0 0 0 -2 2 a2 2 0 0 0 2 2 h14" />
<path d="M19 21 a2 2 0 0 0 2 -2 a2 2 0 0 0 -2 -2 H5" />
<line x1="5" y1="5" x2="5" y2="21" />
<line x1="19" y1="3" x2="19" y2="19" />
<line x1="8" y1="9" x2="16" y2="9" />
<line x1="8" y1="13" x2="14" y2="13" />''');

const _bookmark = CourseIconSpec('bookmark', 'Bookmark', '''
<path d="M6 3 h12 v18 l-6 -4.5 L6 21 Z" />''');

// ---------------------------------------------------------------------------
// Theatre
// ---------------------------------------------------------------------------

const _theatreGeneral = CourseIconSpec('theatre_general', 'Theatre', '''
<path d="M4 21 V9 a8 8 0 0 1 16 0 V21" />
<line x1="4" y1="21" x2="20" y2="21" />
<line x1="4" y1="21" x2="4" y2="17" />
<line x1="20" y1="21" x2="20" y2="17" />''');

const _masks = CourseIconSpec('masks', 'Masks', '''
<circle cx="8.5" cy="10" r="6" />
<circle cx="15.5" cy="14" r="6" />
<circle cx="6.3" cy="9.3" r="0.5" fill="$_colorToken" stroke="none" />
<circle cx="10.7" cy="9.3" r="0.5" fill="$_colorToken" stroke="none" />
<path d="M6.3 12.3 q2.2 1.8 4.4 0" />
<circle cx="13.3" cy="13" r="0.5" fill="$_colorToken" stroke="none" />
<circle cx="17.7" cy="13" r="0.5" fill="$_colorToken" stroke="none" />
<path d="M13.3 16.7 q2.2 -1.8 4.4 0" />''');

const _curtain = CourseIconSpec('curtain', 'Curtain', '''
<line x1="4" y1="3" x2="4" y2="21" />
<line x1="20" y1="3" x2="20" y2="21" />
<path d="M4 3 q4.5 6 0 9 q4.5 6 0 9" />
<path d="M20 3 q-4.5 6 0 9 q-4.5 6 0 9" />
<line x1="4" y1="3" x2="20" y2="3" />''');

const _spotlight = CourseIconSpec('spotlight', 'Spotlight', '''
<path d="M9 3 L15 3 L19 12 L5 12 Z" />
<ellipse cx="12" cy="19" rx="7" ry="2.5" />
<line x1="12" y1="12" x2="12" y2="16" />''');

// ---------------------------------------------------------------------------
// Fashion
// ---------------------------------------------------------------------------

const _fashionGeneral = CourseIconSpec('fashion_general', 'Fashion', '''
<path d="M12 3 a2 2 0 1 1 -2 2" />
<line x1="12" y1="5" x2="12" y2="8" />
<path d="M12 8 L3 15 a1.5 1.5 0 0 0 1 2.6 H20 a1.5 1.5 0 0 0 1 -2.6 Z" />''');

const _shirt = CourseIconSpec('shirt', 'Apparel', '''
<path d="M8 3 L4 6 L6 9 L8 7.5 V20 H16 V7.5 L18 9 L20 6 L16 3 Q14 5 12 5 Q10 5 8 3 Z" />''');

const _scissors = CourseIconSpec('scissors', 'Tailoring', '''
<circle cx="6" cy="6" r="2" />
<circle cx="6" cy="18" r="2" />
<line x1="20" y1="4" x2="7.5" y2="16.5" />
<line x1="20" y1="20" x2="7.5" y2="7.5" />''');

const _needle = CourseIconSpec('needle', 'Stitching', '''
<line x1="4" y1="20" x2="18" y2="6" />
<circle cx="19.5" cy="4.5" r="1.6" />
<path d="M4 20 q-2 -4 2 -6 q4 -2 2 -6" />''');

const _heel = CourseIconSpec('heel', 'Footwear', '''
<path d="M4 18 h9 q3 0 3 -3 v-1 q0 -3 3 -3 l1 5 q0 3 -3 4 H4 Z" />
<line x1="18" y1="15" x2="19" y2="19" />''');

// ---------------------------------------------------------------------------
// Others / general
// ---------------------------------------------------------------------------

const _othersGeneral = CourseIconSpec('others_general', 'General', '''
<path d="M11 3 H4 V10 L14 20 L21 13 Z" />
<circle cx="7.5" cy="7.5" r="1.3" />''');

const _star = CourseIconSpec('star', 'Star', '''
<path d="M12 2 L14.6 8.6 L21.8 9.2 L16.3 13.8 L18 21 L12 17 L6 21 L7.7 13.8 L2.2 9.2 L9.4 8.6 Z" />''');

const _sparkle = CourseIconSpec('sparkle', 'Sparkle', '''
<path d="M12 3 L13.2 10.8 L21 12 L13.2 13.2 L12 21 L10.8 13.2 L3 12 L10.8 10.8 Z" />
<circle cx="19" cy="5" r="1" fill="$_colorToken" stroke="none" />''');

const _group = CourseIconSpec('group', 'Group', '''
<circle cx="9" cy="8" r="3" />
<path d="M3 20 q0 -6 6 -6 q6 0 6 6" />
<circle cx="17" cy="9" r="2.4" />
<path d="M15.2 20 q0 -4.6 4 -5.5" />''');

const _ribbon = CourseIconSpec('ribbon', 'Ribbon', '''
<circle cx="12" cy="8" r="5" />
<path d="M9 12.5 L7 21 L12 18 L17 21 L15 12.5" />''');

// ---------------------------------------------------------------------------
// Grouping
// ---------------------------------------------------------------------------

/// Indian classical and Western options sit together in one list per category, with no
/// origin-based grouping - the split exists in the source only as an authoring convenience.
/// Each list leads with the icon that stands for the category as a whole, so a course that
/// doesn't map to a specific instrument or form still has an honest default.
const Map<CourseCategory, List<CourseIconSpec>> courseIconsByCategory = {
  CourseCategory.music: [
    _musicGeneral,
    _sitar, _tabla, _veena, _harmonium, _bansuri, _tanpura,
    _guitar, _pianoKeys, _violin, _drumKit, _mic, _speaker,
  ],
  CourseCategory.dance: [
    _danceGeneral,
    _bharatanatyam, _kathak, _odissi, _ghungroo,
    _ballet, _contemporary, _hiphop, _ballroom,
  ],
  CourseCategory.fineArts: [_fineArtsGeneral, _palette, _paintbrush, _easel, _camera],
  CourseCategory.literature: [_literatureGeneral, _bookopen, _quill, _scroll, _bookmark],
  CourseCategory.theatre: [_theatreGeneral, _masks, _curtain, _spotlight],
  CourseCategory.fashion: [_fashionGeneral, _shirt, _scissors, _needle, _heel],
  CourseCategory.others: [_othersGeneral, _star, _sparkle, _group, _ribbon],
};

/// The icons offered when a course is in [category]. Falls back to the Others set so a category
/// the backend knows about but this build doesn't still yields a usable picker.
List<CourseIconSpec> iconsForCategory(CourseCategory category) =>
    courseIconsByCategory[category] ?? courseIconsByCategory[CourseCategory.others]!;

final Map<String, CourseIconSpec> _byKey = {
  for (final list in courseIconsByCategory.values)
    for (final spec in list) spec.key: spec,
};

/// Looks up art by its stored key. Returns null for an unrecognised key so callers can decide
/// between a category default and a neutral placeholder rather than getting a silent wrong glyph.
CourseIconSpec? courseIconSpec(String? key) => key == null ? null : _byKey[key];

/// The art a course should render with: its own icon if the key still resolves, otherwise the
/// leading "whole category" icon. Never returns null, so list rows can't end up with a hole.
CourseIconSpec resolveCourseIcon({String? iconKey, required CourseCategory category}) =>
    courseIconSpec(iconKey) ?? iconsForCategory(category).first;

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// `#rrggbb` for the SVG's stroke/fill attributes, which take no alpha - any translucency is
/// reapplied as a colour filter over the rendered picture instead.
String _rgbHex(Color c) {
  int channel(double v) => (v * 255).round().clamp(0, 255);
  final rgb = (channel(c.r) << 16) | (channel(c.g) << 8) | channel(c.b);
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

/// Paints a [CourseIconSpec] at [size], stroked in [color].
///
/// Stroke width is held at the set's native 1.7 rather than scaled with [size]: these are drawn
/// on a 24x24 canvas and scaling the stroke with the box makes the small (14-16px) instances used
/// in list rows turn muddy.
class CourseIcon extends StatelessWidget {
  const CourseIcon({
    super.key,
    required this.spec,
    required this.color,
    this.size = 17,
  });

  /// Convenience for the common "I have a course row" case.
  CourseIcon.forCourse({
    super.key,
    String? iconKey,
    required CourseCategory category,
    required this.color,
    this.size = 17,
  }) : spec = resolveCourseIcon(iconKey: iconKey, category: category);

  final CourseIconSpec spec;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hex = _rgbHex(color);
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" '
        'viewBox="0 0 24 24" fill="none" stroke="$hex" stroke-width="1.7" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '${spec.body.replaceAll(_colorToken, hex)}'
        '</svg>';

    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      // The alpha channel is carried separately: the hex above is RGB-only, so a translucent
      // colour would otherwise silently paint fully opaque.
      colorFilter: color.a < 1.0
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }
}
