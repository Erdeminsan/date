import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/moderation_screen.dart';
class ModerationBackend implements Backend {
  bool allowed=true,reviewed=false,failSave=false,escalated=false,restricted=false;
  int? savedHours;
  String? sanctionReason,liftReason;
  String? savedId,savedDecision,savedNote;
  @override
  String get userId=>'moderator';
  @override
  Future<bool> moderationAccess()async=>allowed;
  @override
  Future<FeedPage<ModerationReport>> moderationReports({String status='pending',FeedCursor? before})async{
    if(!allowed)throw StateError('not authorized');
    return FeedPage(reviewed?[]:[ModerationReport({'id':'report','reporter_name':'Reporter','reported_name':'Target','reason':'Private report reason','created_at':'2026-01-01','decision':escalated?'escalated':null,'review_note':null})],null);
  }
  @override
  Future<void> reviewReport(String reportId,String decision,String note)async{
    if(failSave)throw StateError('network error');
    savedId=reportId;savedDecision=decision;savedNote=note;reviewed=true;
  }
  @override
  Future<void> suspendReportedAccount(String reportId,int hours,String reason)async{
    if(failSave)throw StateError('network error');
    savedId=reportId;savedHours=hours;sanctionReason=reason;restricted=true;
  }
  @override
  Future<void> liftAccountSanction(String id,String reason)async{
    if(failSave)throw StateError('network error');
    savedId=id;liftReason=reason;restricted=false;
  }
  @override
  Future<FeedPage<ModerationSanction>> moderationSanctions({FeedCursor? before})async{
    if(!allowed)throw StateError('not authorized');
    return FeedPage([ModerationSanction({'id':'sanction','reported_name':'Target','reason':'Restriction evidence',
      'expires_at':'2026-10-27T12:00:00Z','active':restricted,'lift_reason':liftReason})],null);
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
  testWidgets('escalated case requires explicit reason before temporary restriction', (tester)async{
    final b=ModerationBackend()..escalated=true;await open(tester,b);
    await tester.tap(find.text('Süreli kısıtla'));await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Kısıtlamayı onayla')).onPressed,isNull);
    await tester.enterText(find.byType(TextField),'Reviewed violation');await tester.pump();
    await tester.tap(find.text('Kısıtlamayı onayla'));await tester.pumpAndSettle();
    expect(b.savedId,'report');expect(b.savedHours,24);expect(b.sanctionReason,'Reviewed violation');
    expect(find.text('Aktif kısıtlama'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('lifting a restriction records a separate reason', (tester)async{
    final b=ModerationBackend()..restricted=true;await open(tester,b);
    await tester.tap(find.text('Kısıtlamalar'));await tester.pumpAndSettle();
    await tester.tap(find.text('Kısıtlamayı kaldır'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'Appeal accepted');await tester.pump();
    await tester.tap(find.text('Kaldırmayı onayla'));await tester.pumpAndSettle();
    expect(b.savedId,'sanction');expect(b.liftReason,'Appeal accepted');
    expect(find.text('Kısıtlama sona erdi'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('role revocation dismisses restriction confirmation without sending', (tester)async{
    final b=ModerationBackend()..escalated=true;await open(tester,b);
    await tester.tap(find.text('Süreli kısıtla'));await tester.pumpAndSettle();b.allowed=false;
    await tester.pump(const Duration(seconds:5));await tester.pumpAndSettle();
    expect(find.text('Hesabı süreli kısıtla'),findsNothing);expect(b.savedHours,isNull);
    expect(find.text('Private report reason'),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('uncertain restriction response clears data and requires refresh', (tester)async{
    final b=ModerationBackend()..escalated=true..failSave=true;await open(tester,b);
    await tester.tap(find.text('Süreli kısıtla'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'Reviewed violation');await tester.pump();
    await tester.tap(find.text('Kısıtlamayı onayla'));await tester.pumpAndSettle();
    expect(find.textContaining('İşlem doğrulanamadı'),findsOneWidget);expect(find.text('Private report reason'),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

}
