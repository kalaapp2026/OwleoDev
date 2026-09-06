import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/features/curriculum/data/material_playlist.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';

Map<String, dynamic> _material(String id, {String title = 'Track'}) => {
      'id': id,
      'batchId': 'b1',
      'title': title,
      'url': '/uploads/$id.mp3',
      'fileName': '$id.mp3',
      'fileType': 'AUDIO',
      'sizeBytes': 3200,
      'permission': 'VIEW_ONLY',
      'uploadedAt': '2026-09-01T10:00:00Z',
    };

void main() {
  group('playback time', () {
    test('formats seconds as m:ss', () {
      expect(formatPlaybackTime(0), '0:00');
      expect(formatPlaybackTime(9), '0:09');
      expect(formatPlaybackTime(65), '1:05');
      expect(formatPlaybackTime(600), '10:00');
    });

    test('a negative position renders as zero rather than "-0:-1"', () {
      // Reachable by seeking backwards past the start, which some platforms report briefly.
      expect(formatPlaybackTime(-5), '0:00');
    });

    test('parses both m:ss and a bare second count', () {
      expect(parsePlaybackTime('1:30'), 90);
      expect(parsePlaybackTime('0:07'), 7);
      expect(parsePlaybackTime('45'), 45);
      expect(parsePlaybackTime('  2:00  '), 120);
    });

    test('rejects nonsense rather than guessing at it', () {
      expect(parsePlaybackTime(''), isNull);
      expect(parsePlaybackTime('abc'), isNull);
      expect(parsePlaybackTime('1:2:3'), isNull);
      // 90 seconds past the minute is a typo, not 2:30 - silently accepting it would put the
      // trim somewhere the user did not ask for.
      expect(parsePlaybackTime('1:90'), isNull);
    });

    test('empty is null, not zero - "not entered" differs from "the start"', () {
      expect(parsePlaybackTime(''), isNull);
      expect(parsePlaybackTime('0'), 0);
    });
  });

  group('segments', () {
    test('a segment ending before it starts is invalid', () {
      expect(const PlaybackSegment(start: 10, end: 30, speed: 1).isValid, isTrue);
      expect(const PlaybackSegment(start: 30, end: 10, speed: 1).isValid, isFalse);
      // Zero-length plays for no time at all, which looks like a broken track.
      expect(const PlaybackSegment(start: 10, end: 10, speed: 1).isValid, isFalse);
    });

    test('round-trips through JSON keeping its own speed', () {
      const original = PlaybackSegment(start: 12, end: 48, speed: 0.75);
      final restored = PlaybackSegment.fromJson(original.toJson());
      expect(restored.start, 12);
      expect(restored.end, 48);
      expect(restored.speed, 0.75);
      expect(restored.duration, const Duration(seconds: 36));
    });
  });

  group('playback settings', () {
    test('defaults are full speed, audible, no loop, whole track', () {
      const settings = PlaybackSettings();
      expect(settings.speed, 1.0);
      expect(settings.volume, 80);
      expect(settings.loopEnabled, isFalse);
      expect(settings.isTrimmed, isFalse);
    });

    test('an absent payload degrades to defaults rather than throwing', () {
      final settings = PlaybackSettings.fromJson(const {});
      expect(settings.speed, 1.0);
      expect(settings.volume, 80);
      expect(settings.segments, isEmpty);
    });

    test('copyWith leaves untouched fields alone', () {
      const settings = PlaybackSettings(speed: 0.5, volume: 30, loopEnabled: true);
      final next = settings.copyWith(volume: 90);
      expect(next.volume, 90);
      expect(next.speed, 0.5);
      expect(next.loopEnabled, isTrue);
    });
  });

  group('playlist', () {
    test('counts a repeated song twice in length but once as distinct', () {
      // The whole reason entries carry their own ids: the same piece played slowly, then
      // up to tempo, is two entries over one material.
      final playlist = MaterialPlaylist.fromJson({
        'id': 'p1',
        'name': 'Warm-ups',
        'createdAt': '2026-09-01T10:00:00Z',
        'entries': [
          {'entryId': 'e1', 'position': 0, 'material': _material('m1')},
          {'entryId': 'e2', 'position': 1, 'material': _material('m2')},
          {'entryId': 'e3', 'position': 2, 'material': _material('m1')},
        ],
      });

      expect(playlist.length, 3);
      expect(playlist.distinctMaterials, 2);
      expect(playlist.countLabel, '3 songs');
      // Distinct entry ids are what removal and reordering address.
      expect(playlist.entries.map((e) => e.entryId).toSet().length, 3);
    });

    test('an empty playlist reads as zero, not as broken', () {
      final playlist = MaterialPlaylist.fromJson({
        'id': 'p1',
        'name': 'New',
        'createdAt': '2026-09-01T10:00:00Z',
      });
      expect(playlist.length, 0);
      expect(playlist.distinctMaterials, 0);
      expect(playlist.entries, isEmpty);
    });

    test('one song is singular', () {
      final playlist = MaterialPlaylist.fromJson({
        'id': 'p1',
        'name': 'Solo',
        'createdAt': '2026-09-01T10:00:00Z',
        'entries': [
          {'entryId': 'e1', 'position': 0, 'material': _material('m1')},
        ],
      });
      expect(playlist.countLabel, '1 song');
    });
  });

  group('material visibility', () {
    test('SELECTED is honoured', () {
      expect(StudyMaterialVisibility.fromWire('SELECTED'),
          StudyMaterialVisibility.selected);
    });

    test('anything else reads as ALL, including null', () {
      // Every material uploaded before the column existed sends nothing here, and it means
      // "the whole batch" - the safe direction to guess.
      expect(StudyMaterialVisibility.fromWire(null), StudyMaterialVisibility.all);
      expect(StudyMaterialVisibility.fromWire('ALL'), StudyMaterialVisibility.all);
      expect(StudyMaterialVisibility.fromWire('nonsense'), StudyMaterialVisibility.all);
    });

    test('a material parses its audience, defaulting to empty', () {
      final withAudience = StudyMaterial.fromJson({
        ..._material('m1'),
        'visibility': 'SELECTED',
        'studentIds': ['s1', 's2'],
      });
      expect(withAudience.visibility, StudyMaterialVisibility.selected);
      expect(withAudience.studentIds, {'s1', 's2'});

      final without = StudyMaterial.fromJson(_material('m2'));
      expect(without.visibility, StudyMaterialVisibility.all);
      expect(without.studentIds, isEmpty);
    });
  });
}
