import 'package:flutter_test/flutter_test.dart';
import 'package:pillar_ai/main.dart';
import 'package:pillar_ai/screens/home_screen.dart';

void main() {
  testWidgets('FirstSign app boots to splash then home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FirstSignApp());

    expect(find.byType(SplashScreen), findsOneWidget);

    // Splash holds ~1.2s, then fades and navigates to HomeScreen.
    // Avoid pumpAndSettle — HomeScreen has repeating pulse animations.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(); // complete navigation frame

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
