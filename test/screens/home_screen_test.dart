import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:glucosaathi/core/errors/app_failure.dart';
import 'package:glucosaathi/core/network/api_client.dart';
import 'package:glucosaathi/screens/home/home_screen.dart';

const String _png1x1Base64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _FakeApiClient implements ApiClient {
  _FakeApiClient(this.handler);

  final Future<Map<String, dynamic>> Function(File image) handler;

  @override
  Future<Map<String, dynamic>> analyzeFood(File image) => handler(image);
}

Future<File> _createPngFile([String name = 'meal.png']) async {
  final dir = await Directory.systemTemp.createTemp('home_screen_test');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(base64Decode(_png1x1Base64));
  return file;
}

Future<T> _createInTest<T>(WidgetTester tester, Future<T> Function() create) =>
    tester.runAsync<T>(create).then((value) => value!);

Future<void> _pumpHomeScreen(
  WidgetTester tester, {
  Future<Map<String, dynamic>> Function(File image)? handler,
  Future<XFile?> Function(ImageSource source)? pickImage,
  double glucose = 124,
  double activeInsulin = 1.8,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());

  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        client: _FakeApiClient(handler ?? (_) async => {}),
        pickImage: pickImage ?? ((source) async => null),
        initialGlucose: glucose,
        initialActiveInsulin: activeInsulin,
      ),
    ),
  );
}

