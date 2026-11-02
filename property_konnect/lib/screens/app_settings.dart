import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';
import '../l10n/catalogs.g.dart' as gen;

// ============================================================
// BRAND COLORS
// ============================================================

const Color kBrandGreen = Color(0xFF167A4B);
const Color kBrandGreenOnDark = Color(0xFF2FBF71);
const Color kPageBackgroundLight = Color(0xFFF6FAF7);
const Color kPageBackgroundDark = Color(0xFF101612);
const Color kDarkCard = Color(0xFF1A241D);

/// Noto fallback families (loaded by the google_fonts package via
/// pubspec) so every registered language's script renders —
/// Ethiopic, Khmer, Tamil, Arabic, CJK, etc.
const List<String> kFontFallbacks = [
  'Noto Sans',
  'Noto Sans Ethiopic',
  'Noto Sans Arabic',
  'Noto Sans Hebrew',
  'Noto Sans Devanagari',
  'Noto Sans Bengali',
  'Noto Sans Gujarati',
  'Noto Sans Gurmukhi',
  'Noto Sans Oriya',
  'Noto Sans Tamil',
  'Noto Sans Telugu',
  'Noto Sans Kannada',
  'Noto Sans Malayalam',
  'Noto Sans Sinhala',
  'Noto Sans Thai',
  'Noto Sans Lao',
  'Noto Sans Khmer',
  'Noto Sans Myanmar',
  'Noto Sans Armenian',
  'Noto Sans Georgian',
  'Noto Sans JP',
  'Noto Sans KR',
  'Noto Sans SC',
];

// ============================================================
// LANGUAGES — generated from the AppLanguages registry, so
// adding a language in app_localizations.dart is the ONLY
// change needed for it to appear in MaterialApp too.
// ============================================================

class KenyaLanguages {
  KenyaLanguages._();

  static final List<Locale> supportedLocales = [
    for (final l in AppLanguages.all) Locale(l.code),
  ];

  static const localizationsDelegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}

// ============================================================
// SETTINGS CONTROLLER — the ONE place coordinating language,
// brightness and text size for the entire app.
// ============================================================

class SettingsController extends ChangeNotifier {
  /// FIX: initializing formal — no manual assignment lint.
  SettingsController({this.prefs});

  SharedPreferences? prefs;

  static const String _prefKeyLanguage = 'app_language';
  static const String _prefKeyBrightness = 'app_brightness';
  static const String _prefKeyTextSize = 'app_text_size';
  static const String _prefKeyLanguageChosen = 'app_language_chosen';

  static const String textSizeSmall = 'small';
  static const String textSizeMedium = 'medium';
  static const String textSizeLarge = 'large';

  static const List<String> textSizes = [
    textSizeSmall,
    textSizeMedium,
    textSizeLarge,
  ];

  String _languageCode = 'en';
  bool _languageChosen = false;
  ThemeMode _themeMode = ThemeMode.system;
  String _textSize = textSizeMedium;

  // ----------------------------------------------------------
  // LOAD / SAVE
  // ----------------------------------------------------------

  Future<void> load() async {
    prefs ??= await SharedPreferences.getInstance();

    _languageCode = prefs!.getString(_prefKeyLanguage) ?? 'en';

    if (!AppLanguages.all.any((l) => l.code == _languageCode)) {
      _languageCode = 'en';
    }
    _languageChosen = prefs!.getBool(_prefKeyLanguageChosen) ?? false;

    final savedBrightness = prefs!.getString(_prefKeyBrightness);
    if (savedBrightness == 'light') {
      _themeMode = ThemeMode.light;
    } else if (savedBrightness == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }

    _textSize = prefs!.getString(_prefKeyTextSize) ?? textSizeMedium;

    notifyListeners();
  }

  Future<void> _save(String key, String value) async {
    prefs ??= await SharedPreferences.getInstance();
    await prefs!.setString(key, value);
  }

  // ----------------------------------------------------------
  // LANGUAGE (any language from AppLanguages.all)
  // ----------------------------------------------------------

  String get languageCode => _languageCode;

  Locale get locale => Locale(_languageCode);

  AppLanguage get language => AppLanguages.byCode(_languageCode);

  Future<void> setLanguageCode(String code) async {
    if (!AppLanguages.all.any((l) => l.code == code)) return;

    // Load the language's JSON catalog BEFORE saving/notifying,
    // so the very first rebuild of every page already sees the
    // new strings (live preview on the language selection page).
    await gen.AppCatalogs.load(code);

    _languageCode = code;
    await _save(_prefKeyLanguage, code);
    notifyListeners();
  }

  Future<void> setEnglish() => setLanguageCode('en');
  Future<void> setSwahili() => setLanguageCode('sw');

  bool get hasChosenLanguage => _languageChosen;

  Future<void> setLanguageChosen() async {
    _languageChosen = true;
    prefs ??= await SharedPreferences.getInstance();
    await prefs!.setBool(_prefKeyLanguageChosen, true);
    notifyListeners();
  }

  // ----------------------------------------------------------
  // BRIGHTNESS
  // ----------------------------------------------------------

