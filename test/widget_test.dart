import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glucosaathi/screens/home/home_screen.dart';

void main() {
  testWidgets('App renders the redesigned Home Screen with all widgets',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    expect(find.text('GlucoSaathi'), findsOneWidget);
    expect(find.text('Glucose'), findsOneWidget);
    expect(find.text('Active Insulin'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Upload Image'), findsOneWidget);
    expect(find.text('Cooked Dish'), findsOneWidget);
    expect(find.text('Packaged Item'), findsOneWidget);
    expect(find.text('Quick-Log (Frequent Indian Foods)'), findsOneWidget);
  });
}