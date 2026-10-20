import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session.dart';

/// (month 'YYYY-MM', day 'YYYY-MM-DD' or null)
typedef OverviewKey = (String, String?);

final collectionsOverviewProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, OverviewKey>((ref, k) {
  return ref.watch(dioClientProvider).getMap('/admin/hq/collections/overview', query: {'month': k.$1, if (k.$2 != null) 'day': k.$2});
});

final billsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(dioClientProvider).getList('/admin/hq/collections/bills'),
);

final offersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(dioClientProvider).getList('/admin/hq/collections/offers'),
);

final addonsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(dioClientProvider).getList('/admin/hq/collections/addons'),
);

final accountProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(dioClientProvider).getMap('/admin/hq/collections/academies/$id'),
);

final billDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(dioClientProvider).getMap('/admin/hq/collections/bills/$id'),
);
