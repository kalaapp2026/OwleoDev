// ignore_for_file: deprecated_member_use
// getToken/onTokenRefresh are deliberate: firebase_messaging 17's replacement (register +
// onRegistered) yields a Firebase Installation ID, not the FCM registration token the backend's
// HTTP v1 sends use as its `token` target.
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';

/// Push notifications over Firebase Cloud Messaging.
///
/// Android only for now: iOS needs an APNs key and a GoogleService-Info.plist, and web needs a
/// service worker plus a VAPID key. Everywhere else this is a quiet no-op, and every failure is
/// swallowed - push is a convenience layered on the in-app bell, never a reason the app breaks.
///
/// While the app is in the background or closed, Android shows the notification itself (the
/// server sends a `notification` payload), so only the foreground case needs code here.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  DioClient? _client;
  String? _registeredToken;
  bool _initialised = false;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Call once a user is signed in. Safe to call repeatedly (e.g. on every session change).
  Future<void> register(DioClient client) async {
    if (!_supported) return;
    _client = client;
    try {
      if (!_initialised) {
        await Firebase.initializeApp();
        _initialised = true;
        _foregroundSub = FirebaseMessaging.onMessage.listen(_showForeground);
        _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(_send);
      }
      // Android 13+ asks at runtime; below that this resolves granted immediately. A refusal just
      // means no pushes - the in-app bell still works - so there is nothing to retry or nag about.
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _send(token);
    } catch (e) {
      debugPrint('Push registration skipped: $e');
    }
  }

  /// Call BEFORE the server-side logout, while the access token is still valid, so a shared phone
  /// stops receiving the previous person's alerts.
  Future<void> unregister() async {
    final client = _client;
    final token = _registeredToken;
    if (!_supported || client == null || token == null) return;
    try {
      await client.callVoid(
          (dio) => dio.delete('/notifications/push-token', queryParameters: {'token': token}));
    } catch (e) {
      debugPrint('Push unregister skipped: $e');
    }
    _registeredToken = null;
  }

  Future<void> _send(String token) async {
    final client = _client;
    if (client == null) return;
    await client.callVoid((dio) =>
        dio.post('/notifications/push-token', data: {'token': token, 'platform': 'android'}));
    _registeredToken = token;
  }

  void _showForeground(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    AppNotice.messengerKey.currentState?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (n.title != null) Text(n.title!, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (n.body != null) Text(n.body!),
        ],
      ),
    ));
  }

  @visibleForTesting
  Future<void> dispose() async {
    await _refreshSub?.cancel();
    await _foregroundSub?.cancel();
  }
}
