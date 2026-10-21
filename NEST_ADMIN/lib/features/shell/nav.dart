import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The prototype keeps a visited-pages stack per side (HQ / Social) so the header's back button
/// returns to where you were, not just "up". go_router's `go` replaces the location without a
/// stack, so the stack lives here.
abstract final class NavHistory {
  static final List<String> hq = [];
  static final List<String> social = [];

  /// The page the business side starts from and goes back to: the dashboard, or Revenue while Finance is open.
  static String home = '/overview';

  static List<String> stackFor(String path) => path.startsWith('/social') ? social : hq;
}

/// Navigate to [path], remembering where we were so [hqBack] can return.
void hqGo(BuildContext context, String path) {
  final current = GoRouterState.of(context).uri.toString();
  if (current != path) {
    final stack = NavHistory.stackFor(current);
    stack.add(current);
    if (stack.length > 30) stack.removeAt(0);
  }
  context.go(path);
}

/// Back to the previous page on this side, or the dashboard when there is none.
void hqBack(BuildContext context) {
  final current = GoRouterState.of(context).uri.path;
  final stack = NavHistory.stackFor(current);
  if (stack.isNotEmpty) {
    context.go(stack.removeLast());
  } else if (current.startsWith('/social')) {
    context.go('/social/post');
  } else {
    context.go(NavHistory.home);
  }
}

bool canGoBack(String path) {
  if (path.startsWith('/social')) return NavHistory.social.isNotEmpty;
  return NavHistory.hq.isNotEmpty || path != NavHistory.home;
}
