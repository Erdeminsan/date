import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/main.dart';

void main() {
  testWidgets('Demo başlangıcı ve eşleşme akışı', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const PlayMatchApp());
    await tester.enterText(find.byType(TextField), 'Erdem');
    final checkbox = find.byType(Checkbox);
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue,
        reason: '18+ onayı seçilmiş olmalı.');
    final startButton = find.widgetWithText(FilledButton, 'Demoyu keşfet');
    await tester.ensureVisible(startButton);
    await tester.pumpAndSettle();
    await tester.tap(startButton);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    final likeButton = find.widgetWithText(FilledButton, '♡ Beğen');
    await tester.scrollUntilVisible(likeButton, 150,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(likeButton);
    await tester.pumpAndSettle();
    expect(find.text('Deniz · Demo'), findsOneWidget);
    expect(find.text('Sky Hop oyna'), findsOneWidget);
  });
}
