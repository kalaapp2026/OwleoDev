import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_settings_api.dart';
import 'package:nest_fe/features/academy/presentation/academy_settings_kit.dart';
import 'package:share_plus/share_plus.dart';

class _ExportKind {
  const _ExportKind(this.key, this.label, this.subtitle, this.icon);
  final String key;
  final String label;
  final String subtitle;
  final IconData icon;
}

const _kinds = [
  _ExportKind('students', 'Students', 'Names, contact details and enrolled courses', Icons.groups_outlined),
  _ExportKind('fees', 'Fees ledger', 'Every payment, including reversals', Icons.receipt_long_outlined),
  _ExportKind('attendance', 'Attendance', 'Class attendance for the last 12 months', Icons.event_available_outlined),
];

String _sizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Download the academy's own data as CSV. Each export is built on the server from this academy's
/// records only, opens straight in Excel or Sheets, and is logged so recent ones are listed below.
class AcademyExportScreen extends ConsumerStatefulWidget {
  const AcademyExportScreen({super.key});

  @override
  ConsumerState<AcademyExportScreen> createState() => _AcademyExportScreenState();
}

class _AcademyExportScreenState extends ConsumerState<AcademyExportScreen> {
  String? _busyKind;

  Future<void> _export(_ExportKind kind) async {
    if (_busyKind != null) return;
    setState(() => _busyKind = kind.key);
    try {
      final file = await ref.read(academySettingsApiProvider).downloadExport(kind.key);
      ref.invalidate(recentExportsProvider);
      await Share.shareXFiles(
        [XFile.fromData(Uint8List.fromList(file.bytes), name: file.fileName, mimeType: 'text/csv')],
        text: '${kind.label} export',
      );
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busyKind = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final recentAsync = ref.watch(recentExportsProvider);
    final colors = [
      (palette.primary, palette.primarySoft),
      (palette.gold, palette.goldSoft),
      (palette.gateway, palette.gatewaySoft),
    ];

    return SettingsPage(
      title: 'Export & Backup',
      onRefresh: () async => ref.invalidate(recentExportsProvider),
      children: [
        const SettingsNote(
          text: 'Each file is built from this academy\'s records only and opens in Excel or Google Sheets. '
              'Anyone you share it with sees everything in it, so treat it like the records themselves.',
          icon: Icons.lock_outline,
        ),
        const SettingsSectionLabel('Export'),
        for (var i = 0; i < _kinds.length; i++) ...[
          SettingsCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Row(
              children: [
                SettingsIconTile(icon: _kinds[i].icon, color: colors[i].$1, soft: colors[i].$2),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_kinds[i].label, style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.heavy, color: palette.text)),
                      Text(_kinds[i].subtitle, style: TextStyle(fontSize: AppType.sm, color: palette.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Pressable(
                  onTap: _busyKind == null ? () => _export(_kinds[i]) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: colors[i].$2,
                      borderRadius: AppRadii.all(AppRadii.md),
                      border: Border.all(color: colors[i].$1.withValues(alpha: 0.33)),
                    ),
                    child: _busyKind == _kinds[i].key
                        ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: colors[i].$1))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.download_rounded, size: 13, color: colors[i].$1),
                            const SizedBox(width: 5),
                            Text('CSV', style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: colors[i].$1)),
                          ]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        const SettingsSectionLabel('Recent exports'),
        AsyncValueView<List<ExportRecord>>(
          value: recentAsync,
          onRetry: () => ref.invalidate(recentExportsProvider),
          data: (context, records) {
            if (records.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text('Nothing exported yet.', style: TextStyle(fontSize: AppType.md, color: palette.textFaint)),
              );
            }
            return SettingsCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                children: [
                  for (var i = 0; i < records.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        border: i == records.length - 1 ? null : Border(bottom: BorderSide(color: palette.borderSoft)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 14, color: palette.textFaint),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(records[i].fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: AppType.md, fontWeight: AppType.semi, color: palette.text)),
                                Text('${shortDate(records[i].createdAt)} · ${records[i].rowCount} rows · ${_sizeLabel(records[i].sizeBytes)}',
                                    style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
