import 'package:flutter_test/flutter_test.dart';
import 'package:algo_terminal/main.dart';

void main() {
  testWidgets('NSE Algo Signal app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const AlgoApp());
    expect(find.text('NSE Algo Signal'), findsOneWidget);
  });
}
