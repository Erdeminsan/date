import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/backend/repository.dart';
import 'package:playmatch/features/discovery_preferences_screen.dart';
class PreferencesBackend implements Backend {
  bool failLoad=false,failSave=false;
  int calls=0;
  int? min,max;
  @override
  String get userId=>'me';
  @override
  Future<DiscoveryPreferences> discoveryPreferences() async {
    if(failLoad)throw StateError('offline');
    return DiscoveryPreferences({'min_age':25,'max_age':40});
  }
  @override
  Future<void> saveDiscoveryPreferences(int minAge,int? maxAge,{required String expectedUserId}) async {
    expect(expectedUserId,'me');calls++;min=minAge;max=maxAge;
    if(failSave)throw StateError('offline');
  }
  @override
  dynamic noSuchMethod(Invocation invocation)=>throw UnimplementedError();
}
void main(){
  testWidgets('loads saved range, changes it and keeps the draft after failed save', (tester) async {
    final b=PreferencesBackend()..failSave=true;
    await tester.pumpWidget(MaterialApp(home:DiscoveryPreferencesScreen(backend:b)));await tester.pumpAndSettle();
    expect(find.text('25 – 40 yaş'),findsOneWidget);
    tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(const RangeValues(30,45));await tester.pump();
    await tester.tap(find.text('Kaydet'));await tester.pumpAndSettle();
    expect(b.min,30);expect(b.max,45);expect(find.text('30 – 45 yaş'),findsOneWidget);
    expect(find.textContaining('kaydedilemedi'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('all-adults reset submits no upper age bound', (tester) async {
    final b=PreferencesBackend()..failSave=true;
    await tester.pumpWidget(MaterialApp(home:DiscoveryPreferencesScreen(backend:b)));await tester.pumpAndSettle();
    await tester.tap(find.text('Tüm yetişkinler'));await tester.pump();
    await tester.tap(find.text('Kaydet'));await tester.pumpAndSettle();
    expect(b.min,18);expect(b.max,isNull);await tester.pumpWidget(const SizedBox());
  });
  testWidgets('successful save returns true so discovery resets its cursor', (tester) async {
    final b=PreferencesBackend();bool? saved;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:() async {saved=await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>DiscoveryPreferencesScreen(backend:b)));},
      child:const Text('Aç'))))));
    await tester.tap(find.text('Aç'));await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));await tester.pumpAndSettle();
    expect(saved,isTrue);expect(b.min,25);expect(b.max,40);expect(find.text('Keşfet tercihleri'),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed initial load cannot overwrite stored preferences with defaults', (tester) async {
    final b=PreferencesBackend()..failLoad=true;
    await tester.pumpWidget(MaterialApp(home:DiscoveryPreferencesScreen(backend:b)));await tester.pumpAndSettle();
    expect(find.text('Kaydet'),findsNothing);expect(b.calls,0);
    b.failLoad=false;await tester.tap(find.text('Yeniden yükle'));await tester.pumpAndSettle();
    expect(find.text('25 – 40 yaş'),findsOneWidget);await tester.pumpWidget(const SizedBox());
  });
}
