import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';

Map<String, dynamic> materialJson({
  String fileType = 'NOTES',
  String permission = 'DOWNLOADABLE',
  int sizeBytes = 430080,
  String? description,
  String? uploadedByName = 'Rahul Nair',
}) =>
    {
      'id': 'm1',
      'batchId': 'b1',
      'title': 'Chord Chart - Week 1',
      'description': description,
      'url': '/files/chord-chart.pdf',
      'fileName': 'chord-chart-week1.pdf',
      'contentType': 'application/pdf',
      'fileType': fileType,
      'sizeBytes': sizeBytes,
      'permission': permission,
      'uploadedBy': 'u1',
      'uploadedByName': uploadedByName,
      'uploadedAt': '2026-08-25T10:30:00Z',
    };

void main() {
  group('file type', () {
    test('round-trips every wire value', () {
      for (final type in StudyMaterialType.values) {
        expect(StudyMaterialType.fromWire(type.wire), type);
      }
    });

    test('an unknown type falls back to notes rather than throwing', () {
      // Notes is the widest bucket and its preview degrades most gracefully, so an unrecognised
      // file still renders as something openable.
      expect(StudyMaterialType.fromWire('VIDEO'), StudyMaterialType.notes);
      expect(StudyMaterialType.fromWire(null), StudyMaterialType.notes);
    });

    test('each type has its own colour so the filter chips are distinguishable', () {
      const p = AppPalette.dark;
      final colours = StudyMaterialType.values.map((t) => t.color(p)).toSet();
      expect(colours, hasLength(StudyMaterialType.values.length));
    });
  });

  group('permission', () {
    test('round-trips both values', () {
      for (final permission in StudyMaterialPermission.values) {
        expect(StudyMaterialPermission.fromWire(permission.wire), permission);
      }
    });

    test('an unknown permission falls back to downloadable', () {
      // Matches the column default, so a row written by an older build reads consistently.
      expect(StudyMaterialPermission.fromWire('SOMETHING_ELSE'),
          StudyMaterialPermission.downloadable);
      expect(StudyMaterialPermission.fromWire(null),
          StudyMaterialPermission.downloadable);
    });

    test('view-only explains that the download button disappears', () {
      // "View only" is ambiguous until you say what a student actually loses.
      expect(StudyMaterialPermission.viewOnly.explanation, contains('no download'));
      expect(StudyMaterialPermission.downloadable.explanation, contains('save'));
    });

    test('the two permissions never share a colour', () {
      const p = AppPalette.dark;
      expect(StudyMaterialPermission.downloadable.color(p),
          isNot(StudyMaterialPermission.viewOnly.color(p)));
    });
  });

  group('size formatting', () {
    test('shows KB below a megabyte and MB above', () {
      expect(StudyMaterial.fromJson(materialJson(sizeBytes: 430080)).sizeLabel, '420 KB');
      expect(
          StudyMaterial.fromJson(materialJson(sizeBytes: 3250586)).sizeLabel, '3.1 MB');
    });

    test('a tiny file rounds up rather than showing 0 KB', () {
      // "0 KB" reads as a failed upload.
      expect(StudyMaterial.fromJson(materialJson(sizeBytes: 200)).sizeLabel, '1 KB');
    });

    test('a zero-byte file still renders a label', () {
      expect(StudyMaterial.fromJson(materialJson(sizeBytes: 0)).sizeLabel, '0 KB');
    });
  });

  group('material deserialisation', () {
    test('reads the file and permission metadata', () {
      final m = StudyMaterial.fromJson(materialJson(
          fileType: 'AUDIO', permission: 'VIEW_ONLY', description: 'Practise slowly'));
      expect(m.fileType, StudyMaterialType.audio);
      expect(m.permission, StudyMaterialPermission.viewOnly);
      expect(m.isDownloadable, isFalse);
      expect(m.description, 'Practise slowly');
      expect(m.uploadedByName, 'Rahul Nair');
    });

    test('an absent description stays null rather than becoming empty text', () {
      expect(StudyMaterial.fromJson(materialJson()).description, isNull);
    });

    test('survives an uploader whose account no longer resolves', () {
      final m = StudyMaterial.fromJson(materialJson(uploadedByName: null));
      expect(m.uploadedByName, isNull);
      expect(m.title, isNotEmpty);
    });
  });

  group('batch summary', () {
    Map<String, dynamic> summaryJson({int fileCount = 3, String? lastUploaded}) => {
          'batchId': 'b1',
          'batchName': 'Batch A',
          'courseId': 'c1',
          'courseName': 'Guitar Beginner',
          'courseIconKey': 'guitar',
          'courseCategory': 'MUSIC',
          'batchStatus': 'ACTIVE',
          'fileCount': fileCount,
          'lastUploadedAt': lastUploaded,
        };

    test('reads the count and last-updated date', () {
      final s = BatchMaterialSummary.fromJson(
          summaryJson(lastUploaded: '2026-08-29T09:00:00Z'));
      expect(s.fileCount, 3);
      expect(s.lastUploadedAt, isNotNull);
      expect(s.courseCategory, CourseCategory.music);
      expect(s.isActive, isTrue);
    });

    test('a batch with nothing shared has a null date, not an epoch', () {
      // The row says "No files yet" off the back of this - a fallback date would render as a
      // real upload that never happened.
      final s = BatchMaterialSummary.fromJson(summaryJson(fileCount: 0));
      expect(s.fileCount, 0);
      expect(s.lastUploadedAt, isNull);
    });

    test('an unknown course category degrades to the neutral treatment', () {
      final json = summaryJson()..['courseCategory'] = 'ASTROPHYSICS';
      expect(BatchMaterialSummary.fromJson(json).courseCategory, CourseCategory.unknown);
    });

    test('missing optional fields do not break the row', () {
      final s = BatchMaterialSummary.fromJson({'batchId': 'b1'});
      expect(s.fileCount, 0);
      expect(s.batchName, '');
      expect(s.isActive, isTrue);
    });
  });
}
