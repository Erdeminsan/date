import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/features/auth_panel.dart';

void main() {
  Future<void> prepare(WidgetTester tester, Authenticate authenticate) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AuthPanel(authenticate: authenticate, resend: (_) async {}),
      ),
    );
  }

  testWidgets('Invalid email does not contact backend', (tester) async {
    var calls = 0;
    await prepare(tester, (_, __, ___) async {
      calls++;
      return null;
    });
    await tester.enterText(find.byType(TextFormField).at(0), 'bad');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Giriş yap'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Geçerli bir e-posta gir.'), findsOneWidget);
  });
  testWidgets('Signup requires adult consent and shows confirmation message', (
    tester,
  ) async {
    var calls = 0;
    await prepare(tester, (email, password, signup) async {
      calls++;
      expect(signup, isTrue);
      expect(email, 'test@example.com');
      return 'E-postanı doğrula';
    });
    await tester.tap(find.text('Yeni hesap oluştur'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'test@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Hesap oluştur'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Hesap oluştur'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('E-postanı doğrula'), findsOneWidget);
  });
  testWidgets(
    'Pending login disables duplicate submits and restores after error',
    (tester) async {
      final pending = Completer<String?>();
      var calls = 0;
      await prepare(tester, (_, __, ___) {
        calls++;
        return pending.future;
      });
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'test@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Giriş yap'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      pending.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byKey(const Key('auth-notice')), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('Reset password needs email but not an existing password', (
    tester,
  ) async {
    final emails = <String>[];
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AuthPanel(
          authenticate: (_, __, ___) async => null,
          resend: (_) async {},
          resetPassword: (email) async {
            emails.add(email);
          },
        ),
      ),
    );
    await tester.ensureVisible(find.text('Şifremi unuttum'));
    await tester.tap(find.text('Şifremi unuttum'));
    await tester.pumpAndSettle();
    expect(emails, isEmpty);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'test@example.com',
    );
    await tester.ensureVisible(find.text('Şifremi unuttum'));
    await tester.tap(find.text('Şifremi unuttum'));
    await tester.pumpAndSettle();
    expect(emails, ['test@example.com']);
    expect(find.textContaining('Uygun bir hesap varsa'), findsOneWidget);
  });
}
