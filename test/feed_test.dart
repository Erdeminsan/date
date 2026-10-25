import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/member_home.dart';

const cursor = FeedCursor('2020-01-01T00:00:00.123456Z', 'first');
class FakeBackend extends Backend {
  FakeBackend(this.fetch) : super(SupabaseClient('https://example.test', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final Future<FeedPage<Person>> Function(FeedCursor?) fetch;
  @override
  Future<OwnProfile?> profile() async => OwnProfile(
    const Person(id: 'owner', name: 'Owner'), DateTime(2000), 'City', '',
  );
  @override
  Future<FeedPage<Person>> discover({FeedCursor? before}) => fetch(before);
  @override
  Future<FeedPage<Connection>> matches({FeedCursor? before}) async => const FeedPage([], null);
}

void main() {
  test('Look-ahead is not displayed and cursor keeps full timestamp precision', () {
    final rows = List.generate(21, (i) => {
      'id': '$i', 'display_name': 'Person $i', 'created_at': cursor.createdAt,
    });
    final page = decodeFeedPage<Person>(rows, Person.fromJson);
    expect(page.items.length, 20);
    expect(page.next!.id, '19');
    expect(page.next!.createdAt, cursor.createdAt);
    expect(decodeFeedPage<Person>(rows.take(20).toList(), Person.fromJson).next, isNull);
    expect(decodeFeedPage<Person>([], Person.fromJson).next, isNull);
  });

  Future<void> open(WidgetTester tester, FakeBackend backend) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); await backend.client.dispose(); });
    await tester.pumpWidget(MaterialApp(home: MemberHome(backend: backend)));
    await tester.pumpAndSettle();
  }

  testWidgets('Next-page failure preserves items and permits a retry without duplicates', (tester) async {
    var attempts = 0;
    final backend = FakeBackend((before) async {
      if (before == null) return const FeedPage([Person(id:'first',name:'First')],cursor);
      expect(before.createdAt, cursor.createdAt);
      if (++attempts == 1) throw Exception('offline');
      return const FeedPage([Person(id:'first',name:'First'),Person(id:'second',name:'Second')],null);
    });
    await open(tester, backend);
    await tester.ensureVisible(find.text('Daha fazla profil'));
    await tester.tap(find.text('Daha fazla profil'));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Daha fazla profil'), findsOneWidget);
    await tester.tap(find.text('Daha fazla profil'));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Daha fazla profil'), findsNothing);
  });

  testWidgets('Refresh discards an older pending next page', (tester) async {
    final pending = Completer<FeedPage<Person>>();
    var firstPages = 0;
    final backend = FakeBackend((before) async {
      if (before != null) return pending.future;
      firstPages++;
      return firstPages == 1
        ? const FeedPage([Person(id:'first',name:'First')],cursor)
        : const FeedPage([Person(id:'fresh',name:'Fresh')],null);
    });
    await open(tester, backend);
    await tester.ensureVisible(find.text('Daha fazla profil'));
    await tester.tap(find.text('Daha fazla profil'));
    await tester.pump();
    await tester.tap(find.byTooltip('Yenile'));
    await tester.pumpAndSettle();
    pending.complete(const FeedPage([Person(id:'stale',name:'Stale')],null));
    await tester.pumpAndSettle();
    expect(find.text('Fresh'), findsOneWidget);
    expect(find.text('Stale'), findsNothing);
  });
}
