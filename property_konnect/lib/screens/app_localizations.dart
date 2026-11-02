import 'package:flutter/material.dart';

import 'app_settings.dart';
import '../l10n/catalogs.g.dart' as gen;

/// ============================================================
/// LANGUAGE REGISTRY — world languages.
///
/// Every registered language appears automatically in the
/// first-launch Language Selection page and in App Settings.
/// To add one more language:
///   1. Add an entry to AppLanguages.all.
///   2. Drop a `<code>.json` file into `lib/l10n/` (e.g. sw.json).
///      catalogs.g.dart loads it at runtime — no regeneration,
///      no hardcoded maps. Missing keys fall back to English
///      automatically, never blank, never a crash.
///
/// NOTE: Dart reserved words / built-in identifiers such as `is`
/// and `as` CANNOT be used as variable names. Icelandic (code
/// 'is') is therefore the constant `isl`, and Assamese (code
/// 'as') is the constant `asm`. The language CODES stay 'is' and
/// 'as' — only the Dart variable names differ.
///
/// LOOKUP CHANGED: `gen.catalogs` no longer exists as a static
/// map (translations now live in the JSON files). All lookups
/// go through `gen.AppCatalogs`, which preloads the JSON files
/// at startup (see main.dart) and again in
/// SettingsController.setLanguageCode whenever the language
/// changes.
/// ============================================================

class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.name, // shown in English UI
    required this.nativeName, // shown in its own script
    required this.flag,
    this.rtl = false,
  });

  final String code;
  final String name;
  final String nativeName;
  final String flag;
  final bool rtl;
}

class AppLanguages {
  AppLanguages._();

  // ---------- EAST AFRICA / KENYA ----------
  static const en = AppLanguage(code: 'en', name: 'English', nativeName: 'English', flag: '🇬🇧');
  static const sw = AppLanguage(code: 'sw', name: 'Kiswahili', nativeName: 'Kiswahili', flag: '🇰🇪');
  static const rw = AppLanguage(code: 'rw', name: 'Kinyarwanda', nativeName: 'Ikinyarwanda', flag: '🇷🇼');
  static const lg = AppLanguage(code: 'lg', name: 'Luganda', nativeName: 'Luganda', flag: '🇺🇬');
  static const ny = AppLanguage(code: 'ny', name: 'Chichewa', nativeName: 'Chichewa', flag: '🇲🇼');
  static const sn = AppLanguage(code: 'sn', name: 'Shona', nativeName: 'ChiShona', flag: '🇿🇼');
  static const so = AppLanguage(code: 'so', name: 'Somali', nativeName: 'Soomaali', flag: '🇸🇴');
  static const am = AppLanguage(code: 'am', name: 'Amharic', nativeName: 'አማርኛ', flag: '🇪🇹');
  static const mg = AppLanguage(code: 'mg', name: 'Malagasy', nativeName: 'Malagasy', flag: '🇲🇬');

  // ---------- OTHER AFRICA ----------
  static const ha = AppLanguage(code: 'ha', name: 'Hausa', nativeName: 'Hausa', flag: '🇳🇬');
  static const yo = AppLanguage(code: 'yo', name: 'Yoruba', nativeName: 'Yorùbá', flag: '🇳🇬');
  static const ig = AppLanguage(code: 'ig', name: 'Igbo', nativeName: 'Igbo', flag: '🇳🇬');
  static const zu = AppLanguage(code: 'zu', name: 'Zulu', nativeName: 'isiZulu', flag: '🇿🇦');
  static const xh = AppLanguage(code: 'xh', name: 'Xhosa', nativeName: 'isiXhosa', flag: '🇿🇦');
  static const af = AppLanguage(code: 'af', name: 'Afrikaans', nativeName: 'Afrikaans', flag: '🇿🇦');

