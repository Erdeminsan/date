import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('18th birthday is required, not just the birth year', () {
    final today = DateTime(2026, 10, 25);
    expect(isAdult(DateTime(2008, 10, 25), today), isTrue);
    expect(isAdult(DateTime(2008, 10, 26), today), isFalse);
    expect(isAdult(DateTime(2008, 10, 24), today), isTrue);
    expect(isAdult(DateTime(2030, 1, 1), today), isFalse);
  });
  test('Missing schema is actionable without leaking raw errors', () {
    expect(
      friendlyError(
        const PostgrestException(message: 'schema dump', code: 'PGRST205'),
      ),
      contains('migration'),
    );
    expect(friendlyError(Exception('token=secret')), isNot(contains('secret')));
  });
  test('Public profile model contains only discoverable fields', () {
    final p = Person.fromJson({
      'id': 'abc',
      'display_name': 'Deniz',
      'discoverable': false,
    });
    expect(p.name, 'Deniz');
    expect(p.visible, isFalse);
  });
}
