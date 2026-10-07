import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/data/study_material_api.dart';

/// The newest files shared with the student across songs, documents and images. The library
/// endpoint already applies the per-student visibility rules, so nothing is filtered here.
final _latestMaterialProvider = FutureProvider.autoDispose<List<StudyMaterial>>((ref) async {
  ref.watch(activeMembershipIdProvider);
  final api = ref.watch(studyMaterialApiProvider);
  final all = <StudyMaterial>[];
  for (final type in StudyMaterialType.values) {
    all.addAll(await api.library(type));
  }
  all.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
  return all.take(3).toList();
});

class StudentMaterialStrip extends ConsumerWidget {
  const StudentMaterialStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final items = ref.watch(_latestMaterialProvider).valueOrNull ?? const <StudyMaterial>[];
    // Nothing shared yet (or still loading): no empty card, the section simply isn't there.
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Study material',
            style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text)),
        Pressable(
          onTap: () => context.push('/erp/study-materials'),
          child: Text('See all',
              style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.primary)),
        ),
      ]),
      const SizedBox(height: AppSpacing.md),
      for (final m in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Pressable(
            onTap: () => context.push('/erp/study-materials'),
            borderRadius: AppRadii.all(AppRadii.xl),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: AppRadii.all(AppRadii.xl),
                border: Border.all(color: palette.border),
              ),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: palette.violetSoft, borderRadius: AppRadii.all(AppRadii.md)),
                  child: Icon(Icons.description_outlined, size: 15, color: palette.violet),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.text)),
                    const SizedBox(height: 2),
                    Text(m.fileType.label, style: TextStyle(fontSize: 10, color: palette.textFaint)),
                  ]),
                ),
                Icon(Icons.chevron_right, size: 14, color: palette.textFaint),
              ]),
            ),
          ),
        ),
    ]);
  }
}
