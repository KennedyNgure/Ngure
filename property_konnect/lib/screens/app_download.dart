import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================
// APP DOWNLOAD CONFIG
//
// For now: direct APK download. Later, replace with:
//   'https://play.google.com/store/apps/details?id=<your.package>'
// ============================================================
const String kAppDownloadUrl =
    'https://property-konnect-cb4bc.web.app/app-release.apk';

/// Opens the app download link (APK now, Play Store later).
Future<void> openAppDownloadPage() async {
  final uri = Uri.parse(kAppDownloadUrl);
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // URL not reachable yet — that's fine until you host the APK.
    debugPrint('Could not open app download link: $kAppDownloadUrl');
  }
}

/// A slim banner shown on pages opened from shared links, so
/// users without the app installed can get it.
class AppDownloadBanner extends StatelessWidget {
  const AppDownloadBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand = isDark ? const Color(0xFF4CAF7D) : const Color(0xFF1E8E5A);
    final bodyText =
    isDark ? const Color(0xFFE3EAE5) : const Color(0xFF1C2B24);

    final lang = Localizations.localeOf(context).languageCode;
    String tr(String en, String sw) => lang == 'sw' ? sw : en;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: OutlinedButton.icon(
        onPressed: openAppDownloadPage,
        icon: Icon(Icons.android, color: brand),
        label: Text(
          tr(
            'Get the PropertyKonnect app',
            'Pata programu ya PropertyKonnect',
          ),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: brand,
          side: BorderSide(color: brand),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

/// Shows a one-time dialog offering the app download when a
/// shared link is opened on a phone without the app.
Future<void> maybeShowAppDownloadDialog(BuildContext context) async {
  // Only prompt on mobile browsers.
  if (!kIsWeb) return;

  final lang = Localizations.localeOf(context).languageCode;
  String tr(String en, String sw) => lang == 'sw' ? sw : en;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(tr('Using the web version',
          'Unatumia toleo la mtandao')),
      content: Text(
        tr(
          'You can browse everything here in your browser. For the best experience, download the PropertyKonnect app.',
          'Unaweza kuvinjari kila kitu hapa kwenye kivinjari chako. Kwa uzoefu bora zaidi, pakua programu ya PropertyKonnect.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(tr('Not now', 'Si sasa')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E8E5A)),
          onPressed: () {
            Navigator.pop(dialogContext);
            openAppDownloadPage();
          },
          child: Text(tr('Download app', 'Pakua programu')),
        ),
      ],
    ),
  );
}