  // ---------- EUROPE ----------
  static const fr = AppLanguage(code: 'fr', name: 'French', nativeName: 'Français', flag: '🇫🇷');
  static const de = AppLanguage(code: 'de', name: 'German', nativeName: 'Deutsch', flag: '🇩🇪');
  static const es = AppLanguage(code: 'es', name: 'Spanish', nativeName: 'Español', flag: '🇪🇸');
  static const pt = AppLanguage(code: 'pt', name: 'Portuguese', nativeName: 'Português', flag: '🇵🇹');
  static const it = AppLanguage(code: 'it', name: 'Italian', nativeName: 'Italiano', flag: '🇮🇹');
  static const nl = AppLanguage(code: 'nl', name: 'Dutch', nativeName: 'Nederlands', flag: '🇳🇱');
  static const sv = AppLanguage(code: 'sv', name: 'Swedish', nativeName: 'Svenska', flag: '🇸🇪');
  static const no = AppLanguage(code: 'no', name: 'Norwegian', nativeName: 'Norsk', flag: '🇳🇴');
  static const da = AppLanguage(code: 'da', name: 'Danish', nativeName: 'Dansk', flag: '🇩🇰');
  static const fi = AppLanguage(code: 'fi', name: 'Finnish', nativeName: 'Suomi', flag: '🇫🇮');

  // FIX: was `is` — a reserved word in Dart. Code stays 'is'.
  static const isl = AppLanguage(code: 'is', name: 'Icelandic', nativeName: 'Íslenska', flag: '🇮🇸');

  static const el = AppLanguage(code: 'el', name: 'Greek', nativeName: 'Ελληνικά', flag: '🇬🇷');
  static const pl = AppLanguage(code: 'pl', name: 'Polish', nativeName: 'Polski', flag: '🇵🇱');
  static const cs = AppLanguage(code: 'cs', name: 'Czech', nativeName: 'Čeština', flag: '🇨🇿');
  static const sk = AppLanguage(code: 'sk', name: 'Slovak', nativeName: 'Slovenčina', flag: '🇸🇰');
  static const hu = AppLanguage(code: 'hu', name: 'Hungarian', nativeName: 'Magyar', flag: '🇭🇺');
  static const ro = AppLanguage(code: 'ro', name: 'Romanian', nativeName: 'Română', flag: '🇷🇴');
  static const bg = AppLanguage(code: 'bg', name: 'Bulgarian', nativeName: 'Български', flag: '🇧🇬');
  static const uk = AppLanguage(code: 'uk', name: 'Ukrainian', nativeName: 'Українська', flag: '🇺🇦');
  static const ru = AppLanguage(code: 'ru', name: 'Russian', nativeName: 'Русский', flag: '🇷🇺');
  static const sr = AppLanguage(code: 'sr', name: 'Serbian', nativeName: 'Српски', flag: '🇷🇸');
  static const hr = AppLanguage(code: 'hr', name: 'Croatian', nativeName: 'Hrvatski', flag: '🇭🇷');
  static const sl = AppLanguage(code: 'sl', name: 'Slovenian', nativeName: 'Slovenščina', flag: '🇸🇮');
  static const mk = AppLanguage(code: 'mk', name: 'Macedonian', nativeName: 'Македонски', flag: '🇲🇰');
  static const sq = AppLanguage(code: 'sq', name: 'Albanian', nativeName: 'Shqip', flag: '🇦🇱');
  static const lt = AppLanguage(code: 'lt', name: 'Lithuanian', nativeName: 'Lietuvių', flag: '🇱🇹');
  static const lv = AppLanguage(code: 'lv', name: 'Latvian', nativeName: 'Latviešu', flag: '🇱🇻');
  static const et = AppLanguage(code: 'et', name: 'Estonian', nativeName: 'Eesti', flag: '🇪🇪');
  static const ca = AppLanguage(code: 'ca', name: 'Catalan', nativeName: 'Català', flag: '🇪🇸');
  static const eu = AppLanguage(code: 'eu', name: 'Basque', nativeName: 'Euskara', flag: '🇪🇸');
  static const gl = AppLanguage(code: 'gl', name: 'Galician', nativeName: 'Galego', flag: '🇪🇸');

  // ---------- MIDDLE EAST ----------
  static const ar = AppLanguage(code: 'ar', name: 'Arabic', nativeName: 'العربية', flag: '🇸🇦', rtl: true);
  static const he = AppLanguage(code: 'he', name: 'Hebrew', nativeName: 'עברית', flag: '🇮🇱', rtl: true);
  static const fa = AppLanguage(code: 'fa', name: 'Persian', nativeName: 'فارسی', flag: '🇮🇷', rtl: true);
  static const ps = AppLanguage(code: 'ps', name: 'Pashto', nativeName: 'پښتو', flag: '🇦🇫', rtl: true);
  static const ur = AppLanguage(code: 'ur', name: 'Urdu', nativeName: 'اردو', flag: '🇵🇰', rtl: true);
  static const ku = AppLanguage(code: 'ku', name: 'Kurdish', nativeName: 'Kurdî', flag: '🇮🇶');
  static const tr = AppLanguage(code: 'tr', name: 'Turkish', nativeName: 'Türkçe', flag: '🇹🇷');
  static const hy = AppLanguage(code: 'hy', name: 'Armenian', nativeName: 'Հայերեն', flag: '🇦🇲');
  static const ka = AppLanguage(code: 'ka', name: 'Georgian', nativeName: 'ქართული', flag: '🇬🇪');
  static const az = AppLanguage(code: 'az', name: 'Azerbaijani', nativeName: 'Azərbaycan', flag: '🇦🇿');

