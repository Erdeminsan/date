import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/photo_report_screen.dart';
import 'package:playmatch/features/photo_evidence_screen.dart';

class PhotoReportBackend implements Backend {
  String owner='owner';
  bool failLoad=false,failOnce=false,allowed=true;
  final reports=<Map<String,String>>[];
  final viewed=<String>[];
  Uint8List photo=Uint8List.fromList(img.encodeJpg(img.Image(width:2,height:2)));
  Future<Uint8List>? pending;
  @override
  String get userId=>owner;
  @override
  Future<Uint8List> downloadPhoto(String path) async {
    if(failLoad)throw StateError('Unavailable');return await (pending??Future.value(photo));
  }
  @override
  Future<void> reportPhoto({required String targetId,required String path,required String requestId,required String reason,required String digest})async{
    reports.add({'target':targetId,'path':path,'request':requestId,'reason':reason,'digest':digest});
    if(failOnce){failOnce=false;throw StateError('Response lost');}
  }
  @override
  Future<Uint8List> moderationPhoto(String reportId)async{viewed.add(reportId);if(!allowed)throw StateError('No access');return await (pending??Future.value(photo));}
  @override
  Future<bool> moderationPhotoAccess(String reportId)async=>allowed;
  @override
  dynamic noSuchMethod(Invocation invocation)=>throw UnimplementedError();
}
void main(){
  Future<void> open(WidgetTester tester,PhotoReportBackend b)async{
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()=>Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>PhotoReportScreen(backend:b,targetId:'target',path:'target/photo.jpg'))),child:const Text('Open'))))));
    await tester.tap(find.text('Open'));await tester.pumpAndSettle();
  }
  Future<void> close(WidgetTester tester)async{await tester.pumpWidget(const SizedBox());}
  testWidgets('photo report requires loaded preview and reason and sends its digest', (tester)async{
    final b=PhotoReportBackend();await open(tester,b);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    await tester.enterText(find.byType(TextField),'Photo violation');await tester.pump();
    await tester.ensureVisible(find.text('Fotoğrafla birlikte gönder'));await tester.tap(find.text('Fotoğrafla birlikte gönder'));await tester.pumpAndSettle();
    expect(b.reports.single['target'],'target');expect(b.reports.single['reason'],'Photo violation');
    expect(b.reports.single['digest'],sha256.convert(b.photo).toString());expect(find.byType(PhotoReportScreen),findsNothing);
    await close(tester);
  });
  testWidgets('uncertain response freezes reason and retries identical request', (tester)async{
    final b=PhotoReportBackend()..failOnce=true;await open(tester,b);
    await tester.enterText(find.byType(TextField),'Photo violation');await tester.pump();
    await tester.ensureVisible(find.text('Fotoğrafla birlikte gönder'));await tester.tap(find.text('Fotoğrafla birlikte gönder'));await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly,isTrue);
    await tester.ensureVisible(find.text('Aynı şikâyeti tekrar dene'));await tester.tap(find.text('Aynı şikâyeti tekrar dene'));await tester.pumpAndSettle();
    expect(b.reports.length,2);expect(b.reports[0],b.reports[1]);await close(tester);
  });
  testWidgets('uncertain request can be confirmed after background without restoring image', (tester)async{
    final b=PhotoReportBackend()..failOnce=true;await open(tester,b);
    await tester.enterText(find.byType(TextField),'Photo violation');await tester.pump();
    await tester.ensureVisible(find.text('Fotoğrafla birlikte gönder'));await tester.tap(find.text('Fotoğrafla birlikte gönder'));await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);await tester.pump();
    expect(find.byType(Image),findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
    expect(find.byType(Image),findsNothing);
    await tester.ensureVisible(find.text('Aynı şikâyeti tekrar dene'));await tester.tap(find.text('Aynı şikâyeti tekrar dene'));await tester.pumpAndSettle();
    expect(b.reports.length,2);expect(b.reports[0],b.reports[1]);await close(tester);
  });
  testWidgets('missing preview cannot be submitted', (tester)async{
    final b=PhotoReportBackend()..failLoad=true;await open(tester,b);
    await tester.enterText(find.byType(TextField),'Photo violation');await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);expect(b.reports,isEmpty);await close(tester);
  });
  testWidgets('case or role access loss clears moderator image', (tester)async{
    final b=PhotoReportBackend();await tester.pumpWidget(MaterialApp(home:PhotoEvidenceScreen(backend:b,reportId:'report')));await tester.pumpAndSettle();
    expect(find.byType(Image),findsOneWidget);expect(b.viewed,['report']);b.allowed=false;
    await tester.pump(const Duration(seconds:5));await tester.pumpAndSettle();
    expect(find.byType(Image),findsNothing);expect(find.textContaining('Fotoğrafa erişilemiyor'),findsOneWidget);await close(tester);
  });
  testWidgets('stale image read cannot restore pre-background evidence', (tester)async{
    final b=PhotoReportBackend(),delayed=Completer<Uint8List>();final old=b.photo;b.pending=delayed.future;
    await tester.pumpWidget(MaterialApp(home:PhotoEvidenceScreen(backend:b,reportId:'report')));await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);await tester.pump();
    b.pending=null;b.photo=Uint8List.fromList(old);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
    delayed.complete(old);await tester.pumpAndSettle();
    final provider=tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    expect(identical(provider.bytes,b.photo),isTrue);await close(tester);
  });
}
