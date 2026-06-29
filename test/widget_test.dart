import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_app/main.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(const WalletApp());
    expect(find.byType(WalletApp), findsOneWidget);
  });
}