import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/data_sync/data_areas.dart';
import 'package:nest_fe/app/data_sync/data_sync.dart';
import 'package:nest_fe/core/data_freshness.dart';
import 'package:nest_fe/features/fees/data/fees_api.dart';
import 'package:nest_fe/features/social/presentation/feed_screen.dart';

// Stand-ins for real data providers: each one watches a real API provider, exactly as the app's
// providers do, and counts how often it was fetched.
var _feeFetches = 0;
var _feedFetches = 0;
final _feeReader = FutureProvider.autoDispose<int>((ref) {
  ref.watch(feesApiProvider);
  return ++_feeFetches;
});
final _feedReader = FutureProvider.autoDispose<int>((ref) {
  ref.watch(socialApiProvider);
  return ++_feedFetches;
});
final _feeCounterState = StateProvider.autoDispose<int>((ref) {
  ref.watch(feesApiProvider);
  return 0;
});

void main() {
  late ProviderContainer container;
  late DataFreshness freshness;
  late StreamController<String> writes;
  late DataSync sync;

  setUp(() {
    _feeFetches = 0;
    _feedFetches = 0;
    freshness = DataFreshness();
    container = ProviderContainer(observers: [freshness]);
    writes = StreamController<String>.broadcast();
    sync = DataSync(
      container: container,
      freshness: freshness,
      mutations: writes.stream,
      debounce: const Duration(milliseconds: 10),
    );
    // "On screen": something is listening to each.
    container.listen(_feeReader, (_, _) {}, fireImmediately: true);
    container.listen(_feedReader, (_, _) {}, fireImmediately: true);
    container.listen(_feeCounterState, (_, _) {}, fireImmediately: true);
  });

  tearDown(() {
    sync.dispose();
    writes.close();
    container.dispose();
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

  test('a write refetches the providers that read its area, and only those', () async {
    await settle();
    expect([_feeFetches, _feedFetches], [1, 1]);

    writes.add('/fees/abc/collect');
    await settle();

    expect(_feeFetches, 2, reason: 'fees data read the fees area');
    expect(_feedFetches, 1, reason: 'the social feed does not');
  });

  test('a burst of writes is one refresh pass', () async {
    await settle();
    writes
      ..add('/fees/a')
      ..add('/fees/b')
      ..add('/fees/c');
    await settle();
    expect(_feeFetches, 2);
  });

  test('a write to an area nobody mapped refreshes everything on screen', () async {
    await settle();
    writes.add('/something-new/1');
    await settle();
    expect([_feeFetches, _feedFetches], [2, 2]);
  });

  test('only async data providers are touched, never plain state', () async {
    await settle();
    container.read(_feeCounterState.notifier).state = 7;
    writes.add('/fees/abc');
    await settle();
    expect(container.read(_feeCounterState), 7, reason: 'local state must not be reset by a refresh');
  });

  test('a provider nobody is watching is not fetched', () async {
    final unwatched = FutureProvider.autoDispose<int>((ref) {
      ref.watch(feesApiProvider);
      return 99;
    });
    // never listened to
    await settle();
    expect(sync.refresh(apis: DataAreas.forSegment('fees')), 1); // only _feeReader (+ the state provider is skipped)
    expect(container.exists(unwatched), isFalse);
  });

  test('refreshing by age skips what was answered a moment ago', () async {
    await settle();
    expect(sync.refresh(olderThan: const Duration(minutes: 1)), 0);
    await settle();
    expect(_feeFetches, 1);

    expect(sync.refresh(olderThan: Duration.zero), 2);
    await settle();
    expect([_feeFetches, _feedFetches], [2, 2]);
  });

  test('opening a tab refreshes that tab\'s data, not the others', () async {
    await settle();
    // ERP index 3 is Fees for staff: reads the fees API, not social.
    expect(sync.refreshTab(erp: true, index: 3, isStudent: false, isSuperAdmin: false), 0, reason: 'still fresh');

    final stale = DataSync(
      container: container,
      freshness: freshness,
      mutations: const Stream.empty(),
      tabStaleAfter: Duration.zero,
    );
    expect(stale.refreshTab(erp: true, index: 3, isStudent: false, isSuperAdmin: false), 1);
    await settle();
    expect([_feeFetches, _feedFetches], [2, 1]);
    stale.dispose();
  });

  test('every segment the app really writes to is mapped, so nothing silently falls back', () {
    const known = [
      'students', 'trainers', 'users', 'existing-accounts', 'batches', 'courses', 'class-instances', 'schedule',
      'schedules', 'calendar', 'fees', 'study-materials', 'material-playlists', 'academies', 'events', 'interests',
      'posts', 'feed', 'notifications', 'artist-applications', 'me', 'admin', 'platform',
    ];
    for (final s in known) {
      expect(DataAreas.forSegment(s), isNotNull, reason: s);
    }
    expect(DataAreas.segmentOf('/students/3f2/statement?x=1'), 'students');
    expect(DataAreas.segmentOf(''), '');
  });
}
