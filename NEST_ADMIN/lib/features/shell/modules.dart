import '../../app/theme.dart';

/// One console module: its route, its page title, and how it appears in the "More" sheet.
class HqModule {
  const HqModule(this.id, this.title, this.subtitle, this.icon, this.tone, {this.label});

  final String id;
  final String title;
  final String subtitle;
  final String icon;
  final Tone tone;

  /// Short name for the tile / dock when it differs from the page title.
  final String? label;

  String get tileLabel => label ?? title;
  String get path => '/$id';
}

/// Every business-side module. The ids are the same strings the server's [HqRole] uses, so a
/// role's module list can be checked against this directly.
const Map<String, HqModule> hqModules = {
  'overview': HqModule('overview', 'Owleo HQ', 'Everything across all academies', 'dash', Tone.primary, label: 'Dashboard'),
  'collections': HqModule('collections', 'Collections', 'What academy owners pay Owleo: plans, add-ons and commission', 'wallet', Tone.green),
  'academies': HqModule('academies', 'Entities', 'Every academy, imports and exports', 'bld', Tone.primary, label: 'Entities'),
  'onboarding': HqModule('onboarding', 'Onboarding', 'New academies: lead, demo, go-live', 'rocket', Tone.violet),
  'courses': HqModule('courses', 'Courses', 'Batches, trainers and gaps across academies', 'book', Tone.green),
  'providers': HqModule('providers', 'Service providers', 'Photographers, stage, decor, makeup and more, hired by academies', 'users', Tone.blue),
  'events': HqModule('events', 'Events', 'Everything scheduled across Owleo', 'cal', Tone.primary),
  'artists': HqModule('artists', 'Artist verification', 'Check profiles, then allow posting and events', 'shield', Tone.violet),
  'approvals': HqModule('approvals', 'Approvals', 'Requests and the flows that decide them', 'flow', Tone.violet),
  'transfers': HqModule('transfers', 'Academy transfer', 'Handover to a new owner, confirmed by both with an OTP', 'swap', Tone.gold),
  'exits': HqModule('exits', 'Exits', 'Offboarding and access removal', 'exit', Tone.coral),
  'support': HqModule('support', 'Support', 'Tickets, enquiries and feedback', 'msg', Tone.blue),
  'finance': HqModule('finance', 'Finance', 'Where Owleo revenue comes from, month by month', 'rupee', Tone.gold, label: 'Revenue'),
  'payments': HqModule('payments', 'Payments', 'Every payment received, and the account each academy is mapped to', 'bank', Tone.blue),
  'invoicing': HqModule('invoicing', 'Invoicing', 'Monthly bills to academies, sent to their admins', 'file', Tone.gold),
  'notifs': HqModule('notifs', 'Notification templates', 'Design what people are told, and link it to a module', 'bell', Tone.violet),
  'growth': HqModule('growth', 'Growth tracker', 'Users, academies and revenue against our targets', 'trend', Tone.primary, label: 'Growth'),
  'plans': HqModule('plans', 'Plans', 'What each plan includes and what it earns', 'layers', Tone.blue),
  'users': HqModule('users', 'Users', 'Who they are, and every student by academy', 'users', Tone.primary),
  'marketing': HqModule('marketing', 'Marketing', 'Campaigns for academies on Meta and in the app', 'mega', Tone.magenta),
  'reports': HqModule('reports', 'Reports', 'Exports and the audit trail', 'file', Tone.gold),
  'master': HqModule('master', 'Master data', 'Settings shared by every academy', 'gear', Tone.blue),
  'settings': HqModule('settings', 'Platform settings', 'Applies to every user, immediately', 'spark', Tone.blue),
  'alerts': HqModule('alerts', 'Alerts', 'Everything that needs a look today', 'bell', Tone.red),
};

/// The groups in the More sheet, in the prototype's order. `courses` is added to Operations: the
/// prototype's module list includes it but its final tile layout dropped it, which left the
/// course and batch monitor with no way in.
const List<(String, List<String>)> moreGroups = [
  ('Operations', ['onboarding', 'courses', 'providers', 'events', 'artists', 'approvals', 'transfers', 'exits', 'support']),
  ('Business', ['finance', 'collections', 'payments', 'growth', 'plans', 'invoicing']),
  ('Market analysis', ['users', 'marketing', 'reports']),
  ('Platform', ['master', 'settings', 'notifs', 'alerts']),
];

/// The bottom dock on the business side: two tabs left of the logo, one right, then More.
const List<String> dockLeft = ['overview', 'support'];
const List<String> dockRight = ['academies'];

/// The dock while the Finance workspace is open.
const List<String> financeDockLeft = ['finance', 'collections'];
const List<String> financeDockRight = ['invoicing'];

/// The Owleo Social side (HQ's own posting account), which the logo in the dock flips to.
class SocialTab {
  const SocialTab(this.id, this.label, this.icon, this.title, this.subtitle);
  final String id;
  final String label;
  final String icon;
  final String title;
  final String subtitle;
  String get path => '/social/$id';
}

const List<SocialTab> socialTabs = [
  SocialTab('post', 'Post', 'imgplus', 'Owleo Social', 'Posts from HQ and every academy'),
  SocialTab('event', 'Event', 'cal', 'Events', 'Workshops, festivals and competitions on Owleo'),
  SocialTab('search', 'Search', 'search', 'Search', 'Find academies, people, posts and events'),
  SocialTab('profile', 'Profile', 'user', 'Owleo profile', 'How our official page is doing'),
];
