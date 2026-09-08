/// Home Dashboard screen for GlucoSaathi.
///
/// Features:
/// 1. Top Section: Current Glucose + trend arrow, Active Insulin (IOB), and dynamic Risk Banner.
/// 2. Central Log Meal Action Card: Take Photo, Upload Image, Cooked Dish, Packaged Item.
/// 3. Quick-Log Bar: 1-tap frequent Indian foods logging.
/// 4. Integrated Image Review & INDB Analysis.
/// 5. Manual Food Entry Bottom Sheet modal with Tab A (Cooked Dish) and Tab B (Packaged Item).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/app_failure.dart';
import '../../core/network/api_client.dart';
import '../../core/network/http_api_client.dart';
import '../../core/utils/image_format.dart';
import '../../models/food_analysis_result.dart';
import '../../models/logged_meal_entry.dart';
import '../../models/user_profile.dart';
import '../../widgets/glucose_status_card.dart';
import '../../widgets/log_meal_action_card.dart';
import '../../widgets/manual_food_entry_sheet.dart';
import '../../widgets/quick_log_bar.dart';
import '../../widgets/risk_prediction_banner.dart';
import '../../services/glucose_api_service.dart';
import '../profile/profile_screen.dart';

/// Injectable image picker function for unit testing.
typedef ImagePickFunction = Future<XFile?> Function(ImageSource source);

