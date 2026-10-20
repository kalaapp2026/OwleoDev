import 'package:url_launcher/url_launcher.dart';

/// Opens a web link in a new tab. Only http and https are ever opened.
Future<void> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
