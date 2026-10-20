import '../../app/theme.dart';

/// How the console colours and names academy types, plans and statuses. One place, so a "Dance"
/// academy is gold on the dashboard, the list and the drawer alike.
abstract final class AcademyMeta {
  static Tone typeTone(String type) => switch (type) {
        'Dance' => Tone.gold,
        'Music' => Tone.primary,
        'Fine Arts' => Tone.violet,
        'Theatre' => Tone.magenta,
        _ => Tone.blue,
      };

  /// The gradient behind an academy's drawer cover, by type.
  static List<int> coverColors(String type) => switch (type) {
        'Dance' => const [0xFF3A2C0B, 0xFF6B4F14, 0xFFB8791A],
        'Music' => const [0xFF0F3D37, 0xFF14544A, 0xFF1B8F7C],
        'Fine Arts' => const [0xFF241C3D, 0xFF3C2E63, 0xFF7D63C9],
        'Theatre' => const [0xFF351327, 0xFF5E1F45, 0xFFC24A82],
        _ => const [0xFF0A0F1C, 0xFF141E33, 0xFF24365C],
      };

  static (Tone, String) status(String status) => switch (status) {
        'live' => (Tone.green, 'Live'),
        'trial' => (Tone.blue, 'Demo'),
        'pastdue' => (Tone.red, 'Payment due'),
        'suspended' => (Tone.coral, 'Suspended'),
        _ => (Tone.mute, 'Churned'),
      };

  static const academyTypes = ['Dance', 'Music', 'Fine Arts', 'Theatre', 'Multi'];
}
