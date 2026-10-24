import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Join" for an online class: opens the batch's Meet / Zoom / Teams link in the browser or the
/// call app, so nobody has to be sent the link on WhatsApp each time.
class JoinClassButton extends StatelessWidget {
  const JoinClassButton({super.key, required this.link});

  final String link;

  static Uri _uri(String link) {
    final v = link.trim();
    return Uri.parse(RegExp(r'^https?://', caseSensitive: false).hasMatch(v) ? v : 'https://$v');
  }

  Future<void> _open(BuildContext context) async {
    var opened = false;
    try {
      opened = await launchUrl(_uri(link), mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) showAppToast(context, 'Could not open the class link.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: palette.primarySoft,
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: palette.primary.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam_outlined, size: 14, color: palette.primary),
          const SizedBox(width: 5),
          Text('Join', style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: palette.primary)),
        ]),
      ),
    );
  }
}
