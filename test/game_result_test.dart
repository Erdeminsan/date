import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/game_result_screen.dart';
class ResultsBackend implements Backend {
  ResultsBackend(this.fetch);
  final Future<GameResult?> Function(bool) fetch;
  @override
  String get userId => 'me';
  @override
  Future<GameResult?> gameResult(String roomId, {bool finalize = false}) => fetch(finalize);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
GameResult result({String? winner = 'me',String? city,String? interests}) => GameResult({
  'winner_id':winner,'my_score':2,'opponent_score':1,'my_hits':3,'opponent_hits':4,
  'city':city,'interests':interests,
});
void main() {
  for (final staleError in [false, true]) {
    testWidgets('resume ignores stale result or failure: $staleError', (tester) async {
      final old = Completer<GameResult?>();
      var calls = 0;
      final backend = ResultsBackend((_) async {
        if (++calls == 1) return old.future;
        return result(city:'Yeni şehir');
      });
      await tester.pumpWidget(MaterialApp(home:GameResultScreen(backend:backend,roomId:'room')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Şehir: Yeni şehir'), findsOneWidget);
      if (staleError) {
        old.completeError(StateError('old request'));
      } else {
        old.complete(result(city:'Eski şehir'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Şehir: Yeni şehir'), findsOneWidget);
      expect(find.text('Şehir: Eski şehir'), findsNothing);
      expect(find.text('Tekrar dene'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('pending retries finalization then reads persisted result; hides fields on access loss', (tester) async {
    var calls=0;
    final backend=ResultsBackend((finalize) async {
      calls++;
      if(calls==1) { expect(finalize,isTrue); return null; }
      if(calls==2) { expect(finalize,isTrue); return result(city:'İstanbul'); }
      expect(finalize,isFalse); throw StateError('unmatched');
    });
    await tester.pumpWidget(MaterialApp(home:GameResultScreen(backend:backend,roomId:'room')));
    await tester.pumpAndSettle();
    expect(find.textContaining('doğrulanıyor'),findsOneWidget);
    await tester.pump(const Duration(seconds:2)); await tester.pumpAndSettle();
    expect(find.text('Kazandın!'),findsOneWidget); expect(find.text('Şehir: İstanbul'),findsOneWidget);
    expect(find.textContaining('İkinci galibiyetinde'),findsOneWidget);
    await tester.pump(const Duration(seconds:2)); await tester.pumpAndSettle();
    expect(find.text('Şehir: İstanbul'),findsNothing); expect(find.text('Tekrar dene'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('tie shows persisted unlocks without claiming a new reward', (tester) async {
    final backend=ResultsBackend((_) async => result(winner:null,city:'İstanbul',interests:'Tenis'));
    await tester.pumpWidget(MaterialApp(home:GameResultScreen(backend:backend,roomId:'room')));
    await tester.pumpAndSettle();
    expect(find.text('Berabere'),findsOneWidget);expect(find.text('İlgi alanları: Tenis'),findsOneWidget);
    expect(find.text('Yalnız kazanan ilerler. Beraberlik yeni bilgi açmaz.'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
