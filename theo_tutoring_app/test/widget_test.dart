import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/login_page.dart';
import 'package:theo_tutoring_app/main.dart';

void main() {
  testWidgets('app opens on the login screen', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
