import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/chat_screen.dart';

class ChatBackend implements Backend {
  bool failSendOnce = false, failRead = false;
  int reads = 0;
  final requests = <String>[];
  ChatMessage? stored;
  @override
  String userId = 'me';
  @override
  Future<MessagePage> messages(String matchId,{String? before,String? after}) async {
    reads++;
    if (failRead) throw Exception('access lost');
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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds:6)); expect(backend.reads,count);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle(); expect(backend.reads,count+1);
    await close(tester); await tester.pump(const Duration(seconds:6)); expect(backend.reads,count+1);
  });
}
