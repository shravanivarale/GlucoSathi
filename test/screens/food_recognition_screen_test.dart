import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:glucosaathi/core/errors/app_failure.dart';
import 'package:glucosaathi/core/network/api_client.dart';
import 'package:glucosaathi/screens/food_recognition/food_recognition_screen.dart';

const String _png1x1Base64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

// Real minimal 1x1 baseline JPEG (starts with the FF D8 FF magic).
const String _jpeg1x1Base64 =
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVN//2Q==';

class _FakeApiClient implements ApiClient {
  _FakeApiClient(this.handler);

  final Future<Map<String, dynamic>> Function(File image) handler;

  @override
  Future<Map<String, dynamic>> analyzeFood(File image) => handler(image);
}

Future<File> _createPngFile([String name = 'meal.png']) async {
  final dir = await Directory.systemTemp.createTemp('food_recognition_test');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(base64Decode(_png1x1Base64));
  return file;
}

Future<File> _createJpegFile([String name = 'meal.jpg']) async {
  final dir = await Directory.systemTemp.createTemp('food_recognition_test');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(base64Decode(_jpeg1x1Base64));
  return file;
}

Future<File> _createOversizedJpegFile() async {
  final dir = await Directory.systemTemp.createTemp('food_recognition_test');
  final file = File('${dir.path}/meal.jpg');
  final bytes = List<int>.filled(10 * 1024 * 1024 + 1, 0);
  bytes[0] = 0xFF;
  bytes[1] = 0xD8;
  bytes[2] = 0xFF;
  await file.writeAsBytes(bytes);
  return file;
}

Future<File> _createTextFile([String name = 'meal.jpg']) async {
  final dir = await Directory.systemTemp.createTemp('food_recognition_test');
  final file = File('${dir.path}/$name');
  await file.writeAsString('this is not an image');
  return file;
}

/// Creates a temp image off the fake-async thread so real file I/O resolves.
Future<T> _createInTest<T>(WidgetTester tester, Future<T> Function() create) =>
    tester.runAsync<T>(create).then((value) => value!);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required Future<Map<String, dynamic>> Function(File image) handler,
  Future<XFile?> Function(ImageSource source)? pickImage,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FoodRecognitionScreen(
        client: _FakeApiClient(handler),
        pickImage: pickImage ?? ((source) async => null),
      ),
    ),
  );
}

/// Taps "Upload Image", lets the injected picker return [file], and settles.
Future<void> _selectImage(WidgetTester tester, File file) async {
  await tester.tap(find.text('Upload Image'));
  await tester.pumpAndSettle();
}

final Map<String, dynamic> _matchedNutrition = {
  'carb_g': 35.048,
  'protein_g': 6.085,
  'fat_g': 14.138,
  'fibre_g': 3.716,
  'energy_kcal': 294.526,
  'basis': 'per_100g',
  'nutrition_source': 'INDB',
};

final Map<String, double> _totalNutrition = {
  'carb_g': 35.048,
  'protein_g': 6.085,
  'fat_g': 14.138,
  'fibre_g': 3.716,
  'energy_kcal': 294.526,
};

