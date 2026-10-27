import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/member_home.dart';
class LiveBackend implements Backend {
  List<Connection> rows = [const Connection('old','other','Old match')];
  int calls = 0;
  bool fail = false;
  Completer<FeedPage<Connection>>? pending;
  final cursors = <String?>[];
  String currentUser = 'me';
  @override
  String get userId => currentUser;
  @override
  Future<OwnProfile?> profile() async => OwnProfile(const Person(id:'me',name:'Me'),DateTime(2000),'City','');
  @override
  Future<FeedPage<Person>> discover({FeedCursor? before}) async => const FeedPage([],null);
  @override
  Future<FeedPage<Connection>> matches({FeedCursor? before}) async {
    calls++; cursors.add(before?.id);
    if(fail) throw StateError('offline');
    if(pending!=null) return pending!.future;
    final offset=before==null?0:rows.indexWhere((r)=>r.id==before.id)+1;
    final page=rows.skip(offset).take(20).toList();
    return FeedPage(page,offset+page.length<rows.length?FeedCursor('2026-01-01',page.last.id):null);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
void main() {
  Future<void> open(WidgetTester tester,LiveBackend backend) async {
    addTearDown(() async { await tester.pumpWidget(const SizedBox()); });
    await tester.pumpWidget(MaterialApp(home:MemberHome(backend:backend)));
    await tester.pumpAndSettle();await tester.tap(find.text('Eşleşmeler'));await tester.pumpAndSettle();
  }
  testWidgets('poll replaces removed matches, adds new ones, clears failures and recovers', (tester) async {
    final b=LiveBackend();await open(tester,b);
    b.rows=[const Connection('new','new-user','New match')];
    await tester.pump(const Duration(seconds:5));await tester.pumpAndSettle();
    expect(find.text('Old match'),findsNothing);expect(find.text('New match'),findsOneWidget);
    b.fail=true;await tester.pump(const Duration(seconds:5));await tester.pumpAndSettle();
    expect(find.text('New match'),findsNothing);expect(find.textContaining('güncellenemedi'),findsOneWidget);
    b.fail=false;await tester.pump(const Duration(seconds:5));await tester.pumpAndSettle();
    expect(find.text('New match'),findsOneWidget);
  });
  testWidgets('background invalidates pending refresh and resume fetches fresh data', (tester) async {
    final b=LiveBackend();await open(tester,b);
    final pending=Completer<FeedPage<Connection>>();b.pending=pending;
    await tester.pump(const Duration(seconds:5));final calls=b.calls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds:10));expect(b.calls,calls);
    b.pending=null;b.rows=[const Connection('fresh','other','Fresh match')];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();pending.complete(const FeedPage([Connection('stale','other','Stale match')],null));await tester.pumpAndSettle();
    expect(find.text('Fresh match'),findsOneWidget);expect(find.text('Stale match'),findsNothing);
  });
  testWidgets('other tabs and covered routes pause polling; account change clears matches', (tester) async {
    final b=LiveBackend();await open(tester,b);final calls=b.calls;
    await tester.tap(find.text('Keşfet'));await tester.pump(const Duration(seconds:10));expect(b.calls,calls);
    await tester.tap(find.text('Eşleşmeler'));await tester.pumpAndSettle();
    final navigator=Navigator.of(tester.element(find.byType(MemberHome)));
    navigator.push<void>(MaterialPageRoute(builder:(_)=>const Scaffold(body:Text('Covered'))));await tester.pumpAndSettle();
    final covered=b.calls;await tester.pump(const Duration(seconds:10));expect(b.calls,covered);
    navigator.pop();await tester.pumpAndSettle();b.currentUser='changed';
    await tester.pump(const Duration(seconds:5));await tester.pumpAndSettle();expect(find.text('Old match'),findsNothing);
  });
  testWidgets('refresh rewalks the loaded window and uses its new pagination cursor', (tester) async {
    final b=LiveBackend()..rows=List.generate(25,(i)=>Connection('id$i','u$i','Match $i'));
    await open(tester,b);
    await tester.scrollUntilVisible(find.text('Daha fazla eşleşme'),400);await tester.tap(find.text('Daha fazla eşleşme'));await tester.pumpAndSettle();
    expect(b.cursors.last,'id19');
    b.rows=[const Connection('new','new','Newest'),...b.rows.where((r)=>r.id!='id23')];
    b.cursors.clear();await tester.pump(const Duration(seconds:5));await tester.pumpAndSettle();
    expect(b.cursors,[null,'id18']);
  });
}
