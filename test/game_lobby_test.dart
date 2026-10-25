import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/game_lobby.dart';

RoomSnapshot state(String? status, {String inviter = 'other'}) => RoomSnapshot({
  'server_now': '2026-10-25T00:00:00Z',
  'room': status == null ? null : {'id': 'room', 'inviter_id': inviter,
    'status': status, 'expires_at': '2026-10-25T00:01:00Z'},
});
class RoomBackend implements Backend {
  RoomBackend(this.fetch);
  final Future<RoomSnapshot> Function(String, String?) fetch;
  @override
  String get userId => 'me';
  @override
  Future<RoomSnapshot> gameRoom(String matchId, {String action = 'read', String? roomId}) => fetch(action, roomId);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
void main() {
  Future<void> open(WidgetTester tester, RoomBackend backend) async {
    await tester.pumpWidget(MaterialApp(home: GameLobby(backend: backend,
      connection: const Connection('match', 'other', 'Other'))));
    await tester.pumpAndSettle();
  }
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }
  testWidgets('incoming invite accepts once and sends the exact room id', (tester) async {
    final pending = Completer<RoomSnapshot>();
    var accepts = 0;
    final backend = RoomBackend((action, room) async {
      if (action == 'accept') { accepts++; expect(room, 'room'); return pending.future; }
      return state('invited');
    });
    await open(tester, backend);
    await tester.tap(find.text('Kabul et')); await tester.pump();
    await tester.tap(find.text('Kabul et')); await tester.pump();
    expect(accepts, 1);
    pending.complete(state('accepted')); await tester.pumpAndSettle();
    expect(find.text('Davet kabul edildi'), findsOneWidget);
    expect(find.text('Kabul et'), findsNothing);
    await close(tester);
  });
  testWidgets('outgoing invitation cannot accept itself; failure clears stale actions', (tester) async {
    var calls = 0;
    await open(tester, RoomBackend((action, room) async {
      if (++calls > 1) throw Exception('offline');
      return state('invited', inviter: 'me');
    }));
    expect(find.text('Kabul et'), findsNothing);
    await tester.tap(find.text('Yenile')); await tester.pumpAndSettle();
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.text('Daveti iptal et'), findsNothing);
    await close(tester);
  });
  testWidgets('background stops polling; resume refreshes; dispose cancels timer', (tester) async {
    var calls = 0;
    await open(tester, RoomBackend((action, room) async { calls++; return state(null); }));
    final initial = calls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 6));
    expect(calls, initial);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, initial + 1);
    await close(tester);
    await tester.pump(const Duration(seconds: 6));
    expect(calls, initial + 1);
  });
}
