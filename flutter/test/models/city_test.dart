import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/city.dart';
import 'package:mereytoi_app/state/locale_provider.dart';

void main() {
  test('1. City.fromJson parses id/name_ru/name_kz/name_en', () {
    final city = City.fromJson({
      'id': 15,
      'name_ru': 'Туркестан',
      'name_kz': 'Түркістан',
      'name_en': 'Turkistan',
    });
    expect(city.id, 15);
    expect(city.nameRu, 'Туркестан');
    expect(city.nameKz, 'Түркістан');
    expect(city.nameEn, 'Turkistan');
  });

  test('missing names parse as empty strings, never crash', () {
    final city = City.fromJson({'id': 3});
    expect(city.id, 3);
    expect(city.nameRu, '');
    expect(city.nameKz, '');
    expect(city.nameEn, '');
  });

  test('name(locale) picks RU/KZ/EN', () {
    const city = City(
      id: 8,
      nameRu: 'Усть-Каменогорск',
      nameKz: 'Өскемен',
      nameEn: 'Oskemen',
    );
    expect(city.name(AppLocale.ru), 'Усть-Каменогорск');
    expect(city.name(AppLocale.kz), 'Өскемен');
    expect(city.name(AppLocale.en), 'Oskemen');
  });

  group('matches — case-insensitive over all three names', () {
    const almaty = City(
      id: 1,
      nameRu: 'Алматы',
      nameKz: 'Алматы',
      nameEn: 'Almaty',
    );
    const karaganda = City(
      id: 4,
      nameRu: 'Караганда',
      nameKz: 'Қарағанды',
      nameEn: 'Karaganda',
    );
    const ust = City(
      id: 8,
      nameRu: 'Усть-Каменогорск',
      nameKz: 'Өскемен',
      nameEn: 'Oskemen',
    );

    test('empty/blank query matches everything', () {
      expect(almaty.matches(''), isTrue);
      expect(almaty.matches('   '), isTrue);
    });
    test('RU prefix and substring, any case', () {
      expect(almaty.matches('Алм'), isTrue);
      expect(almaty.matches('алм'), isTrue);
      expect(almaty.matches('АЛМАТЫ'), isTrue);
      expect(almaty.matches('маты'), isTrue);
    });
    test('KZ letters', () {
      expect(karaganda.matches('қарағ'), isTrue);
      expect(karaganda.matches('ҚАРАҒАНДЫ'), isTrue);
      expect(ust.matches('өске'), isTrue);
    });
    test('EN', () {
      expect(almaty.matches('alm'), isTrue);
      expect(karaganda.matches('KARAG'), isTrue);
    });
    test('hyphen and spaces normalize', () {
      expect(ust.matches('усть кам'), isTrue);
      expect(ust.matches('  Усть-Кам '), isTrue);
    });
    test('non-matching query', () {
      expect(almaty.matches('аст'), isFalse);
      expect(almaty.matches('zzz'), isFalse);
    });
  });
}
