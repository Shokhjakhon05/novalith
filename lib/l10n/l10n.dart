/// Localisation without code generation: one map per language, looked up by key at runtime, so
/// the language switches instantly without restarting anything.
library;

import 'lang_ar.dart';
import 'lang_bn.dart';
import 'lang_de.dart';
import 'lang_en.dart';
import 'lang_es.dart';
import 'lang_fr.dart';
import 'lang_hi.dart';
import 'lang_id.dart';
import 'lang_ja.dart';
import 'lang_pt.dart';
import 'lang_ru.dart';
import 'lang_tr.dart';
import 'lang_ur.dart';
import 'lang_uz.dart';
import 'lang_vi.dart';
import 'lang_zh.dart';

class Language {
  const Language(this.code, this.nativeName, this.strings, {this.rtl = false});
  final String code;

  /// The language's own name - shown untranslated in the language picker.
  final String nativeName;
  final Map<String, String> strings;
  final bool rtl;
}

/// English first: it is the fallback for anything missing.
const List<Language> languages = [
  Language('en', 'English', en),
  Language('zh', '中文', zh),
  Language('hi', 'हिन्दी', hi),
  Language('es', 'Español', es),
  Language('fr', 'Français', fr),
  Language('ar', 'العربية', ar, rtl: true),
  Language('bn', 'বাংলা', bn),
  Language('pt', 'Português', pt),
  Language('ru', 'Русский', ru),
  Language('ur', 'اردو', ur, rtl: true),
  Language('id', 'Bahasa Indonesia', id),
  Language('de', 'Deutsch', de),
  Language('ja', '日本語', ja),
  Language('tr', 'Türkçe', tr),
  Language('vi', 'Tiếng Việt', vi),
  Language('uz', 'Oʻzbekcha', uz),
];

Language languageByCode(String code) {
  for (final l in languages) {
    if (l.code == code) return l;
  }
  return languages.first;
}

/// Saved choice -> device language -> English.
Language resolveLanguage(String saved, String deviceCode) {
  for (final l in languages) {
    if (l.code == saved) return l;
  }
  final device = deviceCode.toLowerCase().split(RegExp('[-_]')).first;
  for (final l in languages) {
    if (l.code == device) return l;
  }
  return languages.first;
}

class L10n {
  L10n(this.language);
  final Language language;

  /// Looks up [key]; `{name}` placeholders are filled from [args]. Falls back to English and,
  /// as a last resort, to the key itself - a missing string must never crash the game.
  String t(String key, [Map<String, Object> args = const {}]) {
    var s = language.strings[key] ?? en[key] ?? key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}
