import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';

/// How wide the panel should be relative to its trigger.
///
/// A half-width trigger opening a half-width panel truncates every option, which is exactly the
/// case the cascading course/batch selectors hit. [left] and [right] let a narrow trigger open a
/// double-width panel that stays anchored to the edge nearest the screen centre.
enum PanelSpan {
  /// Panel matches the trigger's width.
  trigger,

  /// Panel is wider, aligned to the trigger's left edge. For a trigger in the left column.
  left,

  /// Panel is wider, aligned to the trigger's right edge. For a trigger in the right column.
  right,
}

/// A labelled dropdown trigger whose panel opens anchored *under itself*, rather than as a bottom
/// sheet. Use this where the choice is part of a cascade the user is scanning (month -> course ->
/// batch); use a sheet where the choice is a one-off detour.
///
/// The panel carries an optional search box and an "N options" header, and caps its own height so
/// a 60-batch academy scrolls inside the panel instead of running off the screen.
///
/// **Open state can be controlled.** Pass [isOpen] and [onOpenChanged] and the parent decides who
/// is open, which is the only way to stop two side-by-side selectors from both opening and
/// overlapping each other. Leave them null and it manages itself.
///
/// Deliberately generic over [T] and given a [labelOf] rather than assuming a domain type: the
/// month stepper, course, batch, fee type and sort-order selectors are five different shapes.
class AttachedSelect<T> extends StatefulWidget {
  const AttachedSelect({
    super.key,
    required this.label,
    required this.options,
    required this.labelOf,
    required this.onSelected,
    this.value,
    this.placeholder = 'Select',
    this.locked = false,
    this.enabled = true,
    this.searchable = false,
    this.searchHint = 'Search',
    this.panelSpan = PanelSpan.trigger,
    this.panelWidth,
    this.maxPanelHeight = 232,
    this.isOpen,
    this.onOpenChanged,
    this.optionBuilder,
    this.emptyLabel = 'No options',
    this.trailingAction,
  });

  final String label;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final T? value;
  final String placeholder;

  /// Shows a padlock instead of a chevron and refuses to open. Distinct from [enabled]: locked
  /// means "this is decided for you" (a fee type bound to exactly one batch), not "unavailable".
  final bool locked;

  /// Greyed and inert - the downstream half of a cascade before the upstream choice is made.
  final bool enabled;

  final bool searchable;
  final String searchHint;
  final PanelSpan panelSpan;

  /// Explicit panel width. Overrides [panelSpan]'s own sizing when set.
  final double? panelWidth;

  /// Caps the scrolling area, not the whole panel - the header and search box sit outside it, so
  /// they stay put while the list scrolls under them.
  final double maxPanelHeight;

  /// Controlled open state. Null means self-managed.
  final bool? isOpen;
  final ValueChanged<bool>? onOpenChanged;

  /// Renders a richer row (a fee type's amount, a batch's timing) without this widget needing to
  /// know the option type.
  final Widget Function(BuildContext, T, bool selected)? optionBuilder;

  final String emptyLabel;

  /// A row pinned under the list - the "+ Create fee type" affordance.
  final Widget? trailingAction;

  @override
  State<AttachedSelect<T>> createState() => _AttachedSelectState<T>();
}

class _AttachedSelectState<T> extends State<AttachedSelect<T>> {
  final _link = LayerLink();
  final _controller = OverlayPortalController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  bool _uncontrolledOpen = false;
  bool _searchVisible = false;
  String _query = '';

  bool get _isOpen => widget.isOpen ?? _uncontrolledOpen;

