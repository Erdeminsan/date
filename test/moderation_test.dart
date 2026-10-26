import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/moderation_screen.dart';
class ModerationBackend implements Backend {
  bool allowed=true,reviewed=false,failSave=false;
  String? savedId,savedDecision,savedNote;
  @override
  String get userId=>'moderator';
  @override
  Future<bool> moderationAccess()async=>allowed;
  @override
  Future<FeedPage<ModerationReport>> moderationReports({String status='pending',FeedCursor? before})async{
    if(!allowed)throw StateError('not authorized');
    return FeedPage(reviewed?[]:[ModerationReport({'id':'report','reporter_name':'Reporter','reported_name':'Target','reason':'Private report reason','created_at':'2026-01-01','decision':null,'review_note':null})],null);
  }
  @override
  Future<void> reviewReport(String reportId,String decision,String note)async{
    if(failSave)throw StateError('network error');
    savedId=reportId;savedDecision=decision;savedNote=note;reviewed=true;
  }
  @override
  dynamic noSuchMethod(Invocation invocation)=>throw UnimplementedError();
}
void main(){
  Future<void> open(WidgetTester tester,ModerationBackend b)async{
    await tester.pumpWidget(MaterialApp(home:ModerationScreen(backend:b)));await tester.pumpAndSettle();
  }
  testWidgets('ordinary account sees no report data', (tester)async{
    await open(tester,ModerationBackend()..allowed=false);
    expect(find.text('Private report reason'),findsNothing);expect(find.textContaining('erişilemiyor'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('review requires a reason and sends the selected case only', (tester)async{
    final b=ModerationBackend();await open(tester,b);
    await tester.tap(find.text('İncele'));await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Kararı kaydet')).onPressed,isNull);
    await tester.enterText(find.byType(TextField),'Reviewed evidence');await tester.pump();
    await tester.tap(find.text('Kararı kaydet'));await tester.pumpAndSettle();
    expect(b.savedId,'report');expect(b.savedDecision,'dismissed');expect(b.savedNote,'Reviewed evidence');
    expect(find.text('Private report reason'),findsNothing);expect(find.text('Bu listede şikâyet yok.'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('revoked role clears reports and dismisses an open review dialog', (tester)async{
    final b=ModerationBackend();await open(tester,b);
    await tester.tap(find.text('İncele'));await tester.pumpAndSettle();b.allowed=false;
    await tester.pump(const Duration(seconds:5));await tester.pumpAndSettle();
    expect(find.text('Private report reason'),findsNothing);expect(find.text('Şikâyet kararı'),findsNothing);
    expect(find.byType(ModerationScreen),findsOneWidget);expect(b.savedId,isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('uncertain save clears stale data and offers a refresh', (tester)async{
    final b=ModerationBackend()..failSave=true;await open(tester,b);
    await tester.tap(find.text('İncele'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'Reviewed evidence');await tester.pump();
    await tester.tap(find.text('Kararı kaydet'));await tester.pumpAndSettle();
    expect(find.textContaining('Karar doğrulanamadı'),findsOneWidget);expect(find.text('Private report reason'),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
