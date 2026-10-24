import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When each live provider last received an answer. Lets "refresh what is stale" skip data that
/// was fetched a moment ago instead of asking the server again.
///
/// Registered as an observer by the ProviderScope that owns the app (see AppRestart) and handed
/// to the rest of the app through [dataFreshnessProvider].
class DataFreshness extends ProviderObserver {
  final _at = <ProviderBase<Object?>, DateTime>{};

  DateTime? lastUpdated(ProviderBase<Object?> provider) => _at[provider];

  @override
  void didAddProvider(ProviderBase<Object?> provider, Object? value, ProviderContainer container) {
    if (!(value is AsyncValue && value.isLoading)) _at[provider] = DateTime.now();
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    // A refresh passes through "loading" first; the clock restarts when the answer arrives.
    if (newValue is AsyncValue && newValue.isLoading) return;
    _at[provider] = DateTime.now();
  }

  @override
  void didDisposeProvider(ProviderBase<Object?> provider, ProviderContainer container) {
    _at.remove(provider);
  }
}

/// Overridden with the live observer by AppRestart; the default is an empty one so a scope built
/// without it (a test) simply treats everything as stale.
final dataFreshnessProvider = Provider<DataFreshness>((ref) => DataFreshness());
