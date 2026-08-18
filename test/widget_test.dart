import 'package:flutter_test/flutter_test.dart';

import 'package:glucosaathi/main.dart';

void main() {
  testWidgets('App boots to the Food Recognition screen', (tester) async {
    await tester.pumpWidget(const GlucoSaathiApp());

    expect(find.text('GlucoSaathi - Food Recognition'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Upload Image'), findsOneWidget);
  });
}