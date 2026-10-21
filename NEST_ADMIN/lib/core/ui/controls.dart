import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import 'icons.dart';

enum BtnKind { normal, primary, danger, ghost }

/// `.btn`: 40px (32px small) rounded button. [busy] swaps the label for a spinner and blocks taps,
/// so a slow save can't be fired twice.
class HqButton extends StatefulWidget {
  const HqButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.kind = BtnKind.normal,
    this.small = false,
    this.expand = false,
    this.busy = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final BtnKind kind;
  final bool small;
  final bool expand;
  final bool busy;
  final Color? color;

  @override
  State<HqButton> createState() => _HqButtonState();
}

class _HqButtonState extends State<HqButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final h = widget.small ? 32.0 : 40.0;
    final k = widget.kind;
    final bg = switch (k) {
      BtnKind.primary => Hq.primary,
      BtnKind.ghost => Colors.transparent,
      _ => Hq.raised,
    };
    final fg = widget.color ??
        switch (k) {
          BtnKind.primary => Hq.onPrimary,
          BtnKind.danger => Hq.red,
          _ => Hq.text,
        };
    final borderColor = switch (k) {
      BtnKind.primary => Hq.primary,
      BtnKind.danger => Hq.red.withValues(alpha: .4),
      BtnKind.ghost => Colors.transparent,
      _ => _hover && enabled ? Hq.faint : Hq.border,
    };
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy)
          SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else ...[
          if (widget.icon != null) ...[ic(widget.icon!, widget.small ? 13 : 15, fg), const SizedBox(width: 7)],
          Flexible(
            child: Text(widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HqText.button.copyWith(fontSize: widget.small ? 12 : 13, color: fg)),
          ),
        ],
      ],
    );
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: Opacity(
          opacity: widget.onPressed == null && !widget.busy ? .45 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: h,
            padding: EdgeInsets.symmetric(horizontal: widget.small ? 12 : 16),
            decoration: BoxDecoration(
              color: k == BtnKind.primary && _hover && enabled ? Hq.primary.withValues(alpha: .92) : bg,
              borderRadius: BorderRadius.circular(widget.small ? 10 : Hq.radiusBtn),
              border: Border.all(color: borderColor),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// `.ibtn`: 40px square icon button, optionally with a red count badge.
class HqIconButton extends StatelessWidget {
  const HqIconButton(this.icon, {super.key, this.onTap, this.badge, this.size = 40, this.tooltip, this.iconColor});

  final String icon;
  final VoidCallback? onTap;
  final int? badge;
  final double size;
  final String? tooltip;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    Widget btn = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Hq.raised,
                borderRadius: BorderRadius.circular(size * .3),
                border: Border.all(color: Hq.border),
              ),
              child: Center(child: ic(icon, size * .42, iconColor ?? Hq.text)),
            ),
            if (badge != null && badge! > 0)
              Positioned(
                top: -5,
                right: -5,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  height: 17,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: Hq.red, borderRadius: BorderRadius.circular(9)),
                  alignment: Alignment.center,
                  child: Text('$badge', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
    if (tooltip != null) btn = Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

/// `.seg`: the pill-shaped segmented control.
class SegControl<T> extends StatelessWidget {
  const SegControl({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.expand = false,
    this.dense = false,
  });

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  /// Stretch to the full width with equal-width segments (`style="width:100%"` + `flex:1`).
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final (v, label) in items)
        _seg(label, v == value, () => onChanged(v)),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Hq.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Hq.border),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            expand ? Expanded(child: children[i]) : children[i],
          ],
        ],
      ),
    );
  }

  Widget _seg(String label, bool on, VoidCallback tap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: 5),
          decoration: BoxDecoration(color: on ? Hq.high : Colors.transparent, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HqText.button.copyWith(fontSize: 12, color: on ? Hq.text : Hq.muted)),
        ),
      ),
    );
  }
}

