import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/data_sync/data_areas.dart';
import 'package:nest_fe/core/data_freshness.dart';
import 'package:nest_fe/core/providers/core_providers.dart';

/// Keeps what is on screen in step with the server without anyone remembering to refresh.
///
/// Three triggers, all funnelled through [refresh]:
///  * a write succeeds anywhere in the app: the live providers that read the affected area are
///    refetched ([DataAreas] says which). A screen that saves no longer has to know who else
///    shows that data, which is what used to leave the dashboard stale until a hard reload.
///  * the user opens a tab: that tab's providers are refetched if they are older than
///    [tabStaleAfter].
///  * the app returns to the foreground: everything older than [resumeStaleAfter] is refetched.
///
/// Only providers somebody is watching are touched, and only [AsyncValue] ones, so nothing that
/// is not on a screen costs a call, and local state (a form, the theme) is never reset. A
/// refetch keeps the old data on screen until the new data lands, so there is no spinner flash.
class DataSync {
  DataSync({
    required this.container,
    required this.freshness,
    required Stream<String> mutations,
    this.debounce = const Duration(milliseconds: 350),
    this.tabStaleAfter = const Duration(seconds: 20),
    this.resumeStaleAfter = const Duration(seconds: 60),
  }) {
    _subscription = mutations.listen(_onMutation);
  }

  final ProviderContainer container;
  final DataFreshness freshness;
  final Duration debounce;
  final Duration tabStaleAfter;
  final Duration resumeStaleAfter;

  StreamSubscription<String>? _subscription;
  Timer? _timer;
  final _pending = <String>{};

  void _onMutation(String path) {
    _pending.add(DataAreas.segmentOf(path));
    // A save often makes two or three requests back to back; one refresh pass covers them all.
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  void _flush() {
    final segments = _pending.toList();
    _pending.clear();
    final apis = <ProviderBase<Object?>>{};
    for (final segment in segments) {
      final area = DataAreas.forSegment(segment);
      if (area == null) {
        // A write to somewhere not in the map: refetch everything on screen rather than risk
        // leaving something stale.
        refresh();
        return;
      }
      apis.addAll(area);
    }
    refresh(apis: apis);
  }

  /// Refetches live providers. [apis] limits it to providers that read one of those API
  /// providers (null = every live one); [olderThan] skips providers answered more recently.
  /// Returns how many were refetched.
  int refresh({Set<ProviderBase<Object?>>? apis, Duration? olderThan}) {
    final now = DateTime.now();
    final targets = <ProviderBase<Object?>>[];
    for (final element in container.getAllProviderElements()) {
      final provider = element.origin;
      if (provider is! ProviderBase<AsyncValue<Object?>>) continue;
      if (!element.hasListeners) continue;
      if (apis != null && !_reads(element, apis)) continue;
      if (olderThan != null) {
        final at = freshness.lastUpdated(provider);
        if (at != null && now.difference(at) < olderThan) continue;
      }
      targets.add(provider);
    }
    for (final provider in targets) {
      container.invalidate(provider);
    }
    return targets.length;
  }

  bool _reads(ProviderElementBase<Object?> element, Set<ProviderBase<Object?>> apis) {
    var hit = false;
    element.visitAncestors((ancestor) {
      if (apis.contains(ancestor.origin)) hit = true;
    });
    return hit;
  }

  /// The user opened a tab.
  int refreshTab({required bool erp, required int index, required bool isStudent, required bool isSuperAdmin}) =>
      refresh(
        apis: DataAreas.forTab(erp: erp, index: index, isStudent: isStudent, isSuperAdmin: isSuperAdmin),
        olderThan: tabStaleAfter,
      );

  /// The app came back to the foreground.
  int refreshStale() => refresh(olderThan: resumeStaleAfter);

  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
  }
}

final dataSyncProvider = Provider<DataSync>((ref) {
  final sync = DataSync(
    container: ref.container,
    freshness: ref.watch(dataFreshnessProvider),
    mutations: ref.watch(dioClientProvider).mutations,
  );
  ref.onDispose(sync.dispose);
  return sync;
});
