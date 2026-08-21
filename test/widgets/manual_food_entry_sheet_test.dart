import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:glucosaathi/models/logged_meal_entry.dart';
import 'package:glucosaathi/widgets/manual_food_entry_sheet.dart';

const String _png1x1Base64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Future<File> _createPngFile([String name = 'barcode.png']) async {
  final dir = await Directory.systemTemp.createTemp('barcode_test');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(base64Decode(_png1x1Base64));
  return file;
}

Future<T> _createInTest<T>(WidgetTester tester, Future<T> Function() create) =>
    tester.runAsync<T>(create).then((value) => value!);

void main() {
  group('ManualFoodEntrySheet Widget Tests', () {
    testWidgets('renders Tab A (Cooked Dish) with default values & real-time carbs',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      LoggedMealEntry? loggedEntry;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualFoodEntrySheet(
              initialTab: 0,
              currentGlucose: 120,
              activeInsulin: 1.5,
              onMealLogged: (entry) => loggedEntry = entry,
            ),
          ),
        ),
      );

      // Verify header and tabs
      expect(find.text('Manual Food Entry'), findsOneWidget);
      expect(find.text('Cooked Dish (INDB)'), findsOneWidget);
      expect(find.text('Packaged Item'), findsOneWidget);

      // Verify Tab A fields
      expect(find.text('Search Indian Dish (INDB / IFCT)'), findsOneWidget);
      expect(find.text('Household Portion Unit'), findsOneWidget);
      expect(find.text('Quantity'), findsOneWidget);
      expect(find.text('High Fat/Protein Meal (Heavy/Oily)'), findsOneWidget);

      // Verify Footer elements
      expect(find.text('TOTAL NET CARBS'), findsOneWidget);
      expect(find.textContaining('Decision support only'), findsOneWidget);
      expect(find.text('Log Carbs & Predict Risk'), findsOneWidget);

      // Verify initial total net carbs for 1 Medium Roti (18.4g total - 4.0g fiber = 14.4g net)
      expect(find.text('14.4'), findsOneWidget);
      expect(find.text('Total: 18.4g'), findsOneWidget);

      // Increase quantity with stepper (+)
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // Quantity should become 1.5 -> carbs should be 1.5 * 18.4 = 27.6g (net: 21.6g)
      expect(find.text('1.5'), findsOneWidget);
      expect(find.text('21.6'), findsOneWidget);
      expect(find.text('Total: 27.6g'), findsOneWidget);

      // Toggle High Fat/Protein
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Tap Log Carbs & Predict Risk
      await tester.tap(find.text('Log Carbs & Predict Risk'));
      await tester.pumpAndSettle();

      expect(loggedEntry, isNotNull);
      expect(loggedEntry!.entryType, 'cooked');
      expect(loggedEntry!.isHighFatProtein, isTrue);
      expect(loggedEntry!.netCarbsGrams, closeTo(21.6, 0.01));
    });

    testWidgets(
        'renders Tab B (Packaged Item), opens Camera scanner, and auto-populates fields',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final file = await _createInTest(tester, _createPngFile);
      LoggedMealEntry? loggedEntry;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualFoodEntrySheet(
              initialTab: 1,
              currentGlucose: 120,
              activeInsulin: 1.5,
              pickImage: (_) async => XFile(file.path),
              onMealLogged: (entry) => loggedEntry = entry,
            ),
          ),
        ),
      );

      // Verify Tab B fields
      expect(find.text('Scan Barcode / QR Code'), findsOneWidget);
      expect(find.text('Item Name'), findsOneWidget);

      // Tap Scanner button
      await tester.tap(find.text('Scan Barcode / QR Code'));
      await tester.pumpAndSettle();

      expect(find.text('Open Camera Scanner'), findsOneWidget);

      // Tap Open Camera Scanner
      await tester.tap(find.text('Open Camera Scanner'));
      await tester.pumpAndSettle();

      // Verify scanned photo banner and fields populated
      expect(find.text('Scanned Barcode / Package'), findsOneWidget);
      expect(find.textContaining('NutriChoice Digestive'), findsWidgets);

      // Tap Log Carbs & Predict Risk
      await tester.tap(find.text('Log Carbs & Predict Risk'));
      await tester.pumpAndSettle();

      expect(loggedEntry, isNotNull);
      expect(loggedEntry!.entryType, 'packaged');
    });

    testWidgets(
        'renders Tab B (Packaged Item), selects preset, and calculates net carbs',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      LoggedMealEntry? loggedEntry;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualFoodEntrySheet(
              initialTab: 1,
              currentGlucose: 120,
              activeInsulin: 1.5,
              onMealLogged: (entry) => loggedEntry = entry,
            ),
          ),
        ),
      );

      // Test Barcode Scan Options Modal
      await tester.tap(find.text('Scan Barcode / QR Code'));
      await tester.pumpAndSettle();

      expect(find.text('Scan Barcode / QR Code'), findsWidgets);
      expect(find.textContaining('Maggi 2-Minute Masala Noodles'), findsOneWidget);

      // Select Maggi noodles
      await tester.tap(find.textContaining('Maggi 2-Minute Masala Noodles'));
      await tester.pumpAndSettle();

      // Check fields updated: Maggi has 42.0g carbs and 2.5g fiber -> Net Carbs = 39.5g
      expect(find.text('39.5'), findsOneWidget);

      // Tap Log Carbs & Predict Risk
      await tester.tap(find.text('Log Carbs & Predict Risk'));
      await tester.pumpAndSettle();

      expect(loggedEntry, isNotNull);
      expect(loggedEntry!.entryType, 'packaged');
      expect(loggedEntry!.name, contains('Maggi'));
      expect(loggedEntry!.netCarbsGrams, 39.5);
    });

    testWidgets('allows manual input changes and net carb recalculation',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ManualFoodEntrySheet(
              initialTab: 1,
            ),
          ),
        ),
      );

      // Enter custom carbs: 30g, fiber: 5g
      final carbsField = find.widgetWithText(TextField, '17.5');
      await tester.enterText(carbsField, '30');

      final fiberField = find.widgetWithText(TextField, '2.8');
      await tester.enterText(fiberField, '5');
      await tester.pumpAndSettle();

      // Net carbs = (30 - 5) * 1 = 25.0g
      expect(find.text('25.0'), findsOneWidget);
      expect(find.text('Fiber: 5.0g deducted'), findsOneWidget);
    });
  });
}