  @override
  void initState() {
    super.initState();
    // The portal stays mounted for the widget's whole life and renders nothing while closed, so
    // opening and closing is a plain rebuild rather than an imperative show()/hide().
    //
    // That indirection is not stylistic. OverlayPortalController asserts if show() or hide() is
    // called during a build, and a controlled parent closing this one necessarily does exactly
    // that - the change arrives in didUpdateWidget, which runs inside the parent's build. Driving
    // the controller from there crashes as soon as two sibling selectors coordinate.
    //
    // Deferred by a frame because initState runs inside a build too. Nothing is visible yet, so
    // the delay costs nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_controller.isShowing) _controller.show();
    });
  }

  @override
  void didUpdateWidget(covariant AttachedSelect<T> old) {
    super.didUpdateWidget(old);
    // A controlled parent can close this while it isn't being touched - when its sibling opens, or
    // when an upstream cascade choice invalidates it. Only the search state needs clearing; the
    // panel itself disappears because _isOpen is now false.
    if (old.isOpen == true && widget.isOpen == false) _resetSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _resetSearch() {
    _searchVisible = false;
    _query = '';
    _searchController.clear();
  }

  void _setOpen(bool open) {
    if (open && (widget.locked || !widget.enabled)) return;
    if (!open) _resetSearch();

    widget.onOpenChanged?.call(open);
    // A controlled parent decides for itself whether that request is honoured, so don't also set
    // local state - that would let the two disagree.
    if (widget.isOpen != null) return;

    setState(() => _uncontrolledOpen = open);
  }

  List<T> get _filtered {
    if (_query.isEmpty) return widget.options;
    final q = _query.toLowerCase();
    return widget.options.where((o) => widget.labelOf(o).toLowerCase().contains(q)).toList();
  }

  double _panelWidth() {
    if (widget.panelWidth != null) return widget.panelWidth!;
    // The trigger's own width, straight off the link that already anchors the panel to it. Read
    // here rather than through a LayoutBuilder deliberately - see build().
    final triggerWidth = _link.leaderSize?.width ?? 0;
    return switch (widget.panelSpan) {
      PanelSpan.trigger => triggerWidth,
      // Double width, so a half-width trigger's options stop truncating. Clamped to the screen so
      // it can't run off the edge on a narrow phone.
      PanelSpan.left || PanelSpan.right => (triggerWidth * 2 + AppSpacing.md)
          .clamp(triggerWidth, MediaQuery.sizeOf(context).width - AppSpacing.x3l),
    };
  }

  @override
  Widget build(BuildContext context) {
    // No LayoutBuilder here, though one would be the obvious way to measure the trigger: its
    // builder runs during layout, which would mean constructing the overlay's whole subtree from
    // inside the layout phase. LayerLink.leaderSize is the same measurement - it comes off the
    // link that already anchors the panel - without that entanglement.
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (overlayContext) =>
          _isOpen ? _buildOverlay(overlayContext) : const SizedBox.shrink(),
      child: CompositedTransformTarget(
        link: _link,
        child: _Trigger(
          label: widget.label,
          text: widget.value == null ? widget.placeholder : widget.labelOf(widget.value as T),
          hasValue: widget.value != null,
          locked: widget.locked,
          enabled: widget.enabled,
          open: _isOpen,
          onTap: () => _setOpen(!_isOpen),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final palette = context.palette;
    final options = _filtered;
    final panelWidth = _panelWidth();

    // Aligning right means the panel's right edge meets the trigger's right edge, so a
    // right-column trigger grows leftward into the screen rather than off it.
    final alignRight = widget.panelSpan == PanelSpan.right;

    return Stack(
      children: [
        // A full-screen catcher so tapping anywhere else closes the panel. Transparent rather than
        // scrimmed: this is a lightweight attached dropdown, and dimming the screen behind it would
        // make it feel like a modal.
        //
        // It absorbs the tap rather than letting it through, which does mean switching straight
        // from one open selector to its neighbour takes two taps - the first dismisses. That is
        // the right trade: a pass-through barrier would let a dismissing tap also activate
        // whatever card happened to be underneath, and every platform's own dropdown behaves this
        // way.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setOpen(false),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: alignRight ? Alignment.bottomRight : Alignment.bottomLeft,
          followerAnchor: alignRight ? Alignment.topRight : Alignment.topLeft,
          offset: const Offset(0, AppSpacing.xs),
          // Opaque so the panel's own padding and header swallow taps. Without it those areas are
          // not hit targets, the tap falls through to the barrier behind, and the panel closes
          // when the user prods a blank part of it.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.dropdown,
              curve: AppMotion.enter,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(offset: Offset(0, (1 - t) * -6), child: child),
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: panelWidth,
                  decoration: BoxDecoration(
                    color: palette.surfaceHigh,
                    borderRadius: AppRadii.all(AppRadii.xl),
                    border: Border.all(color: palette.border),
                    boxShadow: AppShadows.dialog,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PanelHeader(
                        count: options.length,
                        total: widget.options.length,
                        searchable: widget.searchable,
                        searchVisible: _searchVisible,
                        onToggleSearch: () {
                          setState(() {
                            _searchVisible = !_searchVisible;
                            if (!_searchVisible) {
                              _query = '';
                              _searchController.clear();
                            }
                          });
                          if (_searchVisible) _searchFocus.requestFocus();
                        },
                      ),
                      if (_searchVisible)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
                          child: _SearchField(
                            controller: _searchController,
                            focusNode: _searchFocus,
                            hint: widget.searchHint,
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                      if (options.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
                          child: Text(
                            // Distinguishes "nothing matched your search" from "this list is
                            // genuinely empty" - the fixes are different.
                            _query.isEmpty ? widget.emptyLabel : 'No match for "$_query"',
                            style: TextStyle(fontSize: AppType.md, color: palette.textMuted),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: widget.maxPanelHeight),
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                            itemCount: options.length,
                            itemBuilder: (context, i) {
                              final option = options[i];
                              final selected = option == widget.value;
                              return _OptionRow(
                                selected: selected,
                                onTap: () {
                                  widget.onSelected(option);
                                  _setOpen(false);
                                },
                                child: widget.optionBuilder?.call(context, option, selected) ??
                                    Text(
                                      widget.labelOf(option),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: AppType.lg,
                                        fontWeight: selected ? AppType.bold : AppType.regular,
                                        color: selected ? palette.primary : palette.text,
                                      ),
                                    ),
                              );
                            },
                          ),
                        ),
                      if (widget.trailingAction != null) ...[
                        Divider(height: 1, color: palette.border),
                        widget.trailingAction!,
                      ],
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

class _Trigger extends StatelessWidget {
  const _Trigger({
    required this.label,
    required this.text,
    required this.hasValue,
    required this.locked,
    required this.enabled,
    required this.open,
    required this.onTap,
  });

  final String label;
  final String text;
  final bool hasValue;
  final bool locked;
  final bool enabled;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final inert = locked || !enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: AppType.sectionLabel(palette.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        GestureDetector(
          onTap: inert ? null : onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.fade,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: enabled ? palette.surfaceRaised : palette.surface,
              borderRadius: AppRadii.all(AppRadii.lg),
              // The open panel and its trigger read as one object, so the trigger takes the accent
              // border while open.
              border: Border.all(color: open ? palette.primary : palette.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.lg,
                      fontWeight: hasValue ? AppType.semi : AppType.regular,
                      color: !enabled
                          ? palette.textFaint
                          : hasValue
                              ? palette.text
                              : palette.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (locked)
                  Icon(Icons.lock_outline, size: 14, color: palette.textMuted)
                else
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: AppMotion.chevron,
                    curve: AppMotion.enter,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: enabled ? palette.textMuted : palette.textFaint,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.count,
    required this.total,
    required this.searchable,
    required this.searchVisible,
    required this.onToggleSearch,
  });

  final int count;
  final int total;
  final bool searchable;
  final bool searchVisible;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              // Shows the filtered count against the total while searching, so it's obvious the
              // list is narrowed rather than short.
              count == total ? '$total options' : '$count of $total',
              style: AppType.sectionLabel(palette.textMuted),
            ),
          ),
          if (searchable)
            GestureDetector(
              onTap: onToggleSearch,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Icon(
                  searchVisible ? Icons.close_rounded : Icons.search_rounded,
                  size: 16,
                  color: searchVisible ? palette.primary : palette.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      style: TextStyle(fontSize: AppType.md, color: palette.text),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: AppType.md, color: palette.textFaint),
        prefixIcon: Icon(Icons.search_rounded, size: 15, color: palette.textMuted),
        prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        border: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.md),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.md),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.md),
          borderSide: BorderSide(color: palette.primary),
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.child, required this.selected, required this.onTap});

  final Widget child;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? palette.primarySoft : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.md),
        ),
        child: Row(
          children: [
            Expanded(child: child),
            if (selected) Icon(Icons.check_rounded, size: 15, color: palette.primary),
          ],
        ),
      ),
    );
  }
}
