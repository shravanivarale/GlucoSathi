import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:glucosaathi/core/errors/app_failure.dart';
import 'package:glucosaathi/core/network/http_api_client.dart';

void main() {
  group('HttpApiClient', () {
    test('defaultBaseUri targets the Android emulator host loopback', () {
      expect(
        HttpApiClient.defaultBaseUri,
        Uri.parse('http://10.0.2.2:8000'),
      );
    });

    test('sends a multipart POST to /api/v1/foods/analyze with field image',
        () async {
      final image = await _createTempImage();
      addTearDown(() => image.parent.delete(recursive: true));

      final captured = <http.Request>[];
      final client = HttpApiClient(
        httpClient: MockClient((request) async {
          captured.add(request);
          return http.Response('{"ok":true}', 200);
        }),
        baseUri: Uri.parse('http://10.0.2.2:8000'),
      );

      await client.analyzeFood(image);

      final request = captured.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'http://10.0.2.2:8000/api/v1/foods/analyze',
      );
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data'),
      );
      final body = latin1.decode(request.bodyBytes);
      expect(body, contains('form-data; name="image"'));
      expect(body, contains('filename="meal.png"'));
    });

    test(
      'sends a JPEG part with image/jpeg content type even when the filename '
      'has no image extension',
      () async {
        // Android Photo Picker scenario: MIME metadata may be null and
        // image_picker can materialize a cached filename without a
        // `.jpg`/`.jpeg`/`.png` suffix. The declared part content type must
        // come from the file's actual bytes.
        final image = await _createFile('food', [
          0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, //
        ]);
        addTearDown(() => image.parent.delete(recursive: true));

        final captured = <http.Request>[];
        final client = HttpApiClient(
          httpClient: MockClient((request) async {
            captured.add(request);
            return http.Response('{"ok":true}', 200);
          }),
          baseUri: Uri.parse('http://10.0.2.2:8000'),
        );

        await client.analyzeFood(image);

        final body = latin1.decode(captured.single.bodyBytes);
        expect(body, contains('content-type: image/jpeg'));
      },
    );

    test('sends a PNG part with image/png content type', () async {
      final image = await _createFile('image_picker_20260101', [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      ]);
      addTearDown(() => image.parent.delete(recursive: true));

      final captured = <http.Request>[];
      final client = HttpApiClient(
        httpClient: MockClient((request) async {
          captured.add(request);
          return http.Response('{"ok":true}', 200);
        }),
        baseUri: Uri.parse('http://10.0.2.2:8000'),
      );

      await client.analyzeFood(image);

      final body = latin1.decode(captured.single.bodyBytes);
      expect(body, contains('content-type: image/png'));
    });

    test('sends a non-image file with the octet-stream fallback', () async {
      final image = await _createFile('fake.jpg', utf8.encode('not an image'));
      addTearDown(() => image.parent.delete(recursive: true));

      final captured = <http.Request>[];
      final client = HttpApiClient(
        httpClient: MockClient((request) async {
          captured.add(request);
          return http.Response('{"ok":true}', 200);
        }),
        baseUri: Uri.parse('http://10.0.2.2:8000'),
      );

      await client.analyzeFood(image);

      final body = latin1.decode(captured.single.bodyBytes);
      expect(body, contains('content-type: application/octet-stream'));
      expect(body, isNot(contains('content-type: image/')));
    });

    test('decodes a 2xx JSON response into a map', () async {      final image = await _createTempImage();
      addTearDown(() => image.parent.delete(recursive: true));

      final client = HttpApiClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'recognized_food': 'Poha', 'matched': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        baseUri: Uri.parse('http://10.0.2.2:8000'),
      );

      final result = await client.analyzeFood(image);
      expect(result, {'recognized_food': 'Poha', 'matched': true});
    });

    test('maps backend error envelopes to AppFailure subtypes', () async {
      final cases = <String, Type>{
        'INVALID_IMAGE': ImageInvalidFailure,
        'IMAGE_TOO_LARGE': ImageTooLargeFailure,
        'FOOD_NOT_RECOGNIZED': FoodNotRecognizedFailure,
        'LOW_CONFIDENCE': LowConfidenceFailure,
        'FOOD_NOT_FOUND': FoodNotFoundFailure,
        'NUTRITION_DATA_NOT_FOUND': NutritionDataNotFoundFailure,
        'ANALYSIS_FAILED': AnalysisFailedFailure,
        'INTERNAL_ERROR': InternalErrorFailure,
        'SOME_UNKNOWN': UnknownFailure,
      };

      for (final entry in cases.entries) {
        final image = await _createTempImage();
        addTearDown(() => image.parent.delete(recursive: true));

        final client = HttpApiClient(
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'success': false,
                'data': null,
                'error': {
                  'code': entry.key,
                  'message': 'failed',
                },
              }),
              422,
            );
          }),
          baseUri: Uri.parse('http://10.0.2.2:8000'),
        );

        await expectLater(
          client.analyzeFood(image),
          throwsA(isA<AppFailure>().having((f) => f.runtimeType, 'type', entry.value)),
        );
      }
    });

    test('non-2xx without an error envelope maps to UnknownFailure', () async {
      final image = await _createTempImage();
      addTearDown(() => image.parent.delete(recursive: true));

      final client = HttpApiClient(
        httpClient: MockClient((request) async {
          return http.Response('{"unexpected": true}', 500);
        }),
        baseUri: Uri.parse('http://10.0.2.2:8000'),
      );

      await expectLater(
        client.analyzeFood(image),
        throwsA(isA<UnknownFailure>()),
      );
    });

    test('non-JSON response body maps to UnknownFailure', () async {
      final image = await _createTempImage();
      addTearDown(() => image.parent.delete(recursive: true));

      final client = HttpApiClient(
        httpClient: MockClient((request) async {
          return http.Response('<html>not json</html>', 200);
        }),
        baseUri: Uri.parse('http://10.0.2.2:8000'),
      );

      await expectLater(
        client.analyzeFood(image),
        throwsA(isA<UnknownFailure>()),
      );
    });

    test('JSON response that is not a map maps to UnknownFailure', () async {
      final image = await _createTempImage();
      addTearDown(() => image.parent.delete(recursive: true));

      final client = HttpApiClient(
        httpClient: MockClient((request) async {
          return http.Response('[1, 2, 3]', 200);
        }),
        baseUri: Uri.parse('http://10.0.2.2:8000'),
      );

      await expectLater(
        client.analyzeFood(image),
        throwsA(isA<UnknownFailure>()),
      );
    });

    test('slow responses surface a NetworkFailure', () async {
      final image = await _createTempImage();
      addTearDown(() => image.parent.delete(recursive: true));

      final client = HttpApiClient(
        httpClient: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('{}', 200);
        }),
        baseUri: Uri.parse('http://10.0.2.2:8000'),
        timeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        client.analyzeFood(image),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('HTTP client errors surface a NetworkFailure', () async {
      final image = await _createTempImage();
      addTearDown(() => image.parent.delete(recursive: true));

      final client = HttpApiClient(
        httpClient: MockClient((request) async {
          throw http.ClientException('connection refused');
        }),
        baseUri: Uri.parse('http://10.0.2.2:8000'),
      );

      await expectLater(
        client.analyzeFood(image),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('socket errors surface a NetworkFailure', () async {
      final image = await _createTempImage();
      addTearDown(() => image.parent.delete(recursive: true));

      final client = HttpApiClient(
        httpClient: MockClient((request) async {
          throw const SocketException('connection refused');
        }),
        baseUri: Uri.parse('http://10.0.2.2:8000'),
      );

      await expectLater(
        client.analyzeFood(image),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });
}

Future<File> _createTempImage() async {
  final dir = await Directory.systemTemp.createTemp('http_api_client_test');
  final file = File('${dir.path}/meal.png');
  await file.writeAsBytes(Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  ]));
  return file;
}

Future<File> _createFile(String name, List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('http_api_client_test');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file;
}