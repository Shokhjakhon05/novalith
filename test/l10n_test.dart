import 'package:flutter_test/flutter_test.dart';
import 'package:novalith/core/balance.dart';
import 'package:novalith/core/progression.dart';
import 'package:novalith/l10n/l10n.dart';
import 'package:novalith/l10n/lang_en.dart';

void main() {
  final placeholder = RegExp(r'\{(\w+)\}');
  Set<String> holes(String s) => placeholder.allMatches(s).map((m) => m.group(1)!).toSet();

  test('16 languages, unique codes, English is the fallback', () {
    expect(languages.length, 16);
    expect(languages.map((l) => l.code).toSet().length, 16);
    expect(languages.first.code, 'en');
    expect(languages.where((l) => l.rtl).map((l) => l.code).toSet(), {'ar', 'ur'});
  });

  for (final lang in languages) {
    test('${lang.code}: complete, no empty strings, same placeholders as English', () {
      expect(lang.strings.keys.toSet(), en.keys.toSet(), reason: 'key set differs in ${lang.code}');
      for (final key in en.keys) {
        final s = lang.strings[key]!;
        expect(s.trim(), isNotEmpty, reason: '${lang.code}.$key is empty');
        expect(holes(s), holes(en[key]!), reason: '${lang.code}.$key placeholders');
        expect(s.contains('TODO') || s.contains('???'), isFalse);
      }
    });
  }

  test('every evolution level, shop item and achievement kind has a string', () {
    for (final l in Balance.defaultLevels) {
      expect(en.containsKey('evo_${l.key}'), isTrue, reason: l.key);
    }
    for (final i in shopItems) {
      expect(en.containsKey(i.id), isTrue, reason: i.id);
    }
  });

  test('language resolution: saved -> device -> English', () {
    expect(resolveLanguage('uz', 'ru').code, 'uz');
    expect(resolveLanguage('', 'ru_RU').code, 'ru');
    expect(resolveLanguage('', 'pt-BR').code, 'pt');
    expect(resolveLanguage('', 'ZH').code, 'zh');
    expect(resolveLanguage('', 'sw').code, 'en', reason: 'unsupported locale falls back');
    expect(resolveLanguage('xx', 'yy').code, 'en');
    expect(resolveLanguage('', '').code, 'en');
  });

  test('lookup fills placeholders and never throws on a missing key', () {
    final l = L10n(languageByCode('ru'));
    expect(l.t('level_n', {'n': 7}), 'Уровень 7');
    expect(l.t('no_such_key'), 'no_such_key');
    expect(L10n(languageByCode('nope')).t('play'), 'Play');
  });
}
