import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/features/account_settings.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Future<void> Function(String) delete,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showDialog<bool>(
                        context: context,
                        builder:
                            (_) => DeleteAccountDialog(deleteAccount: delete),
                      ),
                  child: const Text('Open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Deletion needs both password and exact confirmation', (
    tester,
  ) async {
    var calls = 0;
    await open(tester, (_) async {
      calls++;
    });
    await tester.tap(find.text('Kalıcı olarak sil'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.enterText(find.byType(TextFormField).at(0), 'password123');
    await tester.enterText(find.byType(TextFormField).at(1), 'yes');
    await tester.tap(find.text('Kalıcı olarak sil'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.enterText(find.byType(TextFormField).at(1), 'SİL');
    await tester.tap(find.text('Kalıcı olarak sil'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(DeleteAccountDialog), findsNothing);
  });

  testWidgets('Cancel never requests deletion', (tester) async {
    var calls = 0;
    await open(tester, (_) async {
      calls++;
    });
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(DeleteAccountDialog), findsNothing);
  });

  testWidgets('Pending deletion cannot double-submit; failure stays open', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await open(tester, (_) {
      calls++;
      return pending.future;
    });
    await tester.enterText(find.byType(TextFormField).at(0), 'password123');
    await tester.enterText(find.byType(TextFormField).at(1), 'SİL');
    await tester.tap(find.text('Kalıcı olarak sil'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.completeError(Exception('network unavailable'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(DeleteAccountDialog), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