/// Redesigned Home Screen with status tiles, risk banner, 4-button log card,
/// quick-log bar, and full manual & image logging flows.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.client,
    this.pickImage,
    this.initialGlucose = 124,
    this.initialActiveInsulin = 1.8,
  });

  /// Backend client used for food image analysis.
  final ApiClient? client;

  /// Injectable image picker function for testing.
  final ImagePickFunction? pickImage;

  /// Initial glucose reading in mg/dL.
  final double initialGlucose;

  /// Initial Active Insulin on Board (IOB) in units.
  final double initialActiveInsulin;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const int _maxImageBytes = 10 * 1024 * 1024;

  late final TabController _homeTabController;
  late final ApiClient _client = widget.client ?? HttpApiClient();
  late final ImagePickFunction _pickImage =
      widget.pickImage ?? _defaultPickImage;
  final ImagePicker _imagePicker = ImagePicker();
  final GlucoseApiService _glucoseApi = GlucoseApiService();

  // State: Glucose & Insulin
  late double _currentGlucose;
  late double _activeInsulin;

  // State: AI Glucose Forecast
  GlucosePrediction? _glucosePrediction;
  bool _isPredictingGlucose = false;

  String _glucoseTrend = '➔';
  String _insulinType = 'Regular (Novolin R)';
  UserProfile _userProfile = const UserProfile();

  // State: Image Capture & Analysis
  File? _image;
  bool _isAnalyzing = false;
  FoodAnalysis? _analysis;
  String? _errorMessage;

  // State: Recent Logged Meals
  final List<LoggedMealEntry> _recentMeals = [];

  @override
  void initState() {
    super.initState();
    _currentGlucose = widget.initialGlucose;
    _activeInsulin = widget.initialActiveInsulin;
    _homeTabController = TabController(length: 2, vsync: this);
    _homeTabController.addListener(() {
      if (mounted) setState(() {});
    });

    // Run the ML glucose forecast when the Home screen opens.
    _runGlucosePrediction();
  }

  Future<void> _runGlucosePrediction() async {
    if (!mounted) return;

    setState(() {
      _isPredictingGlucose = true;
    });

    try {
      // Demo history: 24 readings × 5 minutes = 2 hours.
      // The final reading is the current glucose value.
      // This will later be replaceable with real CGM/history data.
      final readings = <Map<String, dynamic>>[];

      double step = 0.0;
      if (_glucoseTrend == '↓') {
        step = -2.0;
      } else if (_glucoseTrend == '↘') {
        step = -1.0;
      } else if (_glucoseTrend == '↑') {
        step = 2.0;
      } else if (_glucoseTrend == '↗') {
        step = 1.0;
      }

      for (int i = 0; i < 24; i++) {
        final distanceFromCurrent = 23 - i;
        final cbg = _currentGlucose - (step * distanceFromCurrent);

        readings.add({
          'cbg': cbg.clamp(40.0, 400.0),
          'basal': 0.0,
          'hr': 0.0,
          'gsr': 0.0,
          'carbInput': 0.0,
          'bolus': 0.0,
        });
      }

      final prediction = await _glucoseApi.predictRaw(readings);

      if (!mounted) return;

      setState(() {
        _glucosePrediction = prediction;
        _isPredictingGlucose = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isPredictingGlucose = false;
      });

      debugPrint('Glucose prediction error: $e');
    }
  }

  @override
  void dispose() {
    _homeTabController.dispose();
    super.dispose();
  }

  Future<XFile?> _defaultPickImage(ImageSource source) =>
      _imagePicker.pickImage(source: source);

  // Dynamic Risk Prediction Calculation
  RiskPrediction get _currentRiskPrediction {
    double pendingMealCarbs = 0;
    bool hasHighFatMeal = false;

    if (_recentMeals.isNotEmpty) {
      final latest = _recentMeals.first;
      // Consider meals logged in the last 2 hours
      if (DateTime.now().difference(latest.timestamp).inMinutes < 120) {
        pendingMealCarbs = latest.netCarbsGrams;
        hasHighFatMeal = latest.isHighFatProtein;
      }
    }

    return RiskPrediction.calculate(
      currentGlucose: _currentGlucose,
      activeInsulinUnits: _activeInsulin,
      mealNetCarbs: pendingMealCarbs,
      isHighFatProtein: hasHighFatMeal,
    );
  }

  /// Opens glucose-only editor (Demo Mode).
  void _showEditGlucoseDialog() {
    final glucoseController =
        TextEditingController(text: _currentGlucose.toStringAsFixed(0));
    String selectedTrend = _glucoseTrend;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.water_drop_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Adjust Glucose (Demo Mode)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Quick Presets:',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.warning,
                              size: 16, color: Colors.red),
                          label: const Text('Low (65 mg/dL)'),
                          onPressed: () {
                            setModalState(() {
                              glucoseController.text = '65';
                              selectedTrend = '↓';
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.check_circle,
                              size: 16, color: Colors.green),
                          label: const Text('Target (110 mg/dL)'),
                          onPressed: () {
                            setModalState(() {
                              glucoseController.text = '110';
                              selectedTrend = '➔';
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.trending_up,
                              size: 16, color: Colors.orange),
                          label: const Text('Elevated (210 mg/dL)'),
                          onPressed: () {
                            setModalState(() {
                              glucoseController.text = '210';
                              selectedTrend = '↗';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: glucoseController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Current Glucose (mg/dL)',
                        prefixIcon: Icon(Icons.water_drop_outlined),
                        border: OutlineInputBorder(),
                        suffixText: 'mg/dL',
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Trend chips — use Wrap to prevent overflow
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Trend:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        ...['↑', '↗', '➔', '↘', '↓'].map((trend) {
                          final isSelected = selectedTrend == trend;
                          return ChoiceChip(
                            label: Text(trend,
                                style: const TextStyle(fontSize: 16)),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) {
                                setModalState(() => selectedTrend = trend);
                              }
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        final g = double.tryParse(glucoseController.text) ??
                            _currentGlucose;
                        setState(() {
                          _currentGlucose = g;
                          _glucoseTrend = selectedTrend;
                        });
                        _runGlucosePrediction();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Glucose updated: ${g.toStringAsFixed(0)} mg/dL $selectedTrend'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text('Apply & Recalculate Risk',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Opens insulin-only editor (Demo Mode).
  void _showEditInsulinDialog() {
    final insulinController =
        TextEditingController(text: _activeInsulin.toStringAsFixed(1));
    String selectedInsulin = _insulinType;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.medication_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Adjust Insulin / IOB (Demo Mode)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Quick Presets:',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.arrow_upward,
                              size: 16, color: Colors.blue),
                          label: const Text('High IOB (2.5 U)'),
                          onPressed: () {
                            setModalState(() {
                              insulinController.text = '2.5';
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.check_circle,
                              size: 16, color: Colors.green),
                          label: const Text('Normal (1.2 U)'),
                          onPressed: () {
                            setModalState(() {
                              insulinController.text = '1.2';
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.arrow_downward,
                              size: 16, color: Colors.orange),
                          label: const Text('Low IOB (0.5 U)'),
                          onPressed: () {
                            setModalState(() {
                              insulinController.text = '0.5';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: insulinController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Active Insulin / IOB (Units)',
                        prefixIcon: Icon(Icons.medication_outlined),
                        border: OutlineInputBorder(),
                        suffixText: 'U',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedInsulin,
                      decoration: const InputDecoration(
                        labelText: 'Insulin Formulation',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Regular (Novolin R)',
                            child: Text('Regular (Novolin R)')),
                        DropdownMenuItem(
                            value: 'Rapid-Acting (Novorapid)',
                            child: Text('Rapid-Acting (Novorapid)')),
                        DropdownMenuItem(
                            value: 'Ultra-Rapid (Fiasp)',
                            child: Text('Ultra-Rapid (Fiasp)')),
                        DropdownMenuItem(
                            value: 'Humalog (Lispro)',
                            child: Text('Humalog (Lispro)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedInsulin = val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        final i = double.tryParse(insulinController.text) ??
                            _activeInsulin;
                        setState(() {
                          _activeInsulin = i;
                          _insulinType = selectedInsulin;
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Insulin updated: IOB ${i.toStringAsFixed(1)} U · $selectedInsulin'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text('Apply & Recalculate Risk',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openProfileScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          initialProfile: _userProfile,
          onProfileSaved: (updated) {
            setState(() => _userProfile = updated);
          },
        ),
      ),
    );
  }

  // IMAGE PICKING & ANALYSIS FLOW (Preserving existing logic)
  Future<void> _onTakePhoto() => _selectImage(ImageSource.camera);

  Future<void> _onUploadImage() => _selectImage(ImageSource.gallery);

  Future<void> _selectImage(ImageSource source) async {
    setState(() {
      _image = null;
      _analysis = null;
      _errorMessage = null;
      _isAnalyzing = false;
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

    if (picked == null) return;

    final file = File(picked.path);
    final validationError = _validateImage(file);
    if (validationError != null) {
      _showError(validationError);
      return;
    }

    setState(() => _image = file);
  }

  String? _validateImage(File image) {
    if (detectImageFormat(image) == ImageFormat.unknown) {
      return 'Please choose a JPEG or PNG image.';
    }
    if (image.lengthSync() > _maxImageBytes) {
      return 'Image is too large. The maximum size is 10 MB.';
    }
    return null;
  }

  Future<void> _analyzeImage() async {
    final image = _image;
    if (image == null) return;

    setState(() {
      _isAnalyzing = true;
      _analysis = null;
      _errorMessage = null;
    });

    try {
      final result = await _client.analyzeFood(image);
      if (!mounted) return;
      final analysis = FoodAnalysis.fromJson(result);
      setState(() {
        _isAnalyzing = false;
        _analysis = analysis;
      });

      // If recognized with carbs, automatically log meal entry
      if (analysis.matched && analysis.nutrition != null) {
        final nut = analysis.nutrition!;
        _addLoggedMeal(LoggedMealEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: analysis.recognizedFood,
          entryType: 'photo',
          portionDescription: 'Photo Analysis (100g basis)',
          totalCarbsGrams: nut.carbG,
          fiberGrams: nut.fibreG,
          netCarbsGrams: (nut.carbG - nut.fibreG).clamp(0.0, double.infinity),
          isHighFatProtein: nut.fatG > 15.0,
          timestamp: DateTime.now(),
        ));
      }
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _analysis = null;
        _errorMessage = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
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
      _isAnalyzing = false;
    });
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
      _analysis = null;
      _isAnalyzing = false;
    });
  }

  // MANUAL ENTRY FLOW
  void _openManualEntry({int initialTab = 0}) async {
    final result = await ManualFoodEntrySheet.show(
      context,
      initialTab: initialTab,
      currentGlucose: _currentGlucose,
      activeInsulin: _activeInsulin,
      pickImage: _pickImage,
    );

    if (result != null && mounted) {
      _addLoggedMeal(result);
      _showMealLoggedSnackbar(result);
    }
  }

  // QUICK-LOG 1-TAP ACTION
  void _onQuickLog(Map<String, dynamic> item) {
    final label = item['label'] as String;
    final carbs = (item['carbs'] as num).toDouble();
    final unit = item['unit'] as String;

    final entry = LoggedMealEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: label,
      entryType: 'quick_log',
      portionDescription: unit,
      totalCarbsGrams: carbs,
      fiberGrams: 0,
      netCarbsGrams: carbs,
      isHighFatProtein: label.contains('Paratha') || label.contains('Biryani'),
      timestamp: DateTime.now(),
    );

    _addLoggedMeal(entry);
    _showMealLoggedSnackbar(entry);
  }

  void _addLoggedMeal(LoggedMealEntry entry) {
    setState(() {
      _recentMeals.insert(0, entry);
    });
  }

  void _showMealLoggedSnackbar(LoggedMealEntry entry) {
    // Dismiss any already-queued snackbars so they don't pile up.
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Logged ${entry.name} (${entry.netCarbsGrams.toStringAsFixed(1)}g carbs)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            setState(() {
              _recentMeals.remove(entry);
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/logo.png',
                height: 32,
                width: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.monitor_heart,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'GlucoSaathi',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'User Profile & Settings',
            onPressed: _openProfileScreen,
          ),
        ],
        bottom: TabBar(
          controller: _homeTabController,
          tabs: [
            const Tab(icon: Icon(Icons.home_outlined), text: 'Home'),
            Tab(
              icon: Badge(
                isLabelVisible: _recentMeals.isNotEmpty,
                label: Text('${_recentMeals.length}'),
                child: const Icon(Icons.today_outlined),
              ),
              text: "Today's Meals",
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _homeTabController,
        children: [
          // ── TAB 1: HOME ──────────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // TOP SECTION (Glucose & Status Tiles)
                  GlucoseStatusCard(
                    glucoseValue: _currentGlucose,
                    glucoseTrend: _glucoseTrend,
                    activeInsulinUnits: _activeInsulin,
                    insulinType: _insulinType,
                    onTapGlucose: _showEditGlucoseDialog,
                    onTapInsulin: _showEditInsulinDialog,
                  ),

                  const SizedBox(height: 12),

                  // DYNAMIC RISK BANNER
                  RiskPredictionBanner(
                    prediction: _currentRiskPrediction,
                  ),

                  const SizedBox(height: 12),

                  // AI GLUCOSE FORECAST
                  _buildGlucoseForecastCard(),

                  const SizedBox(height: 16),

                  // CENTRAL "LOG MEAL" ACTION CARD (4 Buttons)
                  LogMealActionCard(
                    isLoading: _isAnalyzing,
                    onTakePhoto: _onTakePhoto,
                    onUploadImage: _onUploadImage,
                    onCookedDish: () => _openManualEntry(initialTab: 0),
                    onPackagedItem: () => _openManualEntry(initialTab: 1),
                  ),

                  const SizedBox(height: 16),

                  // QUICK-LOG BAR (Frequent Indian Foods)
                  QuickLogBar(
                    onQuickLog: _onQuickLog,
                  ),

                  const SizedBox(height: 16),

                  // PHOTO ANALYSIS & REVIEW SECTION (when image is picked)
                  if (_image != null) ...[
                    _buildImageReviewSection(),
                    const SizedBox(height: 16),
                  ],

                  if (_isAnalyzing) ...[
                    _buildLoadingCard(),
                    const SizedBox(height: 16),
                  ],

                  if (_errorMessage != null) ...[
                    _buildErrorCard(_errorMessage!),
                    const SizedBox(height: 16),
                  ],

                  if (_analysis != null) ...[
                    _buildAnalysisResultCard(_analysis!),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),

          // ── TAB 2: TODAY'S MEALS ─────────────────────────────────────────
          SafeArea(
            child: _recentMeals.isEmpty
                ? _buildEmptyMealsState()
                : SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: _buildRecentMealsSection(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlucoseForecastCard() {
    final theme = Theme.of(context);
    final prediction = _glucosePrediction;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_graph,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI Glucose Forecast',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Model-based prediction for the next 30 and 60 minutes',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            if (_isPredictingGlucose)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (prediction != null)
              Row(
                children: [
                  Expanded(
                    child: _buildForecastValue(
                      '30 min',
                      prediction.prediction30Min,
                      theme,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildForecastValue(
                      '60 min',
                      prediction.prediction60Min,
                      theme,
                    ),
                  ),
                ],
              )
            else
              Text(
                'Prediction unavailable. Check backend connection.',
                style: TextStyle(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Demo prediction • Not for medical or dosing decisions',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForecastValue(
    String label,
    double value,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 12,
        horizontal: 10,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${value.toStringAsFixed(0)} mg/dL',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageReviewSection() {
    final image = _image!;
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Captured Food Image',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: _isAnalyzing ? null : _clearImage,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                image,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 200,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isAnalyzing ? null : _analyzeImage,
              icon: const Icon(Icons.search),
              label: const Text('Analyze Food with INDB'),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: _isAnalyzing ? null : _clearImage,
              child: const Text('Choose a different image'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Analyzing food with Gemini & INDB...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisResultCard(FoodAnalysis analysis) {
    final theme = Theme.of(context);
    final nutrition = analysis.nutrition;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recognized Food (INDB)',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (analysis.matched)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'MATCHED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              analysis.recognizedFood,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (analysis.matched && nutrition != null) ...[
              _buildNutritionRow(
                  'Carbohydrates', '${nutrition.carbG.toStringAsFixed(1)} g'),
              _buildNutritionRow(
                  'Protein', '${nutrition.proteinG.toStringAsFixed(1)} g'),
              _buildNutritionRow(
                  'Fat', '${nutrition.fatG.toStringAsFixed(1)} g'),
              _buildNutritionRow(
                  'Fibre', '${nutrition.fibreG.toStringAsFixed(1)} g'),
              _buildNutritionRow('Energy',
                  '${nutrition.energyKcal.toStringAsFixed(1)} kcal'),
              const Divider(height: 20),
              Text(
                'Source: ${nutrition.nutritionSource} • Basis: ${nutrition.basis}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              Text(
                analysis.message ?? 'Food not found in nutrition database',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmptyMealsState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.restaurant_menu_outlined,
              size: 72,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 20),
            Text(
              'No meals logged today',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use Quick-Log or the Log Meal card on the\nHome tab to record what you eat.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentMealsSection() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Today’s Logged Meals',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_recentMeals.length} logged',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._recentMeals.map((meal) {
          final isHighFat = meal.isHighFatProtein;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  meal.entryType == 'cooked'
                      ? Icons.soup_kitchen
                      : meal.entryType == 'packaged'
                          ? Icons.inventory_2
                          : meal.entryType == 'photo'
                              ? Icons.camera_alt
                              : Icons.bolt,
                  size: 18,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(
                meal.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${meal.portionDescription}${isHighFat ? " • High Fat/Protein" : ""}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isHighFat ? Colors.amber.shade900 : null,
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${meal.netCarbsGrams.toStringAsFixed(1)}g',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    'Net Carbs',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}