void main() {
  group('HomeScreen UI & Integration Tests', () {
    testWidgets('renders Top Section (Glucose & Active Insulin) and Risk Banner',
        (tester) async {
      await _pumpHomeScreen(tester);

      // Top Glucose Tile
      expect(find.text('Glucose'), findsOneWidget);
      expect(find.text('124'), findsOneWidget);
      expect(find.text('mg/dL'), findsOneWidget);
      expect(find.text('➔'), findsOneWidget);
      expect(find.text('In Range (Tap to Edit)'), findsOneWidget);

      // Top Active Insulin Tile
      expect(find.text('Active Insulin'), findsOneWidget);
      expect(find.text('1.8 U'), findsOneWidget);
      expect(find.text('IOB'), findsOneWidget);

      // Risk Banner
      expect(find.text('Low Risk — Stable Glycemia'), findsOneWidget);
      expect(find.text('LOW RISK'), findsOneWidget);
    });

    testWidgets('renders 4-Button Log Meal Action Card', (tester) async {
      await _pumpHomeScreen(tester);

      expect(find.text('Log Meal'), findsOneWidget);
      // Top Row (Visual)
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Upload Image'), findsOneWidget);

      // Bottom Row (Manual Entry)
      expect(find.text('Cooked Dish'), findsOneWidget);
      expect(find.text('Packaged Item'), findsOneWidget);
    });

    testWidgets('renders Quick-Log Bar and 1-tap logging updates UI',
        (tester) async {
      await _pumpHomeScreen(tester);

      expect(find.text('Quick-Log (Frequent Indian Foods)'), findsOneWidget);
      expect(find.text('2 Roti'), findsOneWidget);
      expect(find.text('1 Katori Dal'), findsOneWidget);

      // Tap 1-tap quick log item
      await tester.tap(find.text('2 Roti'));
      await tester.pumpAndSettle();

      // Check snackbar
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Logged 2 Roti'), findsOneWidget);

      // Check Today's Logged Meals list appears
      expect(find.text('Today’s Logged Meals'), findsOneWidget);
    });

    testWidgets('tapping Cooked Dish opens Manual Food Entry Sheet on Tab A',
        (tester) async {
      await _pumpHomeScreen(tester);

      await tester.tap(find.text('Cooked Dish'));
      await tester.pumpAndSettle();

      expect(find.text('Manual Food Entry'), findsOneWidget);
      expect(find.text('Cooked Dish (INDB)'), findsOneWidget);
      expect(find.text('Household Portion Unit'), findsOneWidget);
      expect(find.text('Log Carbs & Predict Risk'), findsOneWidget);
      expect(find.textContaining('Decision support only'), findsOneWidget);
    });

    testWidgets('tapping Packaged Item opens Manual Food Entry Sheet on Tab B',
        (tester) async {
      await _pumpHomeScreen(tester);

      await tester.tap(find.text('Packaged Item'));
      await tester.pumpAndSettle();

      expect(find.text('Manual Food Entry'), findsOneWidget);
      expect(find.text('Scan Barcode / QR Code'), findsOneWidget);
      expect(find.text('Item Name'), findsOneWidget);
      expect(find.text('Carbs / Serving (g)'), findsOneWidget);
      expect(find.text('Dietary Fiber (g)'), findsOneWidget);
      expect(find.text('Log Carbs & Predict Risk'), findsOneWidget);
    });

    testWidgets('tapping Glucose tile opens vitals editor and updates risk banner',
        (tester) async {
      await _pumpHomeScreen(tester);

      // Tap Glucose tile
      await tester.tap(find.text('In Range (Tap to Edit)'));
      await tester.pumpAndSettle();

      expect(find.text('Adjust Glucose & IOB (Demo Mode)'), findsOneWidget);
      expect(find.text('Low Risk Alert (65 mg/dL)'), findsOneWidget);

      // Tap Low Risk Demo Preset (65 mg/dL)
      await tester.tap(find.text('Low Risk Alert (65 mg/dL)'));
      await tester.pumpAndSettle();

      // Apply changes
      await tester.tap(find.text('Apply Changes & Recalculate Risk'));
      await tester.pumpAndSettle();

      // Verify Glucose tile and Risk Banner updated
      expect(find.text('65'), findsOneWidget);
      expect(find.text('Hypoglycemia Alert (< 70 mg/dL)'), findsOneWidget);
      expect(find.text('HIGH RISK'), findsOneWidget);
    });

    testWidgets('tapping Profile icon opens ProfileScreen', (tester) async {
      await _pumpHomeScreen(tester);

      // Tap profile icon in AppBar
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();

      expect(find.text('User Profile & Clinical Settings'), findsOneWidget);
      expect(find.text('Personal & Demographic'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
    });

    testWidgets('handles image upload and analysis correctly', (tester) async {
      final file = await _createInTest(tester, _createPngFile);

      await _pumpHomeScreen(
        tester,
        pickImage: (_) async => XFile(file.path),
        handler: (_) async => {
          'recognized_food': 'Rajma Chawal Combo',
          'matched': true,
          'nutrition': {
            'carb_g': 22.0,
            'protein_g': 4.8,
            'fat_g': 3.5,
            'fibre_g': 3.2,
            'energy_kcal': 140.0,
            'basis': 'per_100g',
            'nutrition_source': 'INDB',
          },
        },
      );

      // Tap Upload Image
      await tester.tap(find.text('Upload Image'));
      await tester.pumpAndSettle();

      expect(find.text('Captured Food Image'), findsOneWidget);
      expect(find.text('Analyze Food with INDB'), findsOneWidget);

      await tester.tap(find.text('Analyze Food with INDB'));
      await tester.pumpAndSettle();

      expect(find.text('Recognized Food (INDB)'), findsOneWidget);
      expect(find.text('Rajma Chawal Combo'), findsNWidgets(2));
      expect(find.text('Carbohydrates'), findsOneWidget);
      expect(find.text('22.0 g'), findsOneWidget);
    });

    testWidgets('displays error when analysis fails', (tester) async {
      final file = await _createInTest(tester, _createPngFile);

      await _pumpHomeScreen(
        tester,
        pickImage: (_) async => XFile(file.path),
        handler: (_) async =>
            throw const FoodNotRecognizedFailure("Could not identify food."),
      );

      await tester.tap(find.text('Upload Image'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Analyze Food with INDB'));
      await tester.pumpAndSettle();

      expect(find.text('Could not identify food.'), findsOneWidget);
    });
  });
}