/// `.chip`: pill filter with an optional count.
class HqChip extends StatelessWidget {
  const HqChip(this.label, {super.key, required this.selected, required this.onTap, this.count, this.leading});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Hq.primary : Hq.muted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Hq.tint(Hq.primary, .12) : Hq.raised,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? Hq.primary.withValues(alpha: .4) : Hq.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              Text(label, style: HqText.button.copyWith(fontSize: 12.5, color: fg)),
              if (count != null) ...[
                const SizedBox(width: 6),
                Opacity(opacity: .7, child: Text('$count', style: HqText.button.copyWith(fontSize: 12.5, color: fg))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A wrapping row of chips.
class ChipRow extends StatelessWidget {
  const ChipRow(this.chips, {super.key, this.scroll = false});
  final List<Widget> chips;

  /// One horizontally scrolling line instead of wrapping (`flex-wrap:nowrap;overflow-x:auto`).
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    if (scroll) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [for (var i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: 8), chips[i]]]),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

/// `.search`: rounded search box that reports each keystroke.
class SearchBox extends StatefulWidget {
  const SearchBox({super.key, required this.onChanged, this.hint = 'Search', this.initial = '', this.height = 40});

  final ValueChanged<String> onChanged;
  final String hint;
  final String initial;
  final double height;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: Hq.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _f.hasFocus ? Hq.primary : Hq.border),
      ),
      child: Row(
        children: [
          ic('search', 16, Hq.faint),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: _c,
              focusNode: _f,
              onChanged: widget.onChanged,
              style: HqText.body.copyWith(fontSize: 13),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: HqText.body.copyWith(fontSize: 13, color: Hq.faint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.field`: label above a 42px input.
class HqField extends StatelessWidget {
  const HqField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.error,
    this.keyboard,
    this.obscure = false,
    this.maxLines = 1,
    this.onChanged,
    this.readOnly = false,
    this.suffix,
    this.formatters,
    this.autofocus = false,
    this.onSubmitted,
    this.maxLength,
    this.bottom = 13,
    this.helper,
    this.focusNode,
  });

  final String label;
  final FocusNode? focusNode;
  final TextEditingController? controller;
  final String? hint;
  final String? error;
  final TextInputType? keyboard;
  final bool obscure;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final Widget? suffix;
  final List<TextInputFormatter>? formatters;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;
  final double bottom;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: HqText.label),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboard,
            obscureText: obscure,
            maxLines: obscure ? 1 : maxLines,
            minLines: 1,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            readOnly: readOnly,
            autofocus: autofocus,
            maxLength: maxLength,
            inputFormatters: formatters,
            style: HqText.body,
            cursorColor: Hq.primary,
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              filled: true,
              fillColor: Hq.raised,
              hintText: hint,
              hintStyle: HqText.body.copyWith(color: Hq.faint),
              suffixIcon: suffix,
              contentPadding: EdgeInsets.symmetric(horizontal: 13, vertical: maxLines > 1 ? 12 : 13),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: hasError ? Hq.red : Hq.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: hasError ? Hq.red : Hq.primary),
              ),
            ),
          ),
          if (helper != null && !hasError) Padding(padding: const EdgeInsets.only(top: 5), child: Text(helper!, style: HqText.sub)),
          if (hasError) Padding(padding: const EdgeInsets.only(top: 5), child: Text(error!, style: HqText.small.copyWith(color: Hq.red))),
        ],
      ),
    );
  }
}

/// One option in an [HqSelect].
class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.disabled = false});
  final T value;
  final String label;
  final bool disabled;
}

/// The prototype turns every `<select>` into a searchable panel that opens directly under its
/// field. This is that: a field-looking trigger, and an overlay with a search box and the options.
class HqSelect<T> extends StatefulWidget {
  const HqSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint = 'Choose',
    this.enabled = true,
    this.error,
    this.bottom = 13,
    this.searchable = true,
    this.compact = false,
  });

  final List<SelectOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? label;
  final String hint;
  final bool enabled;
  final String? error;
  final double bottom;
  final bool searchable;

  /// 36px tall instead of 42, for use inside a row of controls.
  final bool compact;

  @override
  State<HqSelect<T>> createState() => _HqSelectState<T>();
}

class _HqSelectState<T> extends State<HqSelect<T>> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted && _open) setState(() => _open = false);
  }

  void _openPanel() {
    if (!widget.enabled || widget.options.isEmpty) return;
    final box = context.findRenderObject() as RenderBox;
    final triggerOrigin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final below = screen.height - (triggerOrigin.dy + box.size.height) - 10;
    final above = triggerOrigin.dy - 10;
    final up = below < 230 && above > below;
    final maxH = (up ? above : below).clamp(150.0, 330.0);
    final width = box.size.width < 200 ? 200.0 : box.size.width;

    _entry = OverlayEntry(
      builder: (_) => _SelectPanel<T>(
        link: _link,
        width: width,
        maxHeight: maxH,
        up: up,
        triggerHeight: box.size.height,
        options: widget.options,
        value: widget.value,
        searchable: widget.searchable,
        onPick: (v) {
          _close();
          widget.onChanged(v);
        },
        onDismiss: _close,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.options.where((o) => o.value == widget.value).firstOrNull;
    final hasError = widget.error != null && widget.error!.isNotEmpty;
    final h = widget.compact ? 36.0 : 42.0;
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.label != null) ...[Text(widget.label!, style: HqText.label), const SizedBox(height: 6)],
          CompositedTransformTarget(
            link: _link,
            child: MouseRegion(
              cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
              child: GestureDetector(
                onTap: _open ? _close : _openPanel,
                child: Opacity(
                  opacity: widget.enabled ? 1 : .5,
                  child: Container(
                    height: h,
                    padding: const EdgeInsets.only(left: 13, right: 12),
                    decoration: BoxDecoration(
                      color: Hq.raised,
                      borderRadius: BorderRadius.circular(widget.compact ? 11 : 12),
                      border: Border.all(color: hasError ? Hq.red : (_open ? Hq.primary : Hq.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selected?.label ?? widget.hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HqText.body.copyWith(
                              fontWeight: FontWeight.w500,
                              color: selected == null ? Hq.faint : Hq.text,
                            ),
                          ),
                        ),
                        ic('chevd', 16, Hq.muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (hasError) Padding(padding: const EdgeInsets.only(top: 5), child: Text(widget.error!, style: HqText.small.copyWith(color: Hq.red))),
        ],
      ),
    );
  }
}

class _SelectPanel<T> extends StatefulWidget {
  const _SelectPanel({
    required this.link,
    required this.width,
    required this.maxHeight,
    required this.up,
    required this.triggerHeight,
    required this.options,
    required this.value,
    required this.searchable,
    required this.onPick,
    required this.onDismiss,
  });

  final LayerLink link;
  final double width;
  final double maxHeight;
  final bool up;
  final double triggerHeight;
  final List<SelectOption<T>> options;
  final T? value;
  final bool searchable;
  final ValueChanged<T> onPick;
  final VoidCallback onDismiss;

  @override
  State<_SelectPanel<T>> createState() => _SelectPanelState<T>();
}

class _SelectPanelState<T> extends State<_SelectPanel<T>> {
  String _q = '';
  int _active = 0;
  final ScrollController _scroll = ScrollController();

  List<SelectOption<T>> get _shown => _q.isEmpty
      ? widget.options
      : widget.options.where((o) => o.label.toLowerCase().contains(_q.toLowerCase())).toList();

  @override
  void initState() {
    super.initState();
    final i = widget.options.indexWhere((o) => o.value == widget.value);
    _active = i < 0 ? 0 : i;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (_active >= shown.length) _active = shown.isEmpty ? 0 : shown.length - 1;
    final listMax = widget.maxHeight - (widget.searchable ? 58 : 12);
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => widget.onDismiss(),
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          targetAnchor: widget.up ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: widget.up ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(0, widget.up ? -6 : 6),
          child: Align(
            alignment: widget.up ? Alignment.bottomLeft : Alignment.topLeft,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
                const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(() {
                      if (shown.isNotEmpty) _active = (_active + 1) % shown.length;
                    }),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () => setState(() {
                      if (shown.isNotEmpty) _active = (_active - 1 + shown.length) % shown.length;
                    }),
                const SingleActivator(LogicalKeyboardKey.enter): () {
                  if (shown.isNotEmpty && !shown[_active].disabled) widget.onPick(shown[_active].value);
                },
              },
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: widget.width,
                  constraints: BoxConstraints(maxHeight: widget.maxHeight),
                  decoration: BoxDecoration(
                    color: Hq.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Hq.border),
                    boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 44, offset: Offset(0, 18))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.searchable)
                        Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Hq.soft))),
                          child: Row(
                            children: [
                              ic('search', 15, Hq.muted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  autofocus: true,
                                  onChanged: (v) => setState(() {
                                    _q = v;
                                    _active = 0;
                                  }),
                                  style: HqText.body.copyWith(fontSize: 14),
                                  decoration: InputDecoration(
                                    isCollapsed: true,
                                    border: InputBorder.none,
                                    hintText: 'Search',
                                    hintStyle: HqText.body.copyWith(fontSize: 14, color: Hq.faint),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: listMax),
                          child: shown.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text('No matches', style: HqText.muted.copyWith(color: Hq.faint)),
                                )
                              : ListView.builder(
                                  controller: _scroll,
                                  padding: const EdgeInsets.all(5),
                                  shrinkWrap: true,
                                  itemCount: shown.length,
                                  itemBuilder: (_, i) {
                                    final o = shown[i];
                                    final sel = o.value == widget.value;
                                    return MouseRegion(
                                      cursor: o.disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
                                      onEnter: (_) => setState(() => _active = i),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: o.disabled ? null : () => widget.onPick(o.value),
                                        child: Opacity(
                                          opacity: o.disabled ? .4 : 1,
                                          child: Container(
                                            constraints: const BoxConstraints(minHeight: 40),
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(
                                              color: i == _active ? Hq.high : Colors.transparent,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    o.label,
                                                    style: HqText.body.copyWith(
                                                      color: sel ? Hq.primary : Hq.text,
                                                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                if (sel) ic('check', 15, Hq.primary),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// `.switch`: on/off toggle.
class HqSwitch extends StatelessWidget {
  const HqSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onChanged == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Opacity(
          opacity: onChanged == null ? .5 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 44,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? Hq.primary : Hq.high,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: value ? Hq.primary : Hq.border),
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: value ? Hq.onPrimary : Hq.muted, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.chk`: the square tick box used in checklists. Tapping the whole row toggles it.
class HqCheckRow extends StatelessWidget {
  const HqCheckRow({super.key, required this.checked, required this.title, this.sub, this.onChanged});

  final bool checked;
  final String title;
  final String? sub;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onChanged == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!checked),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: checked ? Hq.tint(Hq.primary) : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: checked ? Hq.primary : Hq.border, width: 1.5),
                ),
                child: checked ? Center(child: ic('check', 13, Hq.primary)) : null,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: HqText.row),
                    if (sub != null) Text(sub!, style: HqText.small),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A themed date picker. Returns null if dismissed.
Future<DateTime?> pickHqDate(BuildContext context, {DateTime? initial, DateTime? first, DateTime? last}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: first ?? DateTime(2020),
    lastDate: last ?? DateTime(now.year + 5),
    builder: (ctx, child) => Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: const ColorScheme.dark(primary: Hq.primary, onPrimary: Hq.onPrimary, surface: Hq.surface, onSurface: Hq.text),
        dialogTheme: const DialogThemeData(backgroundColor: Hq.surface),
      ),
      child: child!,
    ),
  );
}

/// Scroll behaviour that lets a mouse drag a horizontal scroller (tables, kanban) on desktop web.
class HqScrollBehavior extends MaterialScrollBehavior {
  const HqScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad};
}
