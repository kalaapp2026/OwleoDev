import 'package:flutter_test/flutter_test.dart';
import 'package:owleo_hq/core/auth/hq_access.dart';
import 'package:owleo_hq/core/csv_parse.dart';
import 'package:owleo_hq/core/format.dart';
import 'package:owleo_hq/core/json.dart';

void main() {
  group('money and names', () {
    test('rupees use Indian digit grouping', () {
      expect(inr(123456), '₹1,23,456');
      expect(inr(-2500), '-₹2,500');
    });

    test('short amounts read as lakhs and crores', () {
      expect(short(850), '₹850');
      expect(short(8500), '₹8.5k');
      expect(short(125000), '₹1.25L');
      expect(short(34000000), '₹3.4Cr');
    });

    test('initials take the first two words', () {
      expect(initials('Meera Krishnan Iyer'), 'MK');
      expect(initials('  priya  '), 'P');
    });
  });

  group('server json', () {
    final m = <String, dynamic>{'a': 3.0, 'b': '7', 'c': true, 'd': null, 'list': [{'x': 1}, 'not a map'], 'strs': ['p', 2]};

    test('numbers are read leniently', () {
      expect(m.integer('a'), 3);
      expect(m.integer('b'), 7);
      expect(m.integer('missing', 9), 9);
      expect(m.number('a'), 3.0);
    });

    test('a null is not the string "null"', () {
      expect(m.strOrNull('d'), isNull);
      expect(m.str('d', 'fallback'), 'fallback');
    });

    test('lists keep only the maps', () {
      expect(m.maps('list'), [{'x': 1}]);
      expect(m.maps('nothing'), isEmpty);
    });

    test('only an exact true is a flag', () {
      expect(m.flag('c'), isTrue);
      expect(m.flag('b'), isFalse);
    });
  });

  group('roles', () {
    HqUser user(String code, Set<String> modules) => HqUser(id: 'u', username: 'u', fullName: 'U', role: HqRole.byCode(code), modules: modules);

    test('a missing role is a Super admin, like the seeded owner', () {
      expect(HqRole.byCode(null), HqRole.super_);
      expect(HqRole.byCode('NOPE'), HqRole.super_);
    });

    test('only Super and Operations change things', () {
      expect(user('SUPER', {'*'}).canWrite, isTrue);
      expect(user('OPS', {'users'}).canWrite, isTrue);
      expect(user('FINANCE', {'finance'}).canWrite, isFalse);
      expect(user('SUPPORT', {'support'}).canWrite, isFalse);
    });

    test('support cannot export, finance can', () {
      expect(user('SUPPORT', {'support'}).canExport, isFalse);
      expect(user('FINANCE', {'finance'}).canExport, isTrue);
    });

    test('a module outside the role is locked, welcome never is', () {
      final u = user('FINANCE', {'finance', 'plans'});
      expect(u.can('finance'), isTrue);
      expect(u.can('users'), isFalse);
      expect(u.can('welcome'), isTrue);
      expect(user('SUPER', {'*'}).can('anything'), isTrue);
    });
  });

  group('csv import', () {
    test('splits rows and cells', () {
      expect(parseCsv('name,mobile\nAnanya,9845012345'), [['name', 'mobile'], ['Ananya', '9845012345']]);
    });

    test('a comma inside quotes stays in the cell, and "" is a quote', () {
      expect(parseCsv('a,"b, c","say ""hi"""'), [['a', 'b, c', 'say "hi"']]);
    });

    test('blank lines and a byte order mark are ignored', () {
      expect(parseCsv('\u{feff}name\r\n\r\nx\r\n'), [['name'], ['x']]);
    });
  });
}
