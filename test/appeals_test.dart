import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/account_access_gate.dart';
import 'package:playmatch/features/appeals_screen.dart';

class AppealBackend implements Backend {
  bool restricted = true, allowed = true, submitted = false, failSave = false;
  String owner = 'owner';
  String? savedId, savedBody, savedDecision, response;
  Future<bool>? nextStatus;
  @override
  String get userId => owner;
  @override
  Future<bool> accountRestricted() async => await (nextStatus ?? Future.value(restricted));
  @override
  Future<bool> moderationAccess() async => allowed;
  SanctionAppeal row({bool moderator = false}) => SanctionAppeal({
    'id': moderator ? 'appeal' : 'sanction', 'sanction_id': 'sanction',
    'appeal_id': submitted || moderator ? 'appeal' : null, 'expires_at': '2026-10-28T12:00:00Z',
    'active': restricted, 'body': submitted || moderator ? 'Please reconsider' : null,
    'decision': savedDecision, 'response': response, 'display_name': moderator ? 'Target' : null,
    'internal_reason': moderator ? 'Private evidence' : null,
  });
  @override
  Future<FeedPage<SanctionAppeal>> ownSanctions({FeedCursor? before}) async => FeedPage([row()], null);
  @override
  Future<FeedPage<SanctionAppeal>> moderationAppeals({bool reviewed = false, FeedCursor? before}) async {
    if (!allowed) throw StateError('Access lost');
    return FeedPage([row(moderator: true)], null);
  }
  @override
  Future<void> submitAppeal(String sanctionId, String body) async {
    if (failSave) throw StateError('Network error');
    savedId = sanctionId; savedBody = body; submitted = true;
  }
  @override
  Future<void> reviewAppeal(String appealId, String decision, String message) async {
    savedId = appealId; savedDecision = decision; response = message;
  }
  @override
  Future<void> signOutLocal() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  Future<void> open(WidgetTester tester, AppealBackend b, {bool moderator = false}) async {
    await tester.pumpWidget(MaterialApp(home: AppealsScreen(backend: b, moderator: moderator)));
    await tester.pumpAndSettle();
  }
  testWidgets('self appeal requires text and submits only the owned sanction', (tester) async {
    final b = AppealBackend(); await open(tester, b);
    expect(find.textContaining('Private evidence'), findsNothing);
    await tester.tap(find.text('İtiraz et')); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'İtirazı gönder')).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Please reconsider'); await tester.pump();
    await tester.tap(find.text('İtirazı gönder')); await tester.pumpAndSettle();
    expect(b.savedId, 'sanction'); expect(b.savedBody, 'Please reconsider');
    expect(find.text('İtiraz inceleme bekliyor.'), findsOneWidget);
    expect(find.text('İtiraz et'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('moderator acceptance sends a user-visible response', (tester) async {
    final b = AppealBackend(); await open(tester, b, moderator: true);
    await tester.tap(find.text('İtirazı incele')); await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>)); await tester.pumpAndSettle();
    await tester.tap(find.text('İtirazı kabul et').last); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Your appeal is accepted'); await tester.pump();
    await tester.tap(find.text('Yanıtı kaydet')); await tester.pumpAndSettle();
    expect(b.savedId, 'appeal'); expect(b.savedDecision, 'lifted'); expect(b.response, 'Your appeal is accepted');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('revoked moderator access clears appeal data and open dialog', (tester) async {
    final b = AppealBackend(); await open(tester, b, moderator: true);
    await tester.tap(find.text('İtirazı incele')); await tester.pumpAndSettle(); b.allowed = false;
    await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();
    expect(find.text('İtiraz kararı'), findsNothing); expect(find.textContaining('Private evidence'), findsNothing);
    expect(find.byType(AppealsScreen), findsOneWidget); expect(b.savedId, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('uncertain submission clears data and asks for refresh', (tester) async {
    final b = AppealBackend()..failSave = true; await open(tester, b);
    await tester.tap(find.text('İtiraz et')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Please reconsider'); await tester.pump();
    await tester.tap(find.text('İtirazı gönder')); await tester.pumpAndSettle();
    expect(find.textContaining('İşlem doğrulanamadı'), findsOneWidget); expect(find.text('Aktif kısıtlama'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('access gate removes covered private routes and dialogs on restriction', (tester) async {
    final b = AppealBackend()..restricted = false;
    await tester.pumpWidget(MaterialApp(home: AccountAccessGate(backend: b, memberBuilder: (context) => Scaffold(
      body: TextButton(onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (context) => Scaffold(
        body: TextButton(onPressed: () => showDialog<void>(useRootNavigator: false, context: context,
          builder: (_) => const AlertDialog(content: Text('Private dialog'))), child: const Text('Private chat')),
      ))), child: const Text('Open chat')),
    ))));
    await tester.pumpAndSettle(); await tester.tap(find.text('Open chat')); await tester.pumpAndSettle();
    await tester.tap(find.text('Private chat')); await tester.pumpAndSettle();
    b.restricted = true; await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();
    expect(find.text('Private dialog', skipOffstage: false), findsNothing);
    expect(find.text('Private chat', skipOffstage: false), findsNothing);
    expect(find.text('Hesabın geçici olarak kısıtlı.'), findsOneWidget);
    b.restricted = false; await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();
    expect(find.text('Open chat'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('stale pre-background response cannot reopen restricted navigation', (tester) async {
    final b = AppealBackend()..restricted = false;
    await tester.pumpWidget(MaterialApp(home: AccountAccessGate(backend: b,
      memberBuilder: (_) => const Scaffold(body: Text('Private home')))));
    await tester.pumpAndSettle();
    final delayed = Completer<bool>(); b.nextStatus = delayed.future;
    await tester.pump(const Duration(seconds: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); await tester.pump();
    expect(find.text('Private home'), findsNothing);
    b.nextStatus = null; b.restricted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pumpAndSettle();
    delayed.complete(false); await tester.pumpAndSettle();
    expect(find.text('Private home', skipOffstage: false), findsNothing);
    expect(find.text('Hesabın geçici olarak kısıtlı.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('access-check failure discards authenticated content', (tester) async {
    final b = AppealBackend()..restricted = false;
    await tester.pumpWidget(MaterialApp(home: AccountAccessGate(backend: b,
      memberBuilder: (_) => const Scaffold(body: Text('Private home')))));
    await tester.pumpAndSettle();
    final failed = Completer<bool>(); b.nextStatus = failed.future;
    await tester.pump(const Duration(seconds: 5));
    failed.completeError(StateError('Offline')); await tester.pumpAndSettle();
    expect(find.text('Private home', skipOffstage: false), findsNothing);
    expect(find.textContaining('Hesap durumu doğrulanamadı'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