  ThemeMode get themeMode => _themeMode;

  bool get isDark {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    return WidgetsBinding
        .instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _save(
      _prefKeyBrightness,
      mode == ThemeMode.dark
          ? 'dark'
          : mode == ThemeMode.light
          ? 'light'
          : 'system',
    );
    notifyListeners();
  }

  Future<void> toggleBrightness() async {
    await setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  // ----------------------------------------------------------
  // TEXT SIZE
  // ----------------------------------------------------------

  String get textSize => _textSize;

  double get textScale {
    switch (_textSize) {
      case textSizeSmall:
        return 0.85;
      case textSizeLarge:
        return 1.2;
      default:
        return 1.0;
    }
  }

  Future<void> setTextSize(String size) async {
    if (!textSizes.contains(size)) return;
    _textSize = size;
    await _save(_prefKeyTextSize, size);
    notifyListeners();
  }
}

// ============================================================
// APP SETTINGS (InheritedWidget scope + static app info)
// ============================================================

class AppSettings extends InheritedNotifier<SettingsController> {
  const AppSettings({
    super.key,
    required SettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static const String appName = 'Property Konnect';
  static const String appVersion = '1.0.0';
  static const String supportEmail = 'kenyahostelsandhomes@gmail.com';
  static const String supportPhone = '+254 717 547 703';

  static const String propertiesCollection = 'properties';
  static const String propertyViewsCollection = 'property_views';
  static const String favoritesCollection = 'favorites';

  static SettingsController of(BuildContext context) {
    final scope =
    context.dependOnInheritedWidgetOfExactType<AppSettings>();
    if (scope == null) {
      throw FlutterError(
        'AppSettings.of(context) was called with no AppSettings '
            'ancestor. Wrap the app (in main.dart) in an AppSettings '
            'widget.',
      );
    }
    return scope.notifier!;
  }
}

class AppSettingsScope extends AppSettings {
  const AppSettingsScope({
    super.key,
    required super.controller,
    required super.child,
  });

  static SettingsController of(BuildContext context) =>
      AppSettings.of(context);
}

// ============================================================
// APP THEME
//
// FIX: `fontFamilyFallback` is NOT a named parameter of
// ThemeData.copyWith in your Flutter version. The supported
// way is to apply it to the TEXT THEME via
// `.apply(fontFamilyFallback: ...)`, which every Text widget
// inherits automatically.
// ============================================================

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: kBrandGreen,
      brightness: Brightness.light,
    );

    // FIX: font fallback applied through the text theme.
    final textTheme =
    base.textTheme.apply(fontFamilyFallback: kFontFallbacks);

    return base.copyWith(
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: base.primaryTextTheme
          .apply(fontFamilyFallback: kFontFallbacks),
      scaffoldBackgroundColor: kPageBackgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: kBrandGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(color: Colors.white, elevation: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kBrandGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: kBrandGreen, width: 1.6),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: kBrandGreenOnDark,
      brightness: Brightness.dark,
    );

    // FIX: font fallback applied through the text theme.
    final textTheme =
    base.textTheme.apply(fontFamilyFallback: kFontFallbacks);

    return base.copyWith(
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: base.primaryTextTheme
          .apply(fontFamilyFallback: kFontFallbacks),
      scaffoldBackgroundColor: kPageBackgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0E3D2A),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(color: kDarkCard, elevation: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kBrandGreenOnDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: kBrandGreenOnDark, width: 1.6),
        ),
      ),
    );
  }
}

// ============================================================
// LANGUAGE PICKER FIELD  (shared by the first-launch
// LanguageSelectionPage and the AppSettingsPage)
// ============================================================

class LanguagePickerField extends StatelessWidget {
  /// Currently selected language code, or null when none is chosen.
  final String? selectedCode;

  /// Called with the language code the user picked.
  final ValueChanged<String> onChanged;

  final bool isDark;
  final bool isSwahili;

  const LanguagePickerField({
    super.key,
    required this.selectedCode,
    required this.onChanged,
    required this.isDark,
    required this.isSwahili,
  });

  String _txt(String en, String sw) => isSwahili ? sw : en;

  AppLanguage? get _selectedLanguage {
    final code = selectedCode;
    if (code == null) return null;

    for (final lang in AppLanguages.all) {
      if (lang.code == code) return lang;
    }
    return null;
  }

  Future<void> _openPicker(BuildContext context) async {
    FocusScope.of(context).unfocus();

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: isDark ? kDarkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LanguagePickerSheet(
        selectedCode: selectedCode,
        isDark: isDark,
        title: _txt('Choose your language', 'Chagua lugha yako'),
        searchHint: _txt('Search language...', 'Tafuta lugha...'),
        emptyText: _txt('No language found', 'Hakuna lugha imepatikana'),
      ),
    );

    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final brand = isDark ? kBrandGreenOnDark : kBrandGreen;
    final muted = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final border = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final selected = _selectedLanguage;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openPicker(context),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.language_rounded, color: brand),
          filled: true,
          fillColor: isDark ? kDarkCard : Colors.white,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: brand, width: 2),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: border),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: selected == null
                    ? Text(
                  _txt('Choose your language', 'Chagua lugha yako'),
                  style: TextStyle(fontSize: 16, color: muted),
                )
                    : Row(
                  children: [
                    Text(selected.flag,
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        selected.nativeName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: muted),
          ],
        ),
      ),
    );
  }
}

