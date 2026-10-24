import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/network/get_cache_interceptor.dart';

/// Answers every request with `{"n": count}` where count is how many requests have reached the "server", optionally
/// holding the answer back until [gate] opens so tests can overlap requests.
class _FakeServer implements HttpClientAdapter {
  int hits = 0;
  Completer<void>? gate;
  bool failNext = false;
  final seen = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    hits++;
    seen.add('${options.method} ${options.uri}');
    final wait = gate;
    if (wait != null) await wait.future;
    if (failNext) {
      failNext = false;
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString(
      jsonEncode({'n': hits}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  // DioClient reads the token store, which talks to a platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeServer server;
  late GetCacheInterceptor cache;
  late Dio dio;
  var now = DateTime(2026, 1, 1);
  var who = 'token-a';

  setUp(() {
    now = DateTime(2026, 1, 1);
    who = 'token-a';
    server = _FakeServer();
    cache = GetCacheInterceptor(identity: () async => who, ttl: const Duration(seconds: 5), clock: () => now);
    dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = server
      ..interceptors.add(cache);
  });

  group('GET cache', () {
    test('identical requests in flight together share one network call', () async {
      server.gate = Completer<void>();
      final a = dio.get('/events');
      final b = dio.get('/events');
      final c = dio.get('/events');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      server.gate!.complete();
      final results = await Future.wait([a, b, c]);

      expect(server.hits, 1);
      expect(results.map((r) => (r.data as Map)['n']), everyElement(1));
    });

    test('a second request inside the TTL is answered from memory, then goes out again after it', () async {
      await dio.get('/events');
      now = now.add(const Duration(seconds: 4));
      final cached = await dio.get('/events');
      expect(server.hits, 1);
      expect((cached.data as Map)['n'], 1);

      now = now.add(const Duration(seconds: 2)); // 6s after the first answer
      final fresh = await dio.get('/events');
      expect(server.hits, 2);
      expect((fresh.data as Map)['n'], 2);
    });

    test('clear() makes the next request reach the server', () async {
      await dio.get('/events');
      cache.clear();
      await dio.get('/events');
      expect(server.hits, 2);
    });

    test('an answer that was still on its way when a write landed is not kept', () async {
      server.gate = Completer<void>();
      final slow = dio.get('/events');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cache.clear(); // a write succeeded while the GET was running
      server.gate!.complete();
      await slow;

      server.gate = null;
      await dio.get('/events');
      expect(server.hits, 2, reason: 'the pre-write answer must not be served after the write');
    });

    test('different academy, different person, or different query never share an answer', () async {
      await dio.get('/events', options: Options(headers: {'X-Active-Membership': 'm1'}));
      await dio.get('/events', options: Options(headers: {'X-Active-Membership': 'm2'}));
      expect(server.hits, 2);

      who = 'token-b';
      await dio.get('/events', options: Options(headers: {'X-Active-Membership': 'm1'}));
      expect(server.hits, 3);

      await dio.get('/events', queryParameters: {'page': 2});
      expect(server.hits, 4);
    });

    test('writes always go through and are never cached', () async {
      await dio.post('/events', data: {'a': 1});
      await dio.post('/events', data: {'a': 1});
      expect(server.hits, 2);
    });

    test('skip flag bypasses the cache', () async {
      await dio.get('/events');
      await dio.get('/events', options: Options(extra: {GetCacheInterceptor.skip: true}));
      expect(server.hits, 2);
    });

    test('when the shared request fails, the others try for themselves instead of inheriting the error', () async {
      server
        ..gate = Completer<void>()
        ..failNext = true;
      final first = dio.get('/events').then<Object>((r) => r, onError: (Object e) => e);
      final second = dio.get('/events');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      server.gate!.complete();

      expect(await first, isA<DioException>());
      expect(((await second).data as Map)['n'], 2);
      expect(server.hits, 2);
    });
  });

  group('DioClient write signal', () {
    late DioClient client;
    late List<String> signalled;

    setUp(() {
      client = DioClient();
      client.dio.httpClientAdapter = server;
      signalled = [];
      client.mutations.listen(signalled.add);
    });

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    test('a successful write reports its path and empties the cache', () async {
      await client.call((d) => d.get('/students'), (_) => 0);
      expect(client.cache.networkCalls, 1);

      await client.callVoid((d) => d.post('/students', data: {}));
      await settle();
      expect(signalled, ['/students']);

      await client.call((d) => d.get('/students'), (_) => 0);
      expect(client.cache.networkCalls, 2, reason: 'the write cleared the cache');
    });

    test('reads, failed writes and background writes do not signal', () async {
      await client.call((d) => d.get('/students'), (_) => 0);
      await client.callVoid((d) => d.post('/auth/login', data: {}));
      await client.callVoid((d) => d.put('/study-materials/1/playback', data: {}));
      await client.callVoid((d) => d.post('/devices/ping', data: {}));
      server.failNext = true;
      await expectLater(client.callVoid((d) => d.post('/students', data: {})), throwsA(anything));
      await settle();
      expect(signalled, isEmpty);
    });
  });
}
