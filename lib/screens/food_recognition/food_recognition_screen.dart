/// Food Image Upload + Recognition screen for the GlucoSaathi MVP.
///
/// Captures or picks a food image, uploads it to
/// `POST /api/v1/foods/analyze` through [ApiClient], and renders the
/// recognized foods plus INDB nutrition values returned by the backend.
/// No Gemini or INDB logic lives here — both are handled server-side.
///
/// A single consistent response format is used: the backend always returns
/// a `foods` list (one element for a single-food image, multiple for a
/// meal) plus an optional `totalNutrition` aggregation.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/app_failure.dart';
import '../../core/network/api_client.dart';
import '../../core/network/http_api_client.dart';
import '../../core/utils/image_format.dart';
import '../../models/food_analysis_result.dart';

/// Obtains an [XFile] for the given [ImageSource]. Injectable so widget tests
/// never touch the platform camera/gallery plugins.
typedef ImagePickFunction = Future<XFile?> Function(ImageSource source);

/// Minimal working Food Recognition screen.
class FoodRecognitionScreen extends StatefulWidget {
  const FoodRecognitionScreen({super.key, this.client, this.pickImage});

  /// Backend client used for analysis. Defaults to [HttpApiClient] so the
  /// request goes through the existing networking layer.
  final ApiClient? client;

  /// Injectable image picker, overridden in tests.
  final ImagePickFunction? pickImage;

  @override
  State<FoodRecognitionScreen> createState() => _FoodRecognitionScreenState();
}

class _FoodRecognitionScreenState extends State<FoodRecognitionScreen> {
  static const int _maxImageBytes = 10 * 1024 * 1024;

  late final ApiClient _client = widget.client ?? HttpApiClient();
  late final ImagePickFunction _pickImage =
      widget.pickImage ?? _defaultPickImage;

  final ImagePicker _imagePicker = ImagePicker();

  File? _image;
  bool _isLoading = false;
  FoodAnalysis? _analysis;
  String? _errorMessage;

  Future<XFile?> _defaultPickImage(ImageSource source) =>
      _imagePicker.pickImage(source: source);

  Future<void> _onTakePhoto() => _selectImage(ImageSource.camera);

  Future<void> _onUploadImage() => _selectImage(ImageSource.gallery);

  Future<void> _selectImage(ImageSource source) async {
    setState(() {
      _image = null;
      _analysis = null;
      _errorMessage = null;
      _isLoading = false;
    });

    XFile? picked;
    try {
      picked = await _pickImage(source);
    } catch (_) {
      _showError(source == ImageSource.camera
          ? 'Could not open the camera on this device. Try uploading an image instead.'
          : 'Could not open the gallery on this device.');
      return;
    }
    if (picked == null) {
      return; // User dismissed the picker.
    }

    final file = File(picked.path);
    final validationError = _validateImage(file);
    if (validationError != null) {
      _showError(validationError);
      return;
    }

    setState(() => _image = file);
  }

  /// Returns a user-facing error, or `null` when [image] is acceptable.
  String? _validateImage(File image) {
    if (detectImageFormat(image) == ImageFormat.unknown) {
      return 'Please choose a JPEG or PNG image.';
    }
    if (image.lengthSync() > _maxImageBytes) {
      return 'Image is too large. The maximum size is 10 MB.';
    }
    return null;
  }

  Future<void> _analyze() async {
    final image = _image;
    if (image == null) {
      return;
    }
    setState(() {
      _isLoading = true;
      _analysis = null;
      _errorMessage = null;
    });

    try {
      final result = await _client.analyzeFood(image);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _analysis = FoodAnalysis.fromJson(result);
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _analysis = null;
        _errorMessage = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _analysis = null;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  void _clearImage() {
    setState(() {
      _image = null;
      _analysis = null;
      _errorMessage = null;
      _isLoading = false;
    });
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
      _analysis = null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GlucoSaathi - Food Recognition')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_image == null)
                _buildSourceOptions()
              else
                _buildImageReview(),
              const SizedBox(height: 16),
              if (_isLoading)
                _buildLoading()
              else ...[
                if (_errorMessage != null) _buildError(_errorMessage!),
                if (_analysis != null) _buildResult(_analysis!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _onTakePhoto,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Take Photo'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _onUploadImage,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Upload Image'),
        ),
      ],
    );
  }

  Widget _buildImageReview() {
    final image = _image!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            image,
            height: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              height: 220,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isLoading ? null : _analyze,
          icon: const Icon(Icons.search),
          label: const Text('Analyze Food'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _isLoading ? null : _clearImage,
          child: const Text('Choose a different image'),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Analyzing food...'),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildResult(FoodAnalysis analysis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Recognized Foods section ---
        Text(
          'Recognized Foods',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < analysis.foods.length; i++) ...[
          _buildFoodCard(analysis.foods[i]),
          if (i < analysis.foods.length - 1) const SizedBox(height: 8),
        ],
        // --- Meal Total section ---
        if (analysis.totalNutrition != null) ...[
          const SizedBox(height: 16),
          _buildMealTotal(analysis.totalNutrition!),
        ] else if (analysis.foods.every((f) => !f.matched)) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No nutrition data available for this meal',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFoodCard(SingleFoodResult food) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    food.recognizedFood,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _MatchBadge(matched: food.matched),
              ],
            ),
            if (food.matched && food.nutrition != null) ...[
              const SizedBox(height: 12),
              ..._buildNutrition(food.nutrition!),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                food.message ?? 'Food not found in nutrition database',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMealTotal(Map<String, double> total) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Meal Total',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
            ),
            const SizedBox(height: 8),
            _NutritionRow(
              'Carbohydrates',
              '${total["carb_g"]?.toStringAsFixed(1) ?? "0"} g',
            ),
            _NutritionRow(
              'Protein',
              '${total["protein_g"]?.toStringAsFixed(1) ?? "0"} g',
            ),
            _NutritionRow(
              'Fat',
              '${total["fat_g"]?.toStringAsFixed(1) ?? "0"} g',
            ),
            _NutritionRow(
              'Fibre',
              '${total["fibre_g"]?.toStringAsFixed(1) ?? "0"} g',
            ),
            _NutritionRow(
              'Energy',
              '${total["energy_kcal"]?.toStringAsFixed(1) ?? "0"} kcal',
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildNutrition(FoodNutrition nutrition) {
    return [
      _NutritionRow('Carbohydrates', '${nutrition.carbG.toStringAsFixed(1)} g'),
      _NutritionRow('Protein', '${nutrition.proteinG.toStringAsFixed(1)} g'),
      _NutritionRow('Fat', '${nutrition.fatG.toStringAsFixed(1)} g'),
      _NutritionRow('Fibre', '${nutrition.fibreG.toStringAsFixed(1)} g'),
      _NutritionRow('Energy', '${nutrition.energyKcal.toStringAsFixed(1)} kcal'),
    ];
  }
}

class _MatchBadge extends StatelessWidget {
  const _MatchBadge({required this.matched});

  final bool matched;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: matched
            ? colorScheme.primaryContainer
            : colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        matched ? 'Matched' : 'Not found',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: matched
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onErrorContainer,
            ),
      ),
    );
  }
}

class _NutritionRow extends StatelessWidget {
  const _NutritionRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
