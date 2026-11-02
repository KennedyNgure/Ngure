import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

/// GENERATED-STYLE CATALOG — RUNTIME JSON EDITION
///
/// This file contains no hardcoded translations. It loads every
/// language from its JSON file in `lib/l10n/` at runtime, e.g.
/// `lib/l10n/strings_en.json`, `lib/l10n/strings_sw.json`.
///
/// For each language code it tries these file names, in order:
///   1. lib/l10n/strings_<code>.json
///   2. lib/l10n/<code>.json
///
/// ── ONE-TIME SETUP (2 steps) ─────────────────────────────────────
///
/// 1. Declare the JSON folder as a Flutter asset in `pubspec.yaml`:
///
///    flutter:
///      assets:
///        - lib/l10n/
///
///    (Files inside `lib/` are only readable at runtime if they are
///    declared as assets. Run `flutter clean` after editing pubspec.)
///
/// 2. Preload catalogs BEFORE the first frame, in `main.dart`:
///
///    Future<void> main() async {
///      WidgetsFlutterBinding.ensureInitialized();
///      final settings = SettingsController();       // your controller
///      await settings.loadSettings();
///      await AppCatalogs.load(settings.languageCode);   // <-- add this
///      runApp(...);
///    }
///
///    And in `SettingsController.setLanguageCode(...)` add:
///
///      await AppCatalogs.load(code);
///
///    so the new language is ready the moment the user picks it.
/// ─────────────────────────────────────────────────────────────────

class AppCatalogs {
  AppCatalogs._();

  /// Folder that contains the JSON files, as declared in pubspec.
  static const String _assetDir = 'lib/l10n';

  /// File name prefix used by your catalog files (strings_en.json).
  static const String _filePrefix = 'strings_';

  /// Fallback language when a key or a whole file is missing.
  static const String fallbackCode = 'en';

  /// Codes whose app-side name differs from the JSON filename.
  /// `AppLanguages` uses 'tl' for Filipino but the file is 'fil'.
  static const Map<String, String> _aliases = {
    'tl': 'fil', // Filipino
    'fil-ph': 'fil',
    'zh': 'zh-CN', // adjust if your file is named differently
  };

  /// code -> (key -> translated string)
  static final Map<String, Map<String, String>> _cache = {};

  /// In-flight loads so the same language is never fetched twice.
  static final Map<String, Future<void>> _pending = {};

  /// Resolve an app language code to the JSON filename code.
  static String resolveCode(String code) {
    final lower = code.toLowerCase();
    return _aliases[lower] ??
        _aliases[lower.split('-').first] ??
        lower;
  }

  /// Ensure a language (and the fallback) are in memory.
  /// Safe to call repeatedly; only loads missing files.
  static Future<void> load(String code) async {
    final resolved = resolveCode(code);
    await _loadOne(resolved);
    if (resolved != fallbackCode) {
      await _loadOne(fallbackCode);
    }
  }

  /// Candidate asset paths for a language code, most specific first.
  static List<String> _candidatePaths(String code) => [
    '$_assetDir/$_filePrefix$code.json',
    '$_assetDir/$code.json',
  ];

  static Future<void> _loadOne(String code) {
    return _pending.putIfAbsent(code, () async {
      for (final path in _candidatePaths(code)) {
        try {
          final raw = await rootBundle.loadString(path);
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            _cache[code] =
                decoded.map((k, v) => MapEntry(k, v.toString()));
            return; // loaded successfully, stop trying other paths
          }
        } catch (_) {
          // Try the next candidate path.
        }
      }
      // Nothing found: leave cache empty; tr() falls back to the
      // fallback language, then to the key itself.
      debugPrint('AppCatalogs: no catalog file found for "$code". '
          'Tried: ${_candidatePaths(code).join(', ')}');
    });
  }

  /// Is there a real JSON file loaded for this code?
  static bool isLoaded(String code) =>
      _cache.containsKey(resolveCode(code));

  /// Look up [key] for [code], with fallback chain:
  /// exact language -> fallback language -> key itself.
  static String tr(String code, String key) {
    final map = _cache[resolveCode(code)];
    final hit = map?[key];
    if (hit != null && hit.isNotEmpty) return hit;

    final fb = _cache[fallbackCode];
    final fallbackHit = fb?[key];
    if (fallbackHit != null && fallbackHit.isNotEmpty) return fallbackHit;

    return key; // last resort: show the key, never a wrong-language string
  }

  /// All languages currently available (files loaded successfully).
  static Iterable<String> get loadedCodes => _cache.keys;

  /// For pages that still carry inline _tr('English', 'Kiswahili') pairs:
  /// translates using the ENGLISH TEXT as the key.
  ///   * 'en' -> returns the English text as-is.
  ///   * Any other language:
  ///       1. looks the English text up directly in that catalog
  ///          (English-text-keyed entries),
  ///       2. then reverse-maps the English text to a key via the
  ///          fallback catalog and looks THAT up,
  ///       3. falls back to the English text — never blank.
  static String trText(String englishText, String languageCode) {
    if (languageCode == fallbackCode) return englishText;

    final map = _cache[resolveCode(languageCode)];
    if (map == null) return englishText;

    final direct = map[englishText];
    if (direct != null && direct.isNotEmpty) return direct;

    final fb = _cache[fallbackCode];
    if (fb != null) {
      for (final entry in fb.entries) {
        if (entry.value == englishText) {
          final translated = map[entry.key];
          if (translated != null && translated.isNotEmpty) {
            return translated;
          }
        }
      }
    }

    return englishText;
  }
}

/// Compatibility shim: if your `app_localizations.dart` currently
/// calls something like `translate(locale, key)` from the old
/// generated file, keep that call working by pointing it here
/// (or just call `AppCatalogs.tr(...)` directly):
///
///   String tr(BuildContext context, String key) =>
///       AppCatalogs.tr(Localizations.localeOf(context).languageCode, key);
String translate(String languageCode, String key) =>
    AppCatalogs.tr(languageCode, key);

/// Top-level wrapper so callers can use `trText(...)` without the
/// class prefix. The real logic lives in AppCatalogs.trText.
String trText(String englishText, String languageCode) =>
    AppCatalogs.trText(englishText, languageCode);

/// Marker so existing imports keep compiling while you migrate.
/// Delete once nothing references the old per-language maps
/// (`_en`, `_sw`, `_fr`, ...). They no longer exist in this file.
// ignore: unused_element
const bool generatedFromJson = true;