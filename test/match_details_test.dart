import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/match_details_screen.dart';
class DetailsBackend implements Backend {
  DetailsBackend(this.fetch);
  final Future<MatchUnlocks> Function() fetch;
  String currentUser = 'me';
  @override
  String get userId => currentUser;
  @override
  Future<MatchUnlocks> matchUnlocks(String matchId) { expect(matchId,'match'); return fetch(); }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
MatchUnlocks details(int level) => MatchUnlocks({'unlock_level':level,'city':level>0?'İstanbul':null,'interests':level>1?'Tenis':null});
void main() {
  Future<void> open(WidgetTester tester, DetailsBackend backend) async {
    await tester.pumpWidget(MaterialApp(home:MatchDetailsScreen(backend:backend,connection:const Connection('match','other','Other'))));
    await tester.pumpAndSettle();
  }
  testWidgets('locked fields update and are erased when access is revoked', (tester) async {
    var calls=0;
    await open(tester,DetailsBackend(() async {
      calls++; if(calls==1)return details(0); if(calls==2)return details(2); throw StateError('blocked');
    }));
    expect(find.textContaining('İlk galibiyetinde'),findsOneWidget);
    await tester.pump(const Duration(seconds:3));await tester.pumpAndSettle();
    expect(find.text('Şehir: İstanbul'),findsOneWidget);expect(find.text('İlgi alanları: Tenis'),findsOneWidget);
    await tester.pump(const Duration(seconds:3));await tester.pumpAndSettle();
    expect(find.text('Şehir: İstanbul'),findsNothing);expect(find.textContaining('Bilgiler alınamadı'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('background hides data and stale response cannot restore it after resume', (tester) async {
    final pending=Completer<MatchUnlocks>();var calls=0;
    await open(tester,DetailsBackend(() async { calls++; return calls==2?pending.future:details(calls==1?2:0); }));
    await tester.tap(find.text('Yenile'));await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();expect(find.text('Şehir: İstanbul'),findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();pending.complete(details(2));await tester.pumpAndSettle();
    expect(find.text('Şehir: İstanbul'),findsNothing);expect(find.textContaining('İlk galibiyetinde'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('a different account cannot populate a previous account screen', (tester) async {
    final backend=DetailsBackend(() async=>details(2));await open(tester,backend);
    backend.currentUser='changed';await tester.tap(find.text('Yenile'));await tester.pumpAndSettle();
    expect(find.text('Şehir: İstanbul'),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
