import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/network/api_config.dart';

/// Raised surface with the standard border - the profile screens' basic container.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(AppSpacing.xl)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final body = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
    return onTap == null ? body : Pressable(onTap: onTap, child: body);
  }
}

/// Title row with optional "Add" and "View all" actions.
class ProfileSection extends StatelessWidget {
  const ProfileSection({super.key, required this.title, required this.child, this.onAdd, this.onViewAll});
  final String title;
  final Widget child;
  final VoidCallback? onAdd;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget action(IconData icon, String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Row(children: [
            Icon(icon, size: 13, color: palette.primary),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.primary)),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.heavy, color: palette.text)),
              ),
              if (onAdd != null) action(Icons.add, 'Add', onAdd!),
              if (onAdd != null && onViewAll != null) const SizedBox(width: AppSpacing.xl),
              if (onViewAll != null) action(Icons.chevron_right, 'View all', onViewAll!),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class ProfileEmptyNote extends StatelessWidget {
  const ProfileEmptyNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return CustomPaint(
      painter: _DashedBorderPainter(color: palette.border, radius: AppRadii.xl),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xxl),
        decoration: BoxDecoration(color: palette.surface, borderRadius: AppRadii.all(AppRadii.xl)),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppType.smd, color: palette.textFaint, height: 1.5)),
      ),
    );
  }
}

/// The prototype's empty states use a dashed border, which Flutter has no built-in for.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color || old.radius != radius;
}

/// Small round-cornered icon tile used at the start of cards.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, required this.color, this.size = 38});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: color.withValues(alpha: 0.33)),
      ),
      child: Icon(icon, size: size * 0.47, color: color),
    );
  }
}

/// Photo when there is one, initials otherwise.
class PhotoAvatar extends StatelessWidget {
  const PhotoAvatar({super.key, required this.name, required this.url, this.size = 84});
  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolved = ApiConfig.resolveMediaUrl(url);
    if (resolved == null) return InitialsAvatar(name: name, size: size);
    return ClipRRect(
      borderRadius: AppRadii.all(size * 0.3),
      child: Image.network(
        resolved,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => InitialsAvatar(name: name, size: size),
      ),
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.label, required this.value, this.icon, this.onTap});
  final String label;
  final String? value;
  final IconData? icon;

  /// Optional, and invisible: the row looks the same either way. Staff use it to tap-to-call.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 13, color: palette.textFaint)),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint, letterSpacing: 0.3)),
                const SizedBox(height: 1),
                Text(value!, style: TextStyle(fontSize: AppType.base, color: palette.text, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
    return onTap == null ? row : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row);
  }
}

// ---- Form pieces shared by the edit / add screens ----

class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: AppType.tiny,
                fontWeight: AppType.bold,
                color: context.palette.textFaint,
                letterSpacing: 0.3)),
      );
}

InputDecoration profileInputDecoration(BuildContext context, {String? hint}) {
  final palette = context.palette;
  OutlineInputBorder border(Color c) =>
      OutlineInputBorder(borderRadius: AppRadii.all(AppRadii.xl), borderSide: BorderSide(color: c));
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: palette.textFaint),
    filled: true,
    fillColor: palette.surfaceRaised,
    counterText: '',
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
    border: border(palette.border),
    enabledBorder: border(palette.border),
    focusedBorder: border(palette.primary),
  );
}

/// Label + text input.
class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel(label),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: TextStyle(color: context.palette.text, fontSize: AppType.md),
          decoration: profileInputDecoration(context, hint: hint),
        ),
      ],
    );
  }
}

/// Tappable field that shows a value and opens a picker (dates).
class PickerField extends StatelessWidget {
  const PickerField({super.key, required this.label, required this.text, required this.icon, required this.onTap, this.placeholder = false});
  final String label;
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel(label),
        Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.xl),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(text,
                      style: TextStyle(fontSize: AppType.md, color: placeholder ? palette.textFaint : palette.text)),
                ),
                Icon(icon, size: 15, color: palette.textFaint),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Wrap of selectable chips, each optionally carrying its own icon and colour.
class ChipChoices<T> extends StatelessWidget {
  const ChipChoices({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.iconOf,
    this.colorOf,
  });
  final List<T> options;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final IconData? Function(T)? iconOf;
  final Color Function(T)? colorOf;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final o in options)
          Builder(builder: (context) {
            final active = o == selected;
            final color = colorOf?.call(o) ?? palette.primary;
            final icon = iconOf?.call(o);
            return Pressable(
              onTap: () => onSelected(o),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: active ? color.withValues(alpha: 0.13) : palette.surfaceRaised,
                  borderRadius: AppRadii.all(AppRadii.md),
                  border: Border.all(color: active ? color : palette.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[Icon(icon, size: 13, color: active ? color : palette.textMuted), const SizedBox(width: 6)],
                    Text(labelOf(o),
                        style: TextStyle(
                            fontSize: AppType.smd,
                            fontWeight: AppType.bold,
                            color: active ? color : palette.textMuted)),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// Destructive "Delete" action for an app bar.
class DeleteAction extends StatelessWidget {
  const DeleteAction({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        child: Text('Delete', style: TextStyle(color: context.palette.notPaid, fontWeight: AppType.bold)),
      );
}
