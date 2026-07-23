import 'user_profile.dart';

enum SessionStatus { bootstrapping, unauthenticated, authenticated }

class SessionState {
  final SessionStatus status;
  final UserProfile? user;

  const SessionState({required this.status, this.user});

  factory SessionState.bootstrapping() => const SessionState(status: SessionStatus.bootstrapping);
  factory SessionState.unauthenticated() => const SessionState(status: SessionStatus.unauthenticated);
  factory SessionState.authenticated(UserProfile user) =>
      SessionState(status: SessionStatus.authenticated, user: user);

  bool get isAuthenticated => status == SessionStatus.authenticated;
  bool get isBootstrapping => status == SessionStatus.bootstrapping;
}
