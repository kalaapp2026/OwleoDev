import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/data_freshness.dart';

/// Owns the app's [ProviderScope] so it can be thrown away and rebuilt. Switching account uses
/// this: every cached provider (feeds, course lists, fees...) belongs to the previous user, and
/// invalidating them one by one is how "someone sees data that isn't theirs" bugs happen. A fresh
/// scope boots the session from whichever tokens are active, exactly like a cold start.
class AppRestart extends StatefulWidget {
  const AppRestart({super.key, required this.child});

  final Widget child;

  static _AppRestartState? _current;

  /// Safe to call from anywhere, including mid-build - the rebuild happens after the frame.
  static void restart() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _current?._restart());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  State<AppRestart> createState() => _AppRestartState();
}

class _AppRestartState extends State<AppRestart> {
  Key _scopeKey = UniqueKey();
  var _freshness = DataFreshness();

  @override
  void initState() {
    super.initState();
    AppRestart._current = this;
  }

  @override
  void dispose() {
    if (AppRestart._current == this) AppRestart._current = null;
    super.dispose();
  }

  void _restart() => setState(() {
        _scopeKey = UniqueKey();
        _freshness = DataFreshness();
      });

  @override
  Widget build(BuildContext context) => ProviderScope(
        key: _scopeKey,
        overrides: [dataFreshnessProvider.overrideWithValue(_freshness)],
        observers: [_freshness],
        child: widget.child,
      );
}
