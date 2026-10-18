import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/features/messages/data/broadcast.dart';

const _fallbackAudienceLabels = {
  'ALL_STUDENTS': 'All students',
  'ALL_TRAINERS': 'All trainers',
  'BY_COURSE': 'By course',
  'BY_BATCH': 'By batch',
  'INDIVIDUALS': 'Individuals',
};

/// Who a broadcast went to, in words. The server names the courses and batches; the type label is
/// only a fallback for a response that omits it.
String audienceLabelOf(Broadcast b) => b.audienceLabel ?? _fallbackAudienceLabels[b.audienceType] ?? b.audienceType;

/// Each audience keeps one colour so a glance down the list shows who a message went to.
({Color color, Color soft}) audienceTone(AppPalette palette, String audienceType) => switch (audienceType) {
      'ALL_TRAINERS' => (color: palette.gateway, soft: palette.gatewaySoft),
      'BY_COURSE' => (color: palette.primary, soft: palette.primarySoft),
      'BY_BATCH' => (color: palette.gold, soft: palette.goldSoft),
      'INDIVIDUALS' => (color: palette.violet, soft: palette.violetSoft),
      _ => (color: palette.gold, soft: palette.goldSoft),
    };

/// "just now", "5m ago", "3h ago", "2d ago" - the stamp on a broadcast.
String longAgo(String iso) {
  final at = DateTime.tryParse(iso)?.toLocal();
  if (at == null) return '';
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}

/// The gold TRAINER tag beside a name.
class TrainerTag extends StatelessWidget {
  const TrainerTag({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: palette.goldSoft, borderRadius: AppRadii.all(AppRadii.sm)),
      child: Text('TRAINER', style: TextStyle(fontSize: 9, fontWeight: AppType.heavy, color: palette.gold)),
    );
  }
}
