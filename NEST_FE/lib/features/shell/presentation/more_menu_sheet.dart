import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/features/shell/domain/erp_action.dart';
import 'package:nest_fe/features/shell/presentation/app_shell.dart';

/// The Trainer/Admin "More" action grid (matches the Figma reference: a bottom-sheet grid of
/// every ERP action the caller's role+feature grants allow, plus a trailing Cancel). Visibility
/// per tile is feature-gated the same way the backend gates the endpoint itself - this is a
/// convenience shortcut, not a second source of truth; the backend still enforces every one of
/// these via @RequiresFeature regardless of what the client shows.
Future<void> showMoreMenu(BuildContext context, WidgetRef ref) {
  final user = ref.read(sessionControllerProvider).user;
  if (user == null) return Future.value();

  final visibleItems =
      kErpActions.where((item) => item.visibleFor(user) && (item.route != null || item.erpTabIndex != null)).toList();

  // Must be resolved here, on AppShell's own AppBar context - showModalBottomSheet inserts its
  // content into the root Overlay, so the builder's sheetContext below is NOT a descendant of
  // AppShell's subtree and the ancestor lookup would fail if attempted from inside it.
  final shellState = context.findAncestorStateOfType<AppShellState>();

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(24),
          ),
          child: GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 18,
            crossAxisSpacing: 4,
            childAspectRatio: 0.72,
            children: [
              ...visibleItems.map((item) => _MoreMenuTile(
                    item: item,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      if (item.erpTabIndex != null) {
                        shellState?.goToErpTab(item.erpTabIndex!);
                      } else if (item.route != null) {
                        sheetContext.push(item.route!);
                      }
                    },
                  )),
              _MoreMenuTile(
                item: const ErpAction(icon: Icons.cancel_outlined, label: 'Cancel'),
                isCancel: true,
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _MoreMenuTile extends StatelessWidget {
  const _MoreMenuTile({required this.item, required this.onTap, this.isCancel = false});

  final ErpAction item;
  final VoidCallback onTap;
  final bool isCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isCancel ? colorScheme.error : colorScheme.onSurface.withValues(alpha: 0.85);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(item.icon, color: color, size: 21),
          ),
          const SizedBox(height: 6),
          Text(
            item.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: color, height: 1.15),
          ),
        ],
      ),
    );
  }
}
