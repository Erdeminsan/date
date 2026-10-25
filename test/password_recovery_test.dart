import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/features/password_recovery.dart';

void main() {
  testWidgets('Mismatched passwords cannot update account', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordRecovery(
          save: (_) async {
            calls++;
          },
          finish: () async {},
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'new-password');
    await tester.enterText(find.byType(TextFormField).at(1), 'different');
    await tester.tap(find.text('Şifreyi kaydet'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Şifreler aynı olmalı.'), findsOneWidget);
  });
  testWidgets('Failed logout retries logout without rewriting password', (
    tester,
  ) async {
    var saves = 0, finishes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordRecovery(
          save: (_) async {
            saves++;
          },
          finish: () async {
            finishes++;
            if (finishes == 1) throw Exception('offline');
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'new-password');
    await tester.enterText(find.byType(TextFormField).at(1), 'new-password');
    await tester.tap(find.text('Şifreyi kaydet'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(finishes, 1);
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Giriş ekranına dön'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(finishes, 2);
  });
  testWidgets('Cancel leaves recovery without changing the password', (tester) async {
    var saves = 0, cancels = 0;
    await tester.pumpWidget(MaterialApp(home: PasswordRecovery(
      save: (_) async { saves++; }, finish: () async {},
      cancel: () async { cancels++; },
    )));
    await tester.tap(find.text('Vazgeç ve girişe dön'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(cancels, 1);
  });

}
