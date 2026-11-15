import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yen_back/core/store_catalog.dart';

void main() {
  final catalog = StoreCatalog.parse(File('assets/stores.json').readAsStringSync());

  List<String> names(String q, {List<String> recent = const []}) =>
      catalog.suggest(q, recent: recent).map((s) => s.name).toList();

  test('bundled catalog parses', () {
    expect(catalog.brands.length, greaterThan(30));
    expect(catalog.brands.first.ko, '돈키호테');
  });

  test('empty query lists recent shops first, then curated chains', () {
    final s = catalog.suggest('', recent: ['돈키호테 도톤보리점', '빅카메라 난바점']);
    expect(s.take(3).map((e) => e.name), ['돈키호테 도톤보리점', '빅카메라 난바점', '돈키호테']);
    expect(s.first.isRecent, isTrue);
    expect(s[2].isRecent, isFalse);
    expect(s.length, 12); // limit
  });

  test('matches Korean prefix, aliases, Japanese and English', () {
    expect(names('돈키').first, '돈키호테');
    expect(names('마츠키요'), contains('마츠모토키요시')); // alias
    expect(names('ドン'), contains('돈키호테')); // Japanese
    expect(names('uniq'), contains('유니클로')); // English, case-insensitive
    expect(names('bic camera'), contains('빅카메라')); // spaces ignored
  });

  test('Korean prefix ranks above contains-only matches', () {
    // 다이소, 다이코쿠드럭, 다이마루 start with 다이: curated order among them.
    expect(names('다이').take(3), ['다이소', '다이코쿠드럭', '다이마루']);
    // 드럭 only appears inside names: all are contains-matches.
    expect(names('드럭'), containsAll(['다이코쿠드럭', '츠루하드럭', '선드럭']));
  });

  test('recent shop matching the query comes before the chain', () {
    final r = names('돈키', recent: ['돈키호테 신사이바시점']);
    expect(r.first, '돈키호테 신사이바시점');
    expect(r, contains('돈키호테'));
  });

  test('no match returns empty, so free text is still allowed', () {
    expect(names('존재하지않는가게'), isEmpty);
  });

  test('malformed entries are skipped', () {
    final c = StoreCatalog.parse('{"version":"x","stores":[{"id":"a","ko":"A"},{"id":""},{"ko":"no id"},3]}');
    expect(c.brands.map((b) => b.ko), ['A']);
  });
}
