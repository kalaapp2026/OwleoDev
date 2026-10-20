/// The four HQ staff roles and what each can open. This mirrors the `ROLES` table in the prototype
/// and the server's `HqRole` enum; the SERVER is the one that enforces it (a hidden tile is a
/// convenience, not security), the app only uses it to lock tiles and hide write buttons.
enum HqRole {
  super_('SUPER', 'Super admin', 'Full access, including global changes'),
  ops('OPS', 'Operations admin', 'Academies, users, courses, approvals and exits'),
  finance('FINANCE', 'Finance admin', 'Payments, plans, growth and reports'),
  support('SUPPORT', 'Support admin', 'Tickets, enquiries, feedback, user lookups and exits');

  const HqRole(this.code, this.label, this.blurb);
  final String code;
  final String label;
  final String blurb;

  static HqRole byCode(String? code) =>
      HqRole.values.firstWhere((r) => r.code == code, orElse: () => HqRole.super_);
}

class HqUser {
  const HqUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.modules,
  });

  factory HqUser.fromJson(Map<String, dynamic> j) => HqUser(
        id: j['id'] as String,
        username: j['username'] as String? ?? '',
        fullName: j['fullName'] as String? ?? '',
        role: HqRole.byCode(j['hqRole'] as String?),
        modules: ((j['modules'] as List?) ?? const []).cast<String>().toSet(),
      );

  final String id;
  final String username;
  final String fullName;
  final HqRole role;

  /// Module ids the role may open. `*` means all (Super admin).
  final Set<String> modules;

  bool get isSuper => role == HqRole.super_;

  /// Operations and Super admins change things; Finance and Support read and handle their own areas.
  bool get canWrite => role == HqRole.super_ || role == HqRole.ops;

  bool get canExport => role == HqRole.super_ || role == HqRole.ops || role == HqRole.finance;

  bool can(String module) => module == 'welcome' || modules.contains('*') || modules.contains(module);
}
