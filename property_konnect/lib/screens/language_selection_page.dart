import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'app_settings.dart';

/// Full-screen language chooser shown ONLY on first launch.
/// Saving goes through SettingsController — the single source of
/// truth — so every page updates instantly.
///
/// UPDATED:
///  - ONE picker field (LanguagePickerField, defined in
///    app_settings.dart). Tapping it opens a sheet with the
///    SEARCH BAR inside it and the full list of languages below.
///  - Picking a language now applies it IMMEDIATELY (live preview),
///    so this page changes language the moment you choose.
///    Continue then confirms the choice and shows the HomePage.
class LanguageSelectionPage extends StatefulWidget {
  final SettingsController settings;

  const LanguageSelectionPage({super.key, required this.settings});

  @override
  State<LanguageSelectionPage> createState() =>
      _LanguageSelectionPageState();
}

class _LanguageSelectionPageState extends State<LanguageSelectionPage> {
  String? _selected;

  bool get _isDark => widget.settings.isDark;

  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _mutedText =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  String _tr(String key) => AppLocalizations.tr(context, key);

  /// Called as soon as a language is picked in the sheet.
  Future<void> _onLanguagePicked(String code) async {
    setState(() => _selected = code);
    // Apply right away so this page (and the whole app) switches
    // language instantly. Not yet marked as "chosen".
    await widget.settings.setLanguageCode(code);
    if (mounted) setState(() {});
  }

  Future<void> _confirm() async {
    if (_selected == null) return;

    // 1. Make sure the language is saved in the ONE controller.
    await widget.settings.setLanguageCode(_selected!);
    // 2. Mark the choice so this page never shows again.
    await widget.settings.setLanguageChosen();
    // No navigation needed — main.dart rebuilds and now shows
    // the HomePage because hasChosenLanguage is true.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
      _isDark ? kPageBackgroundDark : kPageBackgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Icon(Icons.language_rounded, size: 64, color: _brand),
                  const SizedBox(height: 18),
                  Text(
                    _tr(AppStrings.chooseLanguage),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: _brand,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tr(AppStrings.chooseLanguageSub),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _mutedText),
                  ),
                  const SizedBox(height: 28),

                  // ---- LANGUAGE PICKER ----
                  LanguagePickerField(
                    selectedCode: _selected,
                    isDark: _isDark,
                    isSwahili: widget.settings.languageCode == 'sw',
                    onChanged: _onLanguagePicked,
                  ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        padding:
                        const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _selected == null ? null : _confirm,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(_tr(AppStrings.continueBtn)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}