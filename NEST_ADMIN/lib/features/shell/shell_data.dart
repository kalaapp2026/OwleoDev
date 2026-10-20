import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session.dart';

/// One thing that needs a look today (the bell and the Alerts page).
class HqAlert {
  const HqAlert({
    required this.kind,
    required this.tone,
    required this.icon,
    required this.title,
    required this.text,
    this.academyId,
  });

  factory HqAlert.fromJson(Map<String, dynamic> j) => HqAlert(
        kind: j['kind'] as String? ?? '',
        tone: j['tone'] as String? ?? 'mute',
        icon: j['icon'] as String? ?? 'bell',
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        academyId: j['academyId'] as String?,
      );

  final String kind;
  final String tone;
  final String icon;
  final String title;
  final String text;
  final String? academyId;
}

/// Open alerts, computed on the server from live data.
final alertsProvider = FutureProvider.autoDispose<List<HqAlert>>((ref) async {
  final rows = await ref.watch(dioClientProvider).getList('/admin/hq/alerts');
  return rows.map(HqAlert.fromJson).toList();
});

/// The little red counts on the More tiles and dock: module id -> number waiting.
final badgesProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final m = await ref.watch(dioClientProvider).getMap('/admin/hq/badges');
  return m.map((k, v) => MapEntry(k, (v as num).toInt()));
});
