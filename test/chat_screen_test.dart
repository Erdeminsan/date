import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/chat_screen.dart';

class ChatBackend implements Backend {
  bool failSendOnce = false, failRead = false, failReportOnce = false;
  final reports = <List<String>>[];
  Future<MessagePage>? pendingRead;
  int reads = 0;
  final requests = <String>[];
  ChatMessage? stored;
  @override
  String userId = 'me';
  @override
  Future<MessagePage> messages(String matchId,{String? before,String? after}) async {
    reads++;
    if (failRead) throw Exception('access lost');
    if (pendingRead != null) return pendingRead!;
    return MessagePage(stored == null || after == stored!.id ? [] : [stored!],false);
  }
  @override
  Future<ChatMessage> sendMessage(String matchId,String requestId,String body) async {
    requests.add(requestId);
    stored ??= ChatMessage({'id':'1','sender_id':'me','request_id':requestId,'body':body});
    if (failSendOnce) { failSendOnce = false; throw Exception('response lost'); }
    return stored!;
  }
  @override
  Future<void> reportMessage(String matchId,String messageId,String reason) async {
    reports.add([matchId,messageId,reason]);
    if(failReportOnce){failReportOnce=false;throw Exception('response lost');}
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
void main() {
  Future<void> open(WidgetTester tester,ChatBackend backend) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(backend:backend,connection:const Connection('match','other','Other'))));
    await tester.pumpAndSettle();
  }
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  }
  testWidgets('lost send response retries with the same identity and frozen body', (tester) async {
    final backend = ChatBackend()..failSendOnce = true;
    await open(tester,backend);
    await tester.enterText(find.byType(TextField),'Hello');
    await tester.tap(find.text('Gönder')); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly,isTrue);
    await tester.tap(find.text('Tekrar dene')); await tester.pumpAndSettle();
    expect(backend.requests.length,2);
    expect(backend.requests[0],backend.requests[1]);
    expect(find.text('Hello'),findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,isEmpty);
    await close(tester);
  });
  testWidgets('refresh failure clears history and prevents stale sending', (tester) async {
    final backend = ChatBackend()..stored = ChatMessage({'id':'1','sender_id':'other','request_id':'old','body':'Private'});
    await open(tester,backend); expect(find.text('Private'),findsOneWidget);
    backend.failRead = true;
    await tester.tap(find.byTooltip('Sohbeti yenile')); await tester.pumpAndSettle();
    expect(find.text('Private'),findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Gönder')).onPressed,isNull);
    await close(tester);
  });
  testWidgets('changing account cannot send the old draft', (tester) async {
    final backend = ChatBackend(); await open(tester,backend);
    await tester.enterText(find.byType(TextField),'Old draft');
    backend.userId = 'someone-else';
    await tester.tap(find.text('Gönder')); await tester.pumpAndSettle();
    expect(backend.requests,isEmpty);
    await close(tester);
  });
  testWidgets('background pauses polling and dispose removes its timer', (tester) async {
    final backend = ChatBackend(); await open(tester,backend);
    final count = backend.reads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds:6)); expect(backend.reads,count);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle(); expect(backend.reads,count+1);
    await close(tester); await tester.pump(const Duration(seconds:6)); expect(backend.reads,count+1);
  });
  testWidgets('selected opponent message is previewed and reported with a required reason', (tester) async {
    final b=ChatBackend()..stored=ChatMessage({'id':'8','sender_id':'other','request_id':'old','body':'Selected evidence'});
    await open(tester,b);await tester.tap(find.byKey(const ValueKey('report-message-8')));await tester.pumpAndSettle();
    expect(find.text('Selected evidence'),findsNWidgets(2));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Şikâyeti gönder')).onPressed,isNull);
    await tester.enterText(find.byKey(const ValueKey('message-report-reason')),'Unwanted contact');await tester.pump();
    await tester.tap(find.text('Şikâyeti gönder'));await tester.pumpAndSettle();
    expect(b.reports,[['match','8','Unwanted contact']]);
    expect(find.text('Şikâyetin seçtiğin mesajla birlikte kaydedildi.'),findsOneWidget);
    await close(tester);
  });
  testWidgets('own message has no report action', (tester) async {
    final b=ChatBackend()..stored=ChatMessage({'id':'8','sender_id':'me','request_id':'old','body':'My message'});
    await open(tester,b);expect(find.byTooltip('Mesajı şikâyet et'),findsNothing);await close(tester);
  });
  testWidgets('uncertain report retry preserves the selected message and reason', (tester) async {
    final b=ChatBackend()..failReportOnce=true..stored=ChatMessage({'id':'8','sender_id':'other','request_id':'old','body':'Selected evidence'});
    await open(tester,b);await tester.tap(find.byKey(const ValueKey('report-message-8')));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('message-report-reason')),'Unwanted contact');await tester.pump();
    await tester.tap(find.text('Şikâyeti gönder'));await tester.pumpAndSettle();
    expect(find.textContaining('Şikâyet doğrulanamadı'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report-message-8')));await tester.pumpAndSettle();
    expect(find.text('Unwanted contact'),findsOneWidget);
    await tester.tap(find.text('Şikâyeti gönder'));await tester.pumpAndSettle();
    expect(b.reports.length,2);expect(b.reports[0],b.reports[1]);await close(tester);
  });
  testWidgets('access loss while reporting dismisses dialog and clears private history', (tester) async {
    final b=ChatBackend()..stored=ChatMessage({'id':'8','sender_id':'other','request_id':'old','body':'Selected evidence'});
    await open(tester,b);await tester.tap(find.byKey(const ValueKey('report-message-8')));await tester.pumpAndSettle();
    b.failRead=true;await tester.pump(const Duration(seconds:3));await tester.pumpAndSettle();
    expect(find.text('Selected evidence'),findsNothing);expect(find.text('Şikâyeti gönder'),findsNothing);
    expect(find.byType(ChatScreen),findsOneWidget);expect(b.reports,isEmpty);await close(tester);
  });
  testWidgets('pre-background read cannot restore cleared message history', (tester) async {
    final message=ChatMessage({'id':'8','sender_id':'other','request_id':'old','body':'Stale private message'});
    final b=ChatBackend()..stored=message;await open(tester,b);
    final delayed=Completer<MessagePage>();b.pendingRead=delayed.future;
    await tester.pump(const Duration(seconds:3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);await tester.pump();
    expect(find.text('Stale private message'),findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);await tester.pump();
    b.pendingRead=null;b.stored=null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
    delayed.complete(MessagePage([message],false));await tester.pumpAndSettle();
    expect(find.text('Stale private message'),findsNothing);await close(tester);
  });

}
