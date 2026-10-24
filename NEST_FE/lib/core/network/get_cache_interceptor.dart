import 'dart:async';

import 'package:dio/dio.dart';

/// Stops the app asking the server the same question twice.
///
/// Several screens read the same endpoint through different providers (the academy's events list
/// is fetched by four of them, a student's courses by three), and a tab switch re-reads whatever
/// was just read. Two things are done about that here, once, instead of in every provider:
///
///  * identical GETs that are in flight at the same moment share one network call, and
///  * a successful answer is reused for [ttl] afterwards.
///
/// Any successful write ([clear], called by DioClient) empties the cache, so a screen that
/// refetches right after a save always reaches the server. A GET that was already on its way when
/// the write finished is not stored, so it cannot put a pre-write answer back.
///
/// A request opts out with `extra: {GetCacheInterceptor.skip: true}`. Only JSON GETs are shared;
/// downloads and anything else pass straight through.
///
/// Must sit before the auth interceptor in the chain: when that one recovers from a 401 it
/// resolves the request itself and later interceptors never hear about it, which would leave
/// callers waiting on a request this one thought was still running.
class GetCacheInterceptor extends Interceptor {
  GetCacheInterceptor({
    required this.identity,
    this.ttl = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// Extra flag that makes a request bypass the cache entirely.
  static const skip = 'nest_skip_cache';

  static const _keyExtra = 'nest_cache_key';
  static const _generationExtra = 'nest_cache_generation';

  /// Who is asking - the access token. Part of the cache key, so one person's answer is never
  /// handed to another when sessions change inside a single app run.
  final Future<String?> Function() identity;
  final Duration ttl;
  final DateTime Function() _now;

  final _fresh = <String, _Entry>{};
  // Completes with the answer, or with null if the request failed: it is never completed with an
  // error, so a failure cannot escape as an unhandled exception from a future nobody awaited.
  final _inFlight = <String, Completer<Response<dynamic>?>>{};
  int _generation = 0;

  /// Calls that actually went to the network, for tests and diagnostics.
  int networkCalls = 0;

  /// Forget everything. Call after any write succeeds.
  void clear() {
    _generation++;
    _fresh.clear();
  }

  bool _shareable(RequestOptions o) =>
      o.method == 'GET' && o.responseType == ResponseType.json && o.extra[skip] != true;

  Future<String> _key(RequestOptions o) async {
    final who = await identity();
    return '$who|${o.headers['X-Active-Membership']}|${o.uri}';
  }

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_shareable(options)) {
      handler.next(options);
      return;
    }
    final key = await _key(options);

    final cached = _fresh[key];
    if (cached != null) {
      if (_now().difference(cached.at) < ttl) {
        handler.resolve(_copy(cached.response, options));
        return;
      }
      _fresh.remove(key);
    }

    final running = _inFlight[key];
    if (running != null) {
      final shared = await running.future;
      if (shared != null) {
        handler.resolve(_copy(shared, options));
      } else {
        // The request this one was riding on failed; make its own attempt rather than inherit
        // someone else's error (it may have been a 401 that the auth interceptor will repair).
        handler.next(options);
      }
      return;
    }

    final completer = Completer<Response<dynamic>?>();
    _inFlight[key] = completer;
    options.extra[_keyExtra] = key;
    options.extra[_generationExtra] = _generation;
    networkCalls++;
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final key = response.requestOptions.extra[_keyExtra] as String?;
    if (key != null) {
      final completer = _inFlight.remove(key);
      if (response.requestOptions.extra[_generationExtra] == _generation) {
        _fresh[key] = _Entry(response, _now());
      }
      if (completer != null && !completer.isCompleted) completer.complete(response);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final key = err.requestOptions.extra[_keyExtra] as String?;
    if (key != null) {
      final completer = _inFlight.remove(key);
      if (completer != null && !completer.isCompleted) completer.complete(null);
    }
    handler.next(err);
  }

  /// Each caller gets its own Response (parsers may keep a reference), sharing the decoded body.
  Response<dynamic> _copy(Response<dynamic> from, RequestOptions to) => Response<dynamic>(
        data: from.data,
        headers: from.headers,
        requestOptions: to,
        statusCode: from.statusCode,
        statusMessage: from.statusMessage,
        isRedirect: from.isRedirect,
        redirects: from.redirects,
        extra: from.extra,
      );
}

class _Entry {
  _Entry(this.response, this.at);
  final Response<dynamic> response;
  final DateTime at;
}
