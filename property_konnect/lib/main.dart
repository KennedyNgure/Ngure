import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'l10n/catalogs.g.dart' as gen;

import 'screens/admin_dashboard.dart';
import 'screens/app_download.dart';
import 'screens/app_settings.dart';
import 'screens/homepage.dart';
import 'screens/language_selection_page.dart';
import 'screens/password_reset_link_handler.dart';

// PropertyDeepLink / PropertyMediaPage / PropertyDetailsPage live here.
import 'screens/property_details_page.dart';

final GlobalKey<NavigatorState> appNavigatorKey =
GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Load saved language, theme, and text-size preferences.
  final settings = SettingsController();
  await settings.load();

  // Load translations for the saved language before displaying the UI.
  await gen.AppCatalogs.load(settings.languageCode);

  runApp(PropertyKonnectApp(settings: settings));

  // Start listening for password-reset email links after startup.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await PasswordResetLinkHandler.instance.start(
        appNavigatorKey,
      );
    } catch (e) {
      debugPrint('Password-reset link setup failed: $e');
    }
  });
}

class PropertyKonnectApp extends StatelessWidget {
  const PropertyKonnectApp({
    super.key,
    required this.settings,
  });

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AppSettings(
      controller: settings,
      child: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          return MaterialApp(
            navigatorKey: appNavigatorKey,
            title: 'Property Konnect',
            debugShowCheckedModeBanner: false,

            locale: settings.locale,
            supportedLocales: KenyaLanguages.supportedLocales,
            localizationsDelegates:
            KenyaLanguages.localizationsDelegates,

            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,

            routes: {
              '/home': (context) => const HomePage(),
              '/admin': (context) => const AdminDashboardPage(),
            },

            // Shared links (?property=ID / ?media=ID) take priority,
            // including over the language-selection page.
            home: _DeepLinkOrHome(
              linkWidget: PropertyDeepLink.widgetFor(Uri.base),
              settings: settings,
            ),
          );
        },
      ),
    );
  }
}

/// Shows the app-download dialog once when someone arrives via a
/// shared link on a device without the app, then the linked page.
class _DeepLinkOrHome extends StatefulWidget {
  final Widget? linkWidget;
  final SettingsController settings;

  const _DeepLinkOrHome({
    required this.linkWidget,
    required this.settings,
  });

  @override
  State<_DeepLinkOrHome> createState() => _DeepLinkOrHomeState();
}

class _DeepLinkOrHomeState extends State<_DeepLinkOrHome> {
  bool _promptShown = false;

  @override
  Widget build(BuildContext context) {
    final link = widget.linkWidget;

    if (link != null) {
      if (!_promptShown) {
        _promptShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) maybeShowAppDownloadDialog(context);
        });
      }
      return link;
    }

    return widget.settings.hasChosenLanguage
        ? const HomePage()
        : LanguageSelectionPage(settings: widget.settings);
  }
}