import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/features/auth/data/auth_api.dart';

/// Single shared Dio instance for the whole app - session-scoped (one per app run, not
/// per-request), since it caches interceptor state (the in-flight refresh lock).
final dioClientProvider = Provider<DioClient>((ref) => DioClient());

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(dioClientProvider)));

/// Pure invalidation trigger: watch this (and ignore the value) inside any academy-scoped data
/// provider so switching the active academy (SessionController.switchActiveMembership) refetches
/// it automatically instead of leaving stale data on screen. Only notifies when the id string
/// itself actually changes, not on every unrelated session/profile update.
final activeMembershipIdProvider = Provider<String?>(
  (ref) => ref.watch(sessionControllerProvider.select((s) => s.user?.activeMembershipId)),
);
