import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/member_home.dart';

class UnmatchBackend implements Backend {
  int calls = 0;
  bool fail = false, removed = false;
  @override
  Future<OwnProfile?> profile() async => OwnProfile(const Person(id: 'me', name: 'Me'), DateTime(2000), 'City', '');
  @override
  Future<FeedPage<Person>> discover({FeedCursor? before}) async => const FeedPage([], null);
  @override
  Future<FeedPage<Connection>> matches({FeedCursor? before}) async => FeedPage(removed ? [] : [const Connection('match-id','other','Other')], null);
  @override
  Future<void> unmatch(String id) async {
    expect(id, 'match-id'); calls++;
    if (fail) throw Exception('offline');
    removed = true;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
void main() {
  Future<void> open(WidgetTester tester, UnmatchBackend backend) async {
    await tester.pumpWidget(MaterialApp(home: MemberHome(backend: backend)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eşleşmeler')); await tester.pumpAndSettle();
  }
  Future<void> prompt(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>)); await tester.pumpAndSettle();
    await tester.tap(find.text('Eşleşmeden ayrıl')); await tester.pumpAndSettle();
  }
  testWidgets('cancel is harmless; confirmation removes the match and refreshes', (tester) async {
    final backend = UnmatchBackend(); await open(tester, backend);
    await prompt(tester); await tester.tap(find.text('Vazgeç')); await tester.pumpAndSettle();
    expect(backend.calls, 0); expect(find.text('Other'), findsOneWidget);
    await prompt(tester); await tester.tap(find.text('Eşleşmeden ayrıl')); await tester.pumpAndSettle();
    expect(backend.calls, 1); expect(find.text('Other'), findsNothing);
  });
  testWidgets('failed unmatch keeps the match available for retry', (tester) async {
    final backend = UnmatchBackend()..fail = true; await open(tester, backend);
    await prompt(tester); await tester.tap(find.text('Eşleşmeden ayrıl')); await tester.pumpAndSettle();
    expect(find.text('Other'), findsOneWidget); expect(backend.removed, isFalse);
    backend.fail = false;
    await prompt(tester); await tester.tap(find.text('Eşleşmeden ayrıl')); await tester.pumpAndSettle();
    expect(backend.calls, 2); expect(find.text('Other'), findsNothing);
  });
}
