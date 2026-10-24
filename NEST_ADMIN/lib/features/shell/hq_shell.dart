import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth/hq_access.dart';
import '../../core/auth/session.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../onboarding/add_academy_page.dart';
import '../onboarding/add_pre_lead_page.dart';
import 'logo_flip.dart';
import 'modules.dart';
import 'nav.dart';
import 'shell_data.dart';
import 'workspace.dart';

/// The frame around every page: the brand header, the floating dock with the HQ/Social logo in
/// the middle, and the "More" sheet. Pages are plain column content; this scrolls them.
class HqShell extends ConsumerStatefulWidget {
  const HqShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<HqShell> createState() => _HqShellState();
}

class _HqShellState extends ConsumerState<HqShell> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _logoKey = GlobalKey();
  bool _more = false;
  bool _bell = false;
  // The alerts popover lives in the app overlay so nothing on the page can paint over it.
  final _bellLink = LayerLink();
  final _bellPortal = OverlayPortalController();
  bool _flipping = false;

  bool get _social => widget.location.startsWith('/social');

  @override
  void didUpdateWidget(HqShell old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location) {
      _more = false;
      _bell = false;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  ({String title, String subtitle}) get _titles {
    if (_social) {
      final t = socialTabs.firstWhere((t) => widget.location.startsWith(t.path), orElse: () => socialTabs.first);
      return (title: t.title, subtitle: t.subtitle);
    }
    final id = Uri.parse(widget.location).path.split('/').where((s) => s.isNotEmpty).firstOrNull ?? 'overview';
    final m = hqModules[id] ?? hqModules['overview']!;
    if (id == 'overview') {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final n = DateTime.now();
      return (title: m.title, subtitle: 'Everything across all academies, as of ${n.day} ${months[n.month - 1]} ${n.year}');
    }
    return (title: m.title, subtitle: m.subtitle);
  }

  void _flip() {
    if (_flipping) return;
    final box = _logoKey.currentContext?.findRenderObject() as RenderBox?;
    final toSocial = !_social;
    void swap() => context.go(toSocial ? '/social/post' : '/overview');
    setState(() {
      _more = false;
      _bell = false;
    });
    if (box == null || MediaQuery.of(context).disableAnimations) {
      swap();
      return;
    }
    final rect = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _flipping = true);
    playLogoFlip(context, from: rect, toSocial: toSocial, swap: swap);
    Future.delayed(const Duration(milliseconds: 2450), () {
      if (mounted) setState(() => _flipping = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user;
    if (user == null) return const SizedBox.shrink();
    final t = _titles;
    final alerts = ref.watch(alertsProvider);
    final alertCount = alerts.valueOrNull?.length ?? 0;
    final finance = ref.watch(workspaceProvider);
    final onOnboarding = widget.location.startsWith('/onboarding');
    Future<void> signOut() async {
      final ok = await confirmHq(context, title: 'Sign out?', body: 'You will need to sign in again to use the console.', confirmLabel: 'Sign out');
      if (ok) await ref.read(sessionProvider.notifier).logout();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_bell && !_bellPortal.isShowing) _bellPortal.show();
      if (!_bell && _bellPortal.isShowing) _bellPortal.hide();
    });

    return Scaffold(
      backgroundColor: Hq.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_bell) setState(() => _bell = false);
            },
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.only(top: 16, bottom: 150),
              child: PageBody(
                children: [
                  _Header(
                    title: t.title,
                    subtitle: t.subtitle,
                    social: _social,
                    showBack: canGoBack(widget.location),
                    showBell: !_social && !finance,
                    alertCount: alertCount,
                    bellOpen: _bell,
                    onLogout: signOut,
                    bellLink: _bellLink,
                    bellPortal: _bellPortal,
                    onBell: () => setState(() => _bell = !_bell),
                    action: onOnboarding && user.canWrite
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            // On a narrow screen there is only room for one; the pipeline has its own Add buttons.
                            if (MediaQuery.sizeOf(context).width >= 700) ...[
                              HqButton('Add pre-lead', icon: 'plus', onPressed: () => showAddPreLead(context, ref)),
                              const SizedBox(width: 8),
                            ],
                            HqButton('Add lead', icon: 'plus', kind: BtnKind.primary, onPressed: () => showAddAcademy(context, ref)),
                          ])
                        : null,
                    alerts: alerts.valueOrNull ?? const [],
                    onOpenAlert: (a) {
                      setState(() => _bell = false);
                      hqGo(context, a.academyId != null ? '/academies?open=${a.academyId}' : '/alerts');
                    },
                    onAllAlerts: () {
                      setState(() => _bell = false);
                      hqGo(context, '/alerts');
                    },
                  ),
                  const SizedBox(height: 18),
                  widget.child,
                ],
              ),
            ),
          ),
          if (_more && !_social) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _more = false),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: const ColoredBox(color: Color(0x8004070E)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 112,
              child: Center(child: _MoreSheet(finance: finance, onSwitch: () { setState(() => _more = false); finance ? backToOperations(context, ref) : showOpenFinance(context, ref); }, user: user, onPick: (id) => hqGo(context, '/$id'), onClose: () => setState(() => _more = false), onSignOut: signOut)),
            ),
          ],
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: _Dock(
              social: _social,
              finance: finance,
              location: widget.location,
              moreOpen: _more,
              logoKey: _logoKey,
              hideLogo: _flipping,
              user: user,
              onFlip: _flip,
              onMore: () => setState(() {
                _more = !_more;
                _bell = false;
              }),
              onTab: (path) => hqGo(context, path),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.social,
    required this.showBack,
    required this.showBell,
    required this.alertCount,
    required this.bellOpen,
    required this.onLogout,
    required this.bellLink,
    required this.bellPortal,
    required this.onBell,
    required this.action,
    required this.alerts,
    required this.onOpenAlert,
    required this.onAllAlerts,
  });

  final String title, subtitle;
  final bool social, showBack, showBell, bellOpen;
  final LayerLink bellLink;
  final OverlayPortalController bellPortal;
  final int alertCount;
  final VoidCallback onBell, onAllAlerts, onLogout;
  final Widget? action;
  final List<HqAlert> alerts;
  final ValueChanged<HqAlert> onOpenAlert;

  @override
  Widget build(BuildContext context) {
    final ring = ringColor(social: social);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          children: [
            if (showBack) ...[HqIconButton('back', size: 40, onTap: () => hqBack(context)), const SizedBox(width: 12)],
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: ring, width: 2),
                color: Hq.bg,
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(logoAsset(social: social), fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.h1),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.muted),
                ],
              ),
            ),
            if (showBell) ...[
              const SizedBox(width: 12),
              CompositedTransformTarget(link: bellLink, child: HqIconButton('bell', badge: alertCount, onTap: onBell, tooltip: 'Alerts')),
            ],
            if (action != null) ...[const SizedBox(width: 12), action!],
            const SizedBox(width: 10),
            HqIconButton('exit', tooltip: 'Sign out', onTap: onLogout),
          ],
        ),
        OverlayPortal(
          controller: bellPortal,
          overlayChildBuilder: (_) => Align(
            alignment: Alignment.topLeft,
            child: CompositedTransformFollower(
              link: bellLink,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 8),
              showWhenUnlinked: false,
              child: Material(type: MaterialType.transparency, child: Container(
              width: 360,
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 32),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Hq.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Hq.border),
                boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 36, offset: Offset(0, 16))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Text('Alerts', style: HqText.h3.copyWith(fontSize: 15)),
                    const SizedBox(width: 8),
                    Text('$alertCount open', style: HqText.small.copyWith(color: Hq.faint)),
                  ]),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .6),
                    child: SingleChildScrollView(
                      child: alerts.isEmpty
                          ? const EmptyNote('Nothing needs a look right now.')
                          : HqList([
                              for (final a in alerts.take(6))
                                HqRow(
                                  leading: IconTile(a.icon, tone: Tone.byName(a.tone), size: 30, iconSize: 15),
                                  title: a.title,
                                  sub: a.text,
                                  wrap: true,
                                  onTap: () => onOpenAlert(a),
                                ),
                            ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  HqButton('See all alerts', small: true, expand: true, onPressed: onAllAlerts),
                ],
              ),
            )),
            ),
          ),
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _Dock extends ConsumerWidget {
  const _Dock({
    required this.social,
    required this.finance,
    required this.location,
    required this.moreOpen,
    required this.logoKey,
    required this.hideLogo,
    required this.user,
    required this.onFlip,
    required this.onMore,
    required this.onTab,
  });

  final bool social, finance, moreOpen, hideLogo;
  final String location;
  final GlobalKey logoKey;
  final HqUser user;
  final VoidCallback onFlip, onMore;
  final ValueChanged<String> onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(badgesProvider).valueOrNull ?? const <String, int>{};
    final ring = ringColor(social: social);

    List<_TabSpec> left, right;
    if (social) {
      left = [for (final t in socialTabs.take(2)) _TabSpec(t.path, t.label, t.icon, 0)];
      right = [for (final t in socialTabs.skip(2)) _TabSpec(t.path, t.label, t.icon, 0)];
    } else {
      _TabSpec spec(String id) => _TabSpec(hqModules[id]!.path, hqModules[id]!.tileLabel, hqModules[id]!.icon, badges[id] ?? 0);
      left = (finance ? financeDockLeft : dockLeft).map(spec).toList();
      right = (finance ? financeDockRight : dockRight).map(spec).toList();
    }
    final inMore = !social &&
        ![...(finance ? financeDockLeft : dockLeft), ...(finance ? financeDockRight : dockRight)].any((id) => location.startsWith('/$id'));

    Widget tab(_TabSpec s, {bool active = false, bool expanded = false}) => Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTab(s.path),
              child: _TabButton(icon: s.icon, label: s.label, active: active, badge: s.badge),
            ),
          ),
        );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                decoration: BoxDecoration(
                  color: Hq.surface,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Hq.soft),
                  boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 34, offset: Offset(0, 14))],
                ),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Row(children: [for (final s in left) tab(s, active: location.startsWith(s.path))])),
                    const SizedBox(width: 62),
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          for (final s in right) tab(s, active: location.startsWith(s.path)),
                          if (!social)
                            Expanded(
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: onMore,
                                  child: _TabButton(icon: 'grid', label: 'More', active: moreOpen || inMore, rotate: moreOpen),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -18,
                child: Opacity(
                  opacity: hideLogo ? 0 : 1,
                  child: _LogoButton(key: logoKey, social: social, ring: ring, onTap: onFlip),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.path, this.label, this.icon, this.badge);
  final String path, label, icon;
  final int badge;
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.icon, required this.label, required this.active, this.badge = 0, this.rotate = false});

  final String icon, label;
  final bool active, rotate;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = active ? Hq.primary : Hq.faint;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedRotation(turns: rotate ? .25 : 0, duration: const Duration(milliseconds: 200), child: ic(icon, 19, color)),
              if (badge > 0)
                Positioned(
                  top: -4,
                  right: -12,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: Hq.red, borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.center,
                    child: Text('$badge', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white, height: 1.1)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, style: TextStyle(fontSize: 10, color: color, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}

/// The raised owl in the middle of the dock. A soft halo pulses behind it; tapping flips the side.
class _LogoButton extends StatefulWidget {
  const _LogoButton({super.key, required this.social, required this.ring, required this.onTap});
  final bool social;
  final Color ring;
  final VoidCallback onTap;

  @override
  State<_LogoButton> createState() => _LogoButtonState();
}

class _LogoButtonState extends State<_LogoButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  bool _down = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: SizedBox(
          width: 62,
          height: 62,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (!reduce)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, _) {
                    final t = Curves.easeOut.transform((_pulse.value / .7).clamp(0.0, 1.0));
                    final scale = .9 + (1.55 - .9) * t;
                    final op = _pulse.value > .7 ? 0.0 : .55 * (1 - t);
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [widget.ring.withValues(alpha: .19 * op / .55), Colors.transparent], stops: const [0, .68]),
                        ),
                      ),
                    );
                  },
                ),
              AnimatedScale(
                scale: _down ? .92 : 1,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Hq.bg,
                    border: Border.all(color: widget.ring, width: 2),
                    boxShadow: [
                      const BoxShadow(color: Hq.bg, spreadRadius: 5),
                      BoxShadow(color: widget.ring.withValues(alpha: .33), blurRadius: 20, offset: const Offset(0, 6)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(logoAsset(social: widget.social), fit: BoxFit.cover),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreSheet extends ConsumerWidget {
  const _MoreSheet({required this.finance, required this.onSwitch, required this.user, required this.onPick, required this.onClose, required this.onSignOut});

  final bool finance;
  final VoidCallback onSwitch;
  final HqUser user;
  final ValueChanged<String> onPick;
  final VoidCallback onClose, onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(badgesProvider).valueOrNull ?? const <String, int>{};
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      width: (w - 24).clamp(0.0, 536.0),
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 150),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
      decoration: BoxDecoration(
        color: Hq.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Hq.border),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 20))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: 'More', style: HqText.h3.copyWith(fontSize: 13.5)),
                  TextSpan(text: '  ·  ${user.role.label}', style: HqText.small.copyWith(color: Hq.faint, fontWeight: FontWeight.w600)),
                ])),
              ),
              HqIconButton('x', size: 28, onTap: onClose),
            ],
          ),
          const SizedBox(height: 14),
          HqCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            margin: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              IconTile(finance ? 'wallet' : 'bld', tone: finance ? Tone.gold : Tone.primary, size: 36, iconSize: 17),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(finance ? 'Finance' : 'Business operations', style: HqText.row.copyWith(fontSize: 13.5)),
                  Text(finance ? 'Business operations are hidden while Finance is open' : 'Revenue and billing are hidden while you work here', style: HqText.small.copyWith(fontSize: 11.5)),
                ]),
              ),
              if (finance || user.can('finance')) HqButton(finance ? 'Back to operations' : 'Open Finance', small: true, onPressed: onSwitch),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (g, group) in [for (final grp in moreGroups) (grp.$1, [for (final id in grp.$2) if (workspaceAllows(id, finance: finance)) id])].where((x) => x.$2.isNotEmpty).indexed) ...[
                    SectionLabel(group.$1, top: g == 0 ? 0 : 16),
                    LayoutBuilder(
                      builder: (_, c) {
                        const cols = 4;
                        const gap = 12.0;
                        final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final id in group.$2)
                              SizedBox(
                                width: tileW,
                                child: _MoreTile(
                                  module: hqModules[id]!,
                                  allowed: user.can(id),
                                  count: badges[id] ?? 0,
                                  onTap: () => onPick(id),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Hq.border),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text('Signed in as ${user.fullName.isEmpty ? user.username : user.fullName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small)),
            HqButton('Sign out', icon: 'exit', small: true, onPressed: onSignOut),
          ]),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.module, required this.allowed, required this.count, required this.onTap});

  final HqModule module;
  final bool allowed;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = module.tone;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: allowed ? 1 : .45,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: tone.soft,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: tone.color.withValues(alpha: .28)),
                      ),
                      child: Center(child: ic(allowed ? module.icon : 'lock', 19, tone.color)),
                    ),
                    if (allowed && count > 0)
                      Positioned(
                        top: -5,
                        right: -6,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 17),
                          height: 17,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(color: Hq.red, borderRadius: BorderRadius.circular(9)),
                          alignment: Alignment.center,
                          child: Text('$count', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(module.tileLabel,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Hq.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
