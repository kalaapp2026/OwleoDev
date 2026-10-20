import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/primitives.dart';

/// Paid / Due / Overdue / Waived, plus a "Part paid" tag when some money has come in.
class BillStatusTags extends StatelessWidget {
  const BillStatusTags(this.bill, {super.key});
  final Map<String, dynamic> bill;

  @override
  Widget build(BuildContext context) {
    final (tone, label) = switch (bill.str('status')) {
      'paid' => (Tone.green, 'Paid'),
      'overdue' => (Tone.red, 'Overdue'),
      'waived' => (Tone.mute, 'Waived'),
      _ => (Tone.blue, 'Due'),
    };
    return Wrap(spacing: 6, runSpacing: 4, children: [
      Tag(label, tone: tone),
      if (bill.flag('partPaid')) const Tag('Part paid', tone: Tone.gold),
    ]);
  }
}

/// The offer's headline: "20% off", "₹500 off" or "First month free".
String offerText(Map<String, dynamic> o) => switch (o.str('type')) {
      'pct' || 'PCT' => '${o.number('value').round()}% off',
      'flat' || 'FLAT' => '${inr(o.number('value'))} off',
      _ => 'First month free',
    };

String offerFor(Map<String, dynamic> o, Map<String, String> planNames) =>
    o.str('appliesTo') == 'all' ? 'All plans' : '${planNames[o.str('appliesTo')] ?? o.str('appliesTo')} plan';

/// Status of an offer as the Offers tab shows it: (label, tone).
(String, Tone) offerStatus(Map<String, dynamic> o) {
  if (!o.flag('active')) return ('Paused', Tone.mute);
  final today = DateTime.now();
  final from = toDate(o['startsOn']), to = toDate(o['endsOn']);
  if (to != null && to.isBefore(DateTime(today.year, today.month, today.day))) return ('Expired', Tone.mute);
  if (from != null && from.isAfter(today)) return ('Scheduled', Tone.blue);
  final limit = o.integerOrNull('limit');
  if (limit != null && o.integer('used') >= limit) return ('Used up', Tone.coral);
  return ('Active', Tone.green);
}

/// A date input that opens the themed picker; shows `5 Oct 2026`.
class DateButton extends StatelessWidget {
  const DateButton({super.key, required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: HqText.label),
        const SizedBox(height: 6),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(color: Hq.raised, borderRadius: BorderRadius.circular(12), border: Border.all(color: Hq.border)),
              child: Text(fd(value), style: HqText.body),
            ),
          ),
        ),
      ]),
    );
  }
}
