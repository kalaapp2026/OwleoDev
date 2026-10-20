import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../api/api_exception.dart';
import 'primitives.dart';

/// Renders the three states of a provider the same way everywhere: a spinner while loading, the
/// server's own message with a retry on failure, and [data] on success.
Widget asyncBody<T>(AsyncValue<T> value, {required Widget Function(T data) data, VoidCallback? onRetry}) {
  return value.when(
    skipLoadingOnRefresh: true,
    loading: () => const HqLoading(),
    error: (e, _) => HqError(e is ApiException ? e.message : 'Something went wrong loading this.', onRetry: onRetry),
    data: data,
  );
}
