import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/app.dart';
import 'package:mereytoi_app/screens/splash/splash_screen.dart';

void main() {
  testWidgets('app boots to the splash screen without crashing', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MereytoiApp()));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The splash screen's navigation is driven by a real Timer
    // (Future.delayed) and its route transition by a ticking
    // AnimationController — both must be flushed with an explicit pump
    // before the test ends, or flutter_test's "Timer still pending" leak
    // check fails even though nothing is actually wrong.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));
  });
}
