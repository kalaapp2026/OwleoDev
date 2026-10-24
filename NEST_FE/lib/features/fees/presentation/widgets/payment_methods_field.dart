import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';

/// Which payment methods a fee accepts - Cash, UPI, Gateway - as one rounded bar of toggles.
///
/// Several can be on at once ("more than one is fine"), so this is a set of independent toggles, not
/// a single choice. The first one on is the fee's default, which is why [selected] keeps the order
/// they were switched on in.
class PaymentMethodsField extends StatelessWidget {
  const PaymentMethodsField({super.key, required this.selected, required this.onToggle});

  final List<String> selected;
  final ValueChanged<String> onToggle;

  static const methods = [('CASH', 'Cash'), ('UPI', 'UPI'), ('GATEWAY', 'Gateway')];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.text.withValues(alpha: 0.4), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < methods.length; i++)
            Expanded(
              child: Pressable(
                onTap: () => onToggle(methods[i].$1),
                child: AnimatedContainer(
                  duration: AppMotion.fade,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: selected.contains(methods[i].$1) ? palette.gold : Colors.transparent,
                    border: i < methods.length - 1
                        ? Border(
                            right: BorderSide(color: palette.text.withValues(alpha: 0.3)),
                          )
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (selected.contains(methods[i].$1)) ...[
                        Icon(Icons.check_rounded, size: 14, color: palette.onGold),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        methods[i].$2,
                        style: TextStyle(
                          fontSize: AppType.lg,
                          fontWeight: AppType.bold,
                          color: selected.contains(methods[i].$1) ? palette.onGold : palette.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