  // ---------- CENTRAL ASIA ----------
  static const kk = AppLanguage(code: 'kk', name: 'Kazakh', nativeName: 'Қазақ', flag: '🇰🇿');
  static const uz = AppLanguage(code: 'uz', name: 'Uzbek', nativeName: 'Oʻzbek', flag: '🇺🇿');
  static const ky = AppLanguage(code: 'ky', name: 'Kyrgyz', nativeName: 'Кыргыз', flag: '🇰🇬');
  static const tg = AppLanguage(code: 'tg', name: 'Tajik', nativeName: 'Тоҷикӣ', flag: '🇹🇯');
  static const tk = AppLanguage(code: 'tk', name: 'Turkmen', nativeName: 'Türkmen', flag: '🇹🇲');
  static const mn = AppLanguage(code: 'mn', name: 'Mongolian', nativeName: 'Монгол', flag: '🇲🇳');

  // ---------- SOUTH ASIA ----------
  static const hi = AppLanguage(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी', flag: '🇮🇳');
  static const bn = AppLanguage(code: 'bn', name: 'Bengali', nativeName: 'বাংলা', flag: '🇧🇩');
  static const ta = AppLanguage(code: 'ta', name: 'Tamil', nativeName: 'தமிழ்', flag: '🇮🇳');
  static const te = AppLanguage(code: 'te', name: 'Telugu', nativeName: 'తెలుగు', flag: '🇮🇳');
  static const mr = AppLanguage(code: 'mr', name: 'Marathi', nativeName: 'मराठी', flag: '🇮🇳');
  static const gu = AppLanguage(code: 'gu', name: 'Gujarati', nativeName: 'ગુજરાતી', flag: '🇮🇳');
  static const pa = AppLanguage(code: 'pa', name: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ', flag: '🇮🇳');
  static const ml = AppLanguage(code: 'ml', name: 'Malayalam', nativeName: 'മലയാളം', flag: '🇮🇳');
  static const kn = AppLanguage(code: 'kn', name: 'Kannada', nativeName: 'ಕನ್ನಡ', flag: '🇮🇳');
  static const or = AppLanguage(code: 'or', name: 'Odia', nativeName: 'ଓଡ଼ିଆ', flag: '🇮🇳');

  // FIX: was `as` — a built-in identifier in Dart. Code stays 'as'.
  static const asm = AppLanguage(code: 'as', name: 'Assamese', nativeName: 'অসমীয়া', flag: '🇮🇳');

  static const ne = AppLanguage(code: 'ne', name: 'Nepali', nativeName: 'नेपाली', flag: '🇳🇵');
  static const si = AppLanguage(code: 'si', name: 'Sinhala', nativeName: 'සිංහල', flag: '🇱🇰');

  // ---------- SOUTHEAST ASIA ----------
  static const id = AppLanguage(code: 'id', name: 'Indonesian', nativeName: 'Bahasa Indonesia', flag: '🇮🇩');
  static const ms = AppLanguage(code: 'ms', name: 'Malay', nativeName: 'Bahasa Melayu', flag: '🇲🇾');
  static const jv = AppLanguage(code: 'jv', name: 'Javanese', nativeName: 'Basa Jawa', flag: '🇮🇩');
  static const su = AppLanguage(code: 'su', name: 'Sundanese', nativeName: 'Basa Sunda', flag: '🇮🇩');
  static const ceb = AppLanguage(code: 'ceb', name: 'Cebuano', nativeName: 'Cebuano', flag: '🇵🇭');

  // FIX: 'tl' is the legacy code, but the JSON file is 'fil.json'.
  // catalogs.g.dart aliases 'tl' -> 'fil', so this now works.
  static const tl = AppLanguage(code: 'tl', name: 'Filipino', nativeName: 'Filipino', flag: '🇵🇭');

  static const vi = AppLanguage(code: 'vi', name: 'Vietnamese', nativeName: 'Tiếng Việt', flag: '🇻🇳');
  static const th = AppLanguage(code: 'th', name: 'Thai', nativeName: 'ไทย', flag: '🇹🇭');
  static const km = AppLanguage(code: 'km', name: 'Khmer', nativeName: 'ខ្មែរ', flag: '🇰🇭');
  static const lo = AppLanguage(code: 'lo', name: 'Lao', nativeName: 'ລາວ', flag: '🇱🇦');
  static const my = AppLanguage(code: 'my', name: 'Burmese', nativeName: 'မြန်မာ', flag: '🇲🇲');

  // ---------- EAST ASIA ----------
  static const zh = AppLanguage(code: 'zh', name: 'Chinese', nativeName: '中文', flag: '🇨🇳');
  static const ja = AppLanguage(code: 'ja', name: 'Japanese', nativeName: '日本語', flag: '🇯🇵');
  static const ko = AppLanguage(code: 'ko', name: 'Korean', nativeName: '한국어', flag: '🇰🇷');

  /// Every language the app offers. Add new ones here.
  static const List<AppLanguage> all = [
    // East Africa / Kenya first
    sw, en, rw, lg, ny, sn, so, am, mg,
    // Other Africa
    ha, yo, ig, zu, xh, af,
    // Europe
    fr, de, es, pt, it, nl, sv, no, da, fi, isl, el,
    pl, cs, sk, hu, ro, bg, uk, ru, sr, hr, sl, mk, sq,
    lt, lv, et, ca, eu, gl,
    // Middle East
    ar, he, fa, ps, ur, ku, tr, hy, ka, az,
    // Central Asia
    kk, uz, ky, tg, tk, mn,
    // South Asia
    hi, bn, ta, te, mr, gu, pa, ml, kn, or, asm, ne, si,
    // Southeast Asia
    id, ms, jv, su, ceb, tl, vi, th, km, lo, my,
    // East Asia
    zh, ja, ko,
  ];

  static AppLanguage byCode(String code) =>
      all.firstWhere((l) => l.code == code, orElse: () => en);
}

/// ============================================================
/// STRING KEYS — one constant per user-facing string.
/// ============================================================

class AppStrings {
  AppStrings._();

  // ---------- GENERIC / SHARED ----------
  static const ok = 'ok';
  static const continueBtn = 'continueBtn';
  static const backToLogin = 'backToLogin';
  static const pleaseWait = 'pleaseWait';
  static const email = 'email';
  static const password = 'password';
  static const login = 'login';
  static const signUp = 'signUp';

  // ---------- LANGUAGE SELECTION ----------
  static const chooseLanguage = 'chooseLanguage';
  static const chooseLanguageSub = 'chooseLanguageSub';

  // ---------- APP SETTINGS PAGE ----------
  static const appSettingsTitle = 'appSettingsTitle';
  static const appearance = 'appearance';
  static const darkMode = 'darkMode';
  static const darkModeSub = 'darkModeSub';
  static const darkEnabled = 'darkEnabled';
  static const lightEnabled = 'lightEnabled';
  static const language = 'language';
  static const textSize = 'textSize';
  static const small = 'small';
  static const medium = 'medium';
  static const large = 'large';
  static const textSizeUpdated = 'textSizeUpdated';

  // ---------- HOME PAGE ----------
  static const menu = 'menu';
  static const collapseMenu = 'collapseMenu';
  static const findYourNextPlace = 'findYourNextPlace';
  static const studentHub = 'studentHub';
  static const favourites = 'favourites';
  static const services = 'services';
  static const appSettings = 'appSettings';
  static const faqs = 'faqs';
  static const contactUs = 'contactUs';
  static const aboutApp = 'aboutApp';
  static const heroHeadline = 'heroHeadline';
  static const heroSub = 'heroSub';
  static const verifiedListingsOnly = 'verifiedListingsOnly';
  static const rent = 'rent';
  static const buy = 'buy';
  static const counties = 'counties';
  static const subcounties = 'subcounties';
  static const propertyCategories = 'propertyCategories';
  static const ourMission = 'ourMission';
  static const missionBody = 'missionBody';
  static const whoWeServe = 'whoWeServe';
  static const whoWeServeSub = 'whoWeServeSub';
  static const students = 'students';
  static const studentsBody = 'studentsBody';
  static const tenantsBuyers = 'tenantsBuyers';
  static const tenantsBuyersBody = 'tenantsBuyersBody';
  static const propertyOwners = 'propertyOwners';
  static const propertyOwnersBody = 'propertyOwnersBody';
  static const whatYouCanFind = 'whatYouCanFind';
  static const whatYouCanFindSub = 'whatYouCanFindSub';
  static const residential = 'residential';
  static const commercial = 'commercial';
  static const shortStay = 'shortStay';
  static const land = 'land';
  static const whereWeCover = 'whereWeCover';
  static const whereWeCoverSub = 'whereWeCoverSub';
  static const subcountiesIn = 'subcountiesIn';
  static const journeyTitle = 'journeyTitle';
  static const journeySub = 'journeySub';
  static const stepFind = 'stepFind';
  static const stepCompare = 'stepCompare';
  static const stepContact = 'stepContact';
  static const stepView = 'stepView';
  static const stepRentBuy = 'stepRentBuy';
  static const stepMove = 'stepMove';
  static const stepLive = 'stepLive';
  static const whyChooseUs = 'whyChooseUs';
  static const whyWideTitle = 'whyWideTitle';
  static const whyWideSub = 'whyWideSub';
  static const whyVerifiedTitle = 'whyVerifiedTitle';
  static const whyVerifiedSub = 'whyVerifiedSub';
  static const whyMobileTitle = 'whyMobileTitle';
  static const whyMobileSub = 'whyMobileSub';
  static const whySmartTitle = 'whySmartTitle';
  static const whySmartSub = 'whySmartSub';
  static const whySafeTitle = 'whySafeTitle';
  static const whySafeSub = 'whySafeSub';
  static const safetyReminder = 'safetyReminder';
  static const safetyBody1 = 'safetyBody1';
  static const safetyBody2 = 'safetyBody2';
  static const areYouStudent = 'areYouStudent';
  static const studentSectionBody = 'studentSectionBody';
  static const openStudentHub = 'openStudentHub';
  static const listYourProperty = 'listYourProperty';
  static const listYourPropertySub = 'listYourPropertySub';
  static const contactUsSub = 'contactUsSub';
  static const copyright = 'copyright';

  // ---------- EMAIL VERIFICATION PAGE ----------
  static const verifyEmail = 'verifyEmail';
  static const verifyYourEmail = 'verifyYourEmail';
  static const verifyIntro = 'verifyIntro';
  static const linkSentResendIn = 'linkSentResendIn';
  static const verifyingYourEmail = 'verifyingYourEmail';
  static const waitingForClick = 'waitingForClick';
  static const tapVerifyToSend = 'tapVerifyToSend';
  static const checkSpam = 'checkSpam';
  static const linkSent = 'linkSent';
  static const linkInvalid = 'linkInvalid';
  static const verifyFailed = 'verifyFailed';
  static const couldNotSend = 'couldNotSend';
  static const tooManyRequests = 'tooManyRequests';
}

/// ============================================================
/// LOOKUP — translations live in the JSON files
/// (lib/l10n/<code>.json), loaded at runtime by
/// gen.AppCatalogs. Missing keys fall back to English, then to
/// the key itself, so partial translations are fine.
///
/// IMPORTANT: gen.AppCatalogs.load() must have completed for the
/// current language before any tr() call. That happens in
/// main() and in SettingsController.setLanguageCode().
/// ============================================================

class AppLocalizations {
  AppLocalizations._();

  /// THE one translation entry point. Language comes from
  /// AppSettings — pages never decide it themselves.
  /// Falls back: selected language -> English -> key.
  static String tr(BuildContext context, String key) {
    final code = AppSettings.of(context).languageCode;
    return gen.AppCatalogs.tr(code, key);
  }

  /// Used by the pages that still carry inline
  /// _tr('English', 'Kiswahili') pairs.
  ///
  /// Translates using the ENGLISH TEXT as the key:
  ///   * 'en'      -> returns the English text as-is.
  ///   * Any other language:
  ///       1. looks the English text up directly in that
  ///          language's catalog (English-text-keyed entries),
  ///       2. then reverse-maps the English text to a key via
  ///          the English catalog and looks THAT up,
  ///       3. and finally falls back to the English text —
  ///          never blank, never a crash.
  static String trText(String englishText, String languageCode) {
    return gen.trText(englishText, languageCode);
  }
}