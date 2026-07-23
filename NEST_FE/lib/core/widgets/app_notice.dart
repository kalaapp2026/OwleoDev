import 'package:flutter/material.dart';

/// Single place every screen goes through to tell the user something happened - a themed
/// SnackBar for success/error, a themed confirm dialog for anything destructive. Shown via a
/// global ScaffoldMessengerState instead of ScaffoldMessenger.of(context) so callers can fire a
/// notice straight out of an async catch block with no context.mounted juggling.
class AppNotice {
  AppNotice._();

  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static void success(BuildContext context, String message) => _show(context, message, isError: false);

  static void error(BuildContext context, String message) => _show(context, message, isError: true);

  static void _show(BuildContext context, String message, {required bool isError}) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = isError ? colorScheme.errorContainer : colorScheme.primaryContainer;
    final foreground = isError ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer;

    messengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: background,
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: foreground, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(color: foreground))),
          ],
        ),
      ));
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
