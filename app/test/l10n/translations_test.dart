import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('en.json and ms.json exist, parse, and have matching key sets', () {
    final enFile = File('assets/translations/en.json');
    final msFile = File('assets/translations/ms.json');

    expect(enFile.existsSync(), isTrue, reason: 'assets/translations/en.json missing');
    expect(msFile.existsSync(), isTrue, reason: 'assets/translations/ms.json missing');

    final en = jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
    final ms = jsonDecode(msFile.readAsStringSync()) as Map<String, dynamic>;

    expect(en.keys.toSet(), equals(ms.keys.toSet()),
        reason: 'en.json and ms.json must have identical keys');
    expect(en.containsKey('app_name'), isTrue);
    expect(en['app_name'], equals('renly'));
    expect(ms['app_name'], equals('renly'));
  });
}
