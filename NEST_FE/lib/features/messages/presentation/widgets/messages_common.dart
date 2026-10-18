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

/// "now", "5m", "3h", "2d" - the compact stamp on a chat row.
String shortAgo(String iso) {
  final at = DateTime.tryParse(iso)?.toLocal();
  if (at == null) return '';
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 30) return '${diff.inDays}d';
  return '${(diff.inDays / 30).floor()}mo';
}

/// "just now", "5m ago" - the stamp under a bubble and on a broadcast.
String longAgo(String iso) {
  final short = shortAgo(iso);
  if (short.isEmpty) return '';
  return short == 'now' ? 'just now' : '$short ago';
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

/// A small count pill - unread messages.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.background, this.foreground});

  final int count;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background ?? palette.primary, borderRadius: BorderRadius.circular(9)),
      child: Text('$count',
          style: TextStyle(fontSize: 10.5, fontWeight: AppType.heavy, color: foreground ?? palette.onPrimary)),
    );
  }
}

/// The search box used at the top of the chat list and the new-chat sheet.
class MessagesSearchField extends StatelessWidget {
  const MessagesSearchField({super.key, required this.hint, required this.onChanged, this.autofocus = false});

  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: palette.textFaint),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: TextField(
              autofocus: autofocus,
              onChanged: onChanged,
              style: TextStyle(fontSize: AppType.xl, color: palette.text),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: palette.textFaint),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
