import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/profile_report_dialog.dart';

class ReportBackend implements Backend {
  String owner = 'owner';
  bool failOnce = false;
  Future<void>? pending;
  final calls = <List<String>>[];
  @override
  String get userId => owner;
  @override
  Future<void> report(String id, String reason, {required String requestId}) async {
    calls.add([id, reason, requestId]);
    if (failOnce) { failOnce = false; throw StateError('Lost response'); }
    await pending;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  Future<void> open(WidgetTester t, ReportBackend b) async {
    await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showDialog<bool>(context: context, builder: (_) => ProfileReportDialog(backend: b, targetId: 'target')),
      child: const Text('Open'))))));
    await t.tap(find.text('Open')); await t.pumpAndSettle();
  }
  Future<void> send(WidgetTester t) async {
    await t.enterText(find.byType(TextField), '  Unwanted contact  '); await t.pump();
    await t.tap(find.text('Gönder')); await t.pump();
  }
  testWidgets('validates reason and retries lost response with identical identity', (t) async {
    final b = ReportBackend()..failOnce = true; await open(t,b);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    await send(t); await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byType(TextField)).readOnly,isTrue);
    await t.tap(find.text('Aynı şikâyeti tekrar dene')); await t.pumpAndSettle();
    expect(b.calls.length,2); expect(b.calls.first,b.calls.last);
    expect(b.calls.first[1],'Unwanted contact');
    expect(find.byType(ProfileReportDialog),findsNothing);
  });
  testWidgets('background invalidates stale completion and preserves retry identity', (t) async {
    final pending = Completer<void>(); final b = ReportBackend()..pending = pending.future;
    await open(t,b); await send(t);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await t.pump();
    pending.complete(); await t.pumpAndSettle();
    expect(find.byType(ProfileReportDialog),findsOneWidget);
    await t.tap(find.text('Aynı şikâyeti tekrar dene')); await t.pumpAndSettle();
    expect(b.calls.length,2); expect(b.calls.first,b.calls.last);
    expect(find.byType(ProfileReportDialog),findsNothing);
  });
  testWidgets('session change cannot send as a different account', (t) async {
    final b = ReportBackend(); await open(t,b); b.owner = 'other'; await send(t); await t.pumpAndSettle();
    expect(b.calls,isEmpty); expect(find.byType(ProfileReportDialog),findsOneWidget);
  });
}