/// The bottom sheet: title, search bar and the filtered language list.
class _LanguagePickerSheet extends StatefulWidget {
  final String? selectedCode;
  final bool isDark;
  final String title;
  final String searchHint;
  final String emptyText;

  const _LanguagePickerSheet({
    required this.selectedCode,
    required this.isDark,
    required this.title,
    required this.searchHint,
    required this.emptyText,
  });

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  String _query = '';

  Color get _brand => widget.isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _muted =>
      widget.isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  List<AppLanguage> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return AppLanguages.all;

    return AppLanguages.all.where((lang) {
      return lang.code.toLowerCase().contains(query) ||
          lang.nativeName.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final languages = _filtered;
    final height = MediaQuery.of(context).size.height * 0.75;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _muted.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ---- SEARCH BAR (inside the list) ----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _brand, width: 2),
                  ),
                ),
              ),
            ),

            // ---- LANGUAGE LIST ----
            Expanded(
              child: languages.isEmpty
                  ? Center(
                child: Text(
                  widget.emptyText,
                  style: TextStyle(color: _muted),
                ),
              )
                  : ListView.builder(
                itemCount: languages.length,
                itemBuilder: (context, index) {
                  final lang = languages[index];
                  final isSelected = lang.code == widget.selectedCode;

                  return ListTile(
                    leading: Text(
                      lang.flag,
                      style: const TextStyle(fontSize: 24),
                    ),
                    title: Text(
                      lang.nativeName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isSelected ? _brand : null,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check, color: _brand)
                        : null,
                    onTap: () => Navigator.pop(context, lang.code),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// APP SETTINGS PAGE — one page coordinating language,
// dark/light mode and text size for the WHOLE app.
// ============================================================

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  SettingsController get _settings => AppSettings.of(context);

  String _tr(String key) => AppLocalizations.tr(context, key);

  Color get _brand => _settings.isDark ? kBrandGreenOnDark : kBrandGreen;

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr(AppStrings.appSettingsTitle)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ----------------------------------------------------
          // APPEARANCE
          // ----------------------------------------------------
          Text(
            _tr(AppStrings.appearance),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(
                settings.isDark ? Icons.dark_mode : Icons.light_mode,
                color: _brand,
              ),
              title: Text(_tr(AppStrings.darkMode)),
              subtitle: Text(_tr(AppStrings.darkModeSub)),
              trailing: Switch(
                value: settings.isDark,
                // FIX: activeColor -> activeThumbColor
                activeThumbColor: _brand,
                onChanged: (value) async {
                  await settings.toggleBrightness();
                  _showSnack(
                    value
                        ? _tr(AppStrings.darkEnabled)
                        : _tr(AppStrings.lightEnabled),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ----------------------------------------------------
          // LANGUAGE — tap to open the searchable language list
          // ----------------------------------------------------
          Text(
            _tr(AppStrings.language),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: LanguagePickerField(
              selectedCode: settings.languageCode,
              isDark: settings.isDark,
              isSwahili: settings.languageCode == 'sw',
              onChanged: (code) async {
                await settings.setLanguageCode(code);
                if (!mounted) return;
                final lang = AppLanguages.byCode(code);
                _showSnack('${lang.nativeName} ✓');
              },
            ),
          ),
          const SizedBox(height: 24),

          // ----------------------------------------------------
          // TEXT SIZE
          // ----------------------------------------------------
          Text(
            _tr(AppStrings.textSize),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<String>(
              groupValue: settings.textSize,
              onChanged: (value) async {
                if (value == null) return;
                await settings.setTextSize(value);
                _showSnack(_tr(AppStrings.textSizeUpdated));
              },
              child: const Column(
                children: [
                  _TextSizeTile(
                    value: SettingsController.textSizeSmall,
                    title: 'Small',
                    sampleFontSize: 13,
                  ),
                  Divider(height: 1),
                  _TextSizeTile(
                    value: SettingsController.textSizeMedium,
                    title: 'Medium',
                    sampleFontSize: 16,
                  ),
                  Divider(height: 1),
                  _TextSizeTile(
                    value: SettingsController.textSizeLarge,
                    title: 'Large',
                    sampleFontSize: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text-size tile as a const-friendly widget.
class _TextSizeTile extends StatelessWidget {
  const _TextSizeTile({
    required this.value,
    required this.title,
    required this.sampleFontSize,
  });

  final String value;
  final String title;
  final double sampleFontSize;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    final brand = settings.isDark ? kBrandGreenOnDark : kBrandGreen;
    final selected = settings.textSize == value;

    return RadioListTile<String>(
      value: value,
      title: Text(title),
      secondary: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? brand.withValues(alpha: 0.12) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Text('Aa', style: TextStyle(fontSize: sampleFontSize)),
      ),
    );
  }
}