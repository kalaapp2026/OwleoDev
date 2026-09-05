import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/design/category_meta.dart';

/// What kind of file a material is - decides the icon, the filter chip it falls under, and which
/// preview the viewer renders.
enum StudyMaterialType {
  notes('NOTES', 'Notes & Docs'),
  audio('AUDIO', 'Audio'),
  image('IMAGE', 'Image');

  const StudyMaterialType(this.wire, this.label);

  final String wire;
  final String label;

  static StudyMaterialType fromWire(String? value) =>
      values.firstWhere((t) => t.wire == value, orElse: () => StudyMaterialType.notes);

  IconData get icon => switch (this) {
        StudyMaterialType.notes => Icons.description_outlined,
        StudyMaterialType.audio => Icons.music_note_outlined,
        StudyMaterialType.image => Icons.image_outlined,
      };

  Color color(AppPalette p) => switch (this) {
        StudyMaterialType.notes => p.primary,
        StudyMaterialType.audio => p.coral,
        StudyMaterialType.image => p.gateway,
      };

  Color softColor(AppPalette p) => switch (this) {
        StudyMaterialType.notes => p.primarySoft,
        StudyMaterialType.audio => p.coralSoft,
        StudyMaterialType.image => p.gatewaySoft,
      };
}

/// Whether students may keep a copy or only open it in the app.
enum StudyMaterialPermission {
  downloadable('DOWNLOADABLE', 'Downloadable'),
  viewOnly('VIEW_ONLY', 'View only');

  const StudyMaterialPermission(this.wire, this.label);

  final String wire;
  final String label;

  static StudyMaterialPermission fromWire(String? value) =>
      value == 'VIEW_ONLY'
          ? StudyMaterialPermission.viewOnly
          : StudyMaterialPermission.downloadable;

  IconData get icon => this == StudyMaterialPermission.downloadable
      ? Icons.download_outlined
      : Icons.lock_outline;

  Color color(AppPalette p) =>
      this == StudyMaterialPermission.downloadable ? p.paidManual : p.violet;

  Color softColor(AppPalette p) =>
      this == StudyMaterialPermission.downloadable ? p.paidManualSoft : p.violetSoft;

  /// What this actually means for a student, spelled out on the upload form - "view only" is
  /// ambiguous until you say the download button disappears.
  String get explanation => this == StudyMaterialPermission.downloadable
      ? 'Students can save this file to their device.'
      : 'Students can only view this inside the app - no download option is shown to them.';
}

/// One shared file.
class StudyMaterial {
  const StudyMaterial({
    required this.id,
    required this.batchId,
    required this.title,
    required this.description,
    required this.url,
    required this.fileName,
    required this.contentType,
    required this.fileType,
    required this.sizeBytes,
    required this.permission,
    required this.uploadedByName,
    required this.uploadedAt,
  });

  final String id;
  final String batchId;
  final String title;
  final String? description;
  final String url;
  final String fileName;
  final String? contentType;
  final StudyMaterialType fileType;
  final int sizeBytes;
  final StudyMaterialPermission permission;
  final String? uploadedByName;
  final DateTime uploadedAt;

  bool get isDownloadable => permission == StudyMaterialPermission.downloadable;

  /// "420 KB" / "3.1 MB". Files here are small enough that GB never comes up.
  String get sizeLabel {
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.ceil()} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  factory StudyMaterial.fromJson(Map<String, dynamic> json) => StudyMaterial(
        id: json['id'] as String,
        batchId: json['batchId'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        url: json['url'] as String,
        fileName: json['fileName'] as String? ?? '',
        contentType: json['contentType'] as String?,
        fileType: StudyMaterialType.fromWire(json['fileType'] as String?),
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        permission: StudyMaterialPermission.fromWire(json['permission'] as String?),
        uploadedByName: json['uploadedByName'] as String?,
        uploadedAt: DateTime.parse(json['uploadedAt'] as String),
      );
}

/// One row on the Study Material home screen: a batch and what has been shared with it.
class BatchMaterialSummary {
  const BatchMaterialSummary({
    required this.batchId,
    required this.batchName,
    required this.courseId,
    required this.courseName,
    required this.courseIconKey,
    required this.courseCategory,
    required this.batchStatus,
    required this.fileCount,
    required this.lastUploadedAt,
  });

  final String batchId;
  final String batchName;
  final String? courseId;
  final String? courseName;
  final String? courseIconKey;
  final CourseCategory courseCategory;
  final String batchStatus;
  final int fileCount;

  /// Null when nothing has been shared - the row says "No files yet" rather than a stale date.
  final DateTime? lastUploadedAt;

  bool get isActive => batchStatus == 'ACTIVE';

  factory BatchMaterialSummary.fromJson(Map<String, dynamic> json) => BatchMaterialSummary(
        batchId: json['batchId'] as String,
        batchName: json['batchName'] as String? ?? '',
        courseId: json['courseId'] as String?,
        courseName: json['courseName'] as String?,
        courseIconKey: json['courseIconKey'] as String?,
        courseCategory: CourseCategory.fromWire(json['courseCategory'] as String?),
        batchStatus: json['batchStatus'] as String? ?? 'ACTIVE',
        fileCount: json['fileCount'] as int? ?? 0,
        lastUploadedAt: json['lastUploadedAt'] == null
            ? null
            : DateTime.tryParse(json['lastUploadedAt'] as String),
      );
}
