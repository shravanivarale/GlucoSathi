import 'package:flutter/material.dart';

import 'core/network/http_api_client.dart';
import 'screens/food_recognition/food_recognition_screen.dart';

void main() {
  runApp(const GlucoSaathiApp());
}

class GlucoSaathiApp extends StatelessWidget {
  const GlucoSaathiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GlucoSaathi',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: FoodRecognitionScreen(client: HttpApiClient()),
    );
  }
}