void main() {
  testWidgets('renders the title and both source options', (tester) async {
    await _pumpScreen(tester, handler: (_) async => {});

    expect(find.text('GlucoSaathi - Food Recognition'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Upload Image'), findsOneWidget);
    expect(find.text('Analyze Food'), findsNothing);
  });

  testWidgets('shows a loading indicator while analyzing', (tester) async {
    final completer = Completer<Map<String, dynamic>>();
    final file = await _createInTest(tester, _createPngFile);

    await _pumpScreen(
      tester,
      handler: (_) => completer.future,
      pickImage: (source) async => XFile(file.path),
    );
    await _selectImage(tester, file);

    expect(find.text('Analyze Food'), findsOneWidget);
    await tester.tap(find.text('Analyze Food'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Analyzing food...'), findsOneWidget);

    completer.complete({
      'foods': [
        {
          'recognized_food': 'Poha',
          'matched': true,
          'nutrition': _matchedNutrition,
        },
      ],
      'total_nutrition': _totalNutrition,
    });
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Poha'), findsOneWidget);
  });

  testWidgets('renders recognized food and INDB nutrition on success',
      (tester) async {
    final file = await _createInTest(tester, _createPngFile);

    await _pumpScreen(
      tester,
      handler: (_) async => {
        'foods': [
          {
            'recognized_food': 'Poha',
            'matched': true,
            'nutrition': _matchedNutrition,
          },
        ],
        'total_nutrition': _totalNutrition,
      },
      pickImage: (source) async => XFile(file.path),
    );
    await _selectImage(tester, file);
    await tester.tap(find.text('Analyze Food'));
    await tester.pumpAndSettle();

    expect(find.text('Recognized Foods'), findsOneWidget);
    expect(find.text('Poha'), findsOneWidget);
    expect(find.text('Carbohydrates'), findsAtLeastNWidgets(1));
    expect(find.text('35.0 g'), findsAtLeastNWidgets(1));
    expect(find.text('Protein'), findsAtLeastNWidgets(1));
    expect(find.text('6.1 g'), findsAtLeastNWidgets(1));
    expect(find.text('Fat'), findsAtLeastNWidgets(1));
    expect(find.text('14.1 g'), findsAtLeastNWidgets(1));
    expect(find.text('Fibre'), findsAtLeastNWidgets(1));
    expect(find.text('3.7 g'), findsAtLeastNWidgets(1));
    expect(find.text('Energy'), findsAtLeastNWidgets(1));
    expect(find.text('294.5 kcal'), findsAtLeastNWidgets(1));
  });

  testWidgets('renders the unmatched message when no nutrition match exists',
      (tester) async {
    final file = await _createInTest(tester, _createPngFile);

    await _pumpScreen(
      tester,
      handler: (_) async => {
        'foods': [
          {
            'recognized_food': 'Rajma Chawal',
            'matched': false,
            'message': 'Food not found in nutrition database',
          },
        ],
        'total_nutrition': null,
      },
      pickImage: (source) async => XFile(file.path),
    );
    await _selectImage(tester, file);
    await tester.tap(find.text('Analyze Food'));
    await tester.pumpAndSettle();

    expect(find.text('Recognized Foods'), findsOneWidget);
    expect(find.text('Rajma Chawal'), findsOneWidget);
    expect(find.text('Food not found in nutrition database'), findsOneWidget);
    expect(find.text('Carbohydrates'), findsNothing);
  });

  testWidgets('shows a friendly message when the backend reports a failure',
      (tester) async {
    final file = await _createInTest(tester, _createPngFile);

    await _pumpScreen(
      tester,
      handler: (_) async =>
          throw const FoodNotRecognizedFailure("We couldn't identify the food."),
      pickImage: (source) async => XFile(file.path),
    );
    await _selectImage(tester, file);
    await tester.tap(find.text('Analyze Food'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text("We couldn't identify the food."), findsOneWidget);
    expect(find.text('Poha'), findsNothing);
  });

  testWidgets('shows a generic message for unexpected errors', (tester) async {
    final file = await _createInTest(tester, _createPngFile);

    await _pumpScreen(
      tester,
      handler: (_) async => throw Exception('boom'),
      pickImage: (source) async => XFile(file.path),
    );
    await _selectImage(tester, file);
    await tester.tap(find.text('Analyze Food'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('boom'), findsNothing);
  });

  testWidgets('accepts a valid JPEG even when the picker assigns a non-image name',
      (tester) async {
    // Reproduces the Android bug: image_picker can return a genuine JPEG whose
    // cached filename has no `.jpg`/`.jpeg`/`.png` suffix (e.g. a bare
    // display name, `.tmp`, or `image_picker`). The format must be judged by
    // its magic bytes, not its filename.
    final file = await _createInTest(tester, () => _createJpegFile('food'));
    var receivedImagePath = '';

    await _pumpScreen(
      tester,
      handler: (image) async {
        receivedImagePath = image.path;
        return {
          'foods': [
            {
              'recognized_food': 'Poha',
              'matched': true,
              'nutrition': _matchedNutrition,
            },
          ],
          'total_nutrition': _totalNutrition,
        };
      },
      pickImage: (source) async => XFile(file.path),
    );
    await _selectImage(tester, file);

    expect(find.text('Analyze Food'), findsOneWidget);
    expect(find.text('Please choose a JPEG or PNG image.'), findsNothing);

    await tester.tap(find.text('Analyze Food'));
    await tester.pumpAndSettle();

    expect(receivedImagePath, file.path);
    expect(find.text('Poha'), findsOneWidget);
  });

  testWidgets(
      'accepts a valid JPEG even when the provider reports a bad MIME value',
      (tester) async {
    // Android Photo Picker can return null or inconsistent MIME metadata.
    // Validation must be based on the file bytes, never on that value.
    final file = await _createInTest(tester, () => _createJpegFile('food.jpg'));

    await _pumpScreen(
      tester,
      handler: (_) async {
        return {
          'foods': [
            {
              'recognized_food': 'Poha',
              'matched': true,
              'nutrition': _matchedNutrition,
            },
          ],
          'total_nutrition': _totalNutrition,
        };
      },
      pickImage: (source) async =>
          XFile(file.path, mimeType: 'application/octet-stream'),
    );
    await _selectImage(tester, file);

    expect(find.text('Analyze Food'), findsOneWidget);
    expect(find.text('Please choose a JPEG or PNG image.'), findsNothing);

    await tester.tap(find.text('Analyze Food'));
    await tester.pumpAndSettle();

    expect(find.text('Poha'), findsOneWidget);
  });

  testWidgets('accepts a valid PNG with a non-image filename', (tester) async {
    final file = await _createInTest(tester, () => _createPngFile('photo.tmp'));

    await _pumpScreen(
      tester,
      handler: (_) async => {
        'foods': [
          {
            'recognized_food': 'Rajma Chawal',
            'matched': false,
          },
        ],
        'total_nutrition': null,
      },
      pickImage: (source) async => XFile(file.path),
    );
    await _selectImage(tester, file);

    expect(find.text('Analyze Food'), findsOneWidget);
    expect(find.text('Please choose a JPEG or PNG image.'), findsNothing);
  });

  testWidgets('rejects a non-image file even when the name suggests an image',
      (tester) async {
    final file = await _createInTest(tester, () => _createTextFile('fake.jpg'));
    var called = false;

    await _pumpScreen(
      tester,
      handler: (image) async {
        called = true;
        return {};
      },
      pickImage: (source) async => XFile(file.path),
    );
    await _selectImage(tester, file);

    expect(called, isFalse);
    expect(find.text('Please choose a JPEG or PNG image.'), findsOneWidget);
    expect(find.text('Analyze Food'), findsNothing);
  });

  testWidgets('rejects an oversized image regardless of format', (tester) async {
    final file = await _createInTest(tester, _createOversizedJpegFile);
    var called = false;

    await _pumpScreen(
      tester,
      handler: (image) async {
        called = true;
        return {};
      },
      pickImage: (source) async => XFile(file.path),
    );
    await _selectImage(tester, file);

    expect(called, isFalse);
    expect(find.text('Image is too large. The maximum size is 10 MB.'),
        findsOneWidget);
    expect(find.text('Analyze Food'), findsNothing);
  });
}