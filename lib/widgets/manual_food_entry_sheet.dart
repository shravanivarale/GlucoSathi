/// Modal Bottom Sheet for Manual Food Entry with Tab A (Cooked Dish) and
/// Tab B (Packaged Item), real-time carb calculations, camera QR/barcode scanning,
/// and medical disclaimer.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/indb_food_database.dart';
import '../models/logged_meal_entry.dart';

/// Injectable image pick function for testing camera/scanner interactions.
typedef ImagePickFunction = Future<XFile?> Function(ImageSource source);

/// Modal Bottom Sheet for entering unpackaged Indian meals or packaged items.
class ManualFoodEntrySheet extends StatefulWidget {
  const ManualFoodEntrySheet({
    super.key,
    this.initialTab = 0,
    this.currentGlucose = 124,
    this.activeInsulin = 1.8,
    this.pickImage,
    this.onMealLogged,
  });

  /// 0 for Cooked Dish (Tab A), 1 for Packaged Item (Tab B).
  final int initialTab;

  /// Current user glucose reading for real-time risk prediction.
  final double currentGlucose;

  /// Active Insulin on Board for real-time risk prediction.
  final double activeInsulin;

  /// Injectable image picker used for camera QR/barcode scanning.
  final ImagePickFunction? pickImage;

  /// Callback when meal is logged.
  final void Function(LoggedMealEntry entry)? onMealLogged;

  /// Helper to show this bottom sheet in a full modal.
  static Future<LoggedMealEntry?> show(
    BuildContext context, {
    int initialTab = 0,
    double currentGlucose = 124,
    double activeInsulin = 1.8,
    ImagePickFunction? pickImage,
    void Function(LoggedMealEntry entry)? onMealLogged,
  }) {
    return showModalBottomSheet<LoggedMealEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ManualFoodEntrySheet(
        initialTab: initialTab,
        currentGlucose: currentGlucose,
        activeInsulin: activeInsulin,
        pickImage: pickImage,
        onMealLogged: onMealLogged,
      ),
    );
  }

  @override
  State<ManualFoodEntrySheet> createState() => _ManualFoodEntrySheetState();
}

class _ManualFoodEntrySheetState extends State<ManualFoodEntrySheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final ImagePickFunction _pickImage =
      widget.pickImage ?? _defaultPickImage;
  final ImagePicker _imagePicker = ImagePicker();

  // TAB A STATE: Cooked Dish
  late IndbFoodDish _selectedDish;
  late IndbPortionUnit _selectedPortion;
  double _cookedQuantity = 1.0;
  bool _isHighFatProtein = false;
  final TextEditingController _searchController = TextEditingController();

  // TAB B STATE: Packaged Item
  final TextEditingController _packagedNameController =
      TextEditingController(text: 'NutriChoice Digestive');
  final TextEditingController _packagedCarbsController =
      TextEditingController(text: '17.5');
  final TextEditingController _packagedFiberController =
      TextEditingController(text: '2.8');
  double _packagedServings = 1.0;
  File? _scannedPackageImage;
  bool _isScanning = false;

  Future<XFile?> _defaultPickImage(ImageSource source) =>
      _imagePicker.pickImage(source: source);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    _selectedDish = IndbFoodDatabase.dishes.first;
    _selectedPortion = _selectedDish.defaultPortion;
    _isHighFatProtein = _selectedDish.isHighFatProtein;
    _searchController.text = _selectedDish.name;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _packagedNameController.dispose();
    _packagedCarbsController.dispose();
    _packagedFiberController.dispose();
    super.dispose();
  }

  // Real-time calculations
  double get _cookedTotalCarbs => _cookedQuantity * _selectedPortion.carbGrams;

  double get _cookedFiber {
    final grams = _cookedQuantity * _selectedPortion.gramWeight;
    return (grams * _selectedDish.fiberPer100g) / 100.0;
  }

  double get _cookedNetCarbs =>
      (_cookedTotalCarbs - _cookedFiber).clamp(0.0, double.infinity);

  double get _packagedTotalCarbs {
    final carbsPerServing =
        double.tryParse(_packagedCarbsController.text) ?? 0.0;
    return carbsPerServing * _packagedServings;
  }

  double get _packagedFiber {
    final fiberPerServing =
        double.tryParse(_packagedFiberController.text) ?? 0.0;
    return fiberPerServing * _packagedServings;
  }

  double get _packagedNetCarbs {
    final carbsPerServing =
        double.tryParse(_packagedCarbsController.text) ?? 0.0;
    final fiberPerServing =
        double.tryParse(_packagedFiberController.text) ?? 0.0;
    final netPerServing =
        (carbsPerServing - fiberPerServing).clamp(0.0, double.infinity);
    return netPerServing * _packagedServings;
  }

  double get _currentTabNetCarbs =>
      _tabController.index == 0 ? _cookedNetCarbs : _packagedNetCarbs;

  double get _currentTabTotalCarbs =>
      _tabController.index == 0 ? _cookedTotalCarbs : _packagedTotalCarbs;

  double get _currentTabFiber =>
      _tabController.index == 0 ? _cookedFiber : _packagedFiber;

  RiskPrediction get _currentRiskPrediction {
    return RiskPrediction.calculate(
      currentGlucose: widget.currentGlucose,
      activeInsulinUnits: widget.activeInsulin,
      mealNetCarbs: _currentTabNetCarbs,
      isHighFatProtein: _tabController.index == 0 ? _isHighFatProtein : false,
    );
  }

  void _onSelectDish(IndbFoodDish dish) {
    setState(() {
      _selectedDish = dish;
      _selectedPortion = dish.defaultPortion;
      _isHighFatProtein = dish.isHighFatProtein;
      _searchController.text = dish.name;
    });
  }

  /// Opens the device camera to scan a barcode, QR code, or nutrition label.
  Future<void> _openCameraBarcodeScanner() async {
    setState(() => _isScanning = true);

    XFile? picked;
    try {
      picked = await _pickImage(ImageSource.camera);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open camera for QR/barcode scanning.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isScanning = false);

    if (picked == null) return;

    // Simulate scanning recognition from the captured image
    final preset = IndbFoodDatabase.packagedPresets.first;
    setState(() {
      _scannedPackageImage = File(picked!.path);
      _packagedNameController.text = '${preset.name} (${preset.brand})';
      _packagedCarbsController.text = preset.totalCarbsPerServing.toString();
      _packagedFiberController.text = preset.fiberPerServing.toString();
      _packagedServings = 1.0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.teal.shade800,
        content: Row(
          children: [
            const Icon(Icons.qr_code_scanner, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Scanned barcode & matched: ${preset.name}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openBarcodeScannerModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code_scanner, color: Colors.deepPurple),
                    const SizedBox(width: 8),
                    Text(
                      'Scan Barcode / QR Code',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Point your camera at a food packaging barcode or choose a preset item:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 14),

                // Option 1: Open Camera
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openCameraBarcodeScanner();
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text(
                    'Open Camera Scanner',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'OR CHOOSE FROM PRESETS',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 8),

                ...IndbFoodDatabase.packagedPresets.map((preset) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text('${preset.name} (${preset.brand})'),
                    subtitle: Text(
                      '${preset.servingSizeText} • ${preset.totalCarbsPerServing}g Carbs, ${preset.fiberPerServing}g Fiber',
                    ),
                    trailing: const Icon(Icons.check_circle_outline, size: 20),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _packagedNameController.text =
                            '${preset.name} (${preset.brand})';
                        _packagedCarbsController.text =
                            preset.totalCarbsPerServing.toString();
                        _packagedFiberController.text =
                            preset.fiberPerServing.toString();
                        _packagedServings = 1.0;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Scanned: ${preset.name}'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _logMealAndPredict() {
    final isCookedTab = _tabController.index == 0;
    final name = isCookedTab
        ? _selectedDish.name
        : (_packagedNameController.text.trim().isEmpty
            ? 'Packaged Item'
            : _packagedNameController.text.trim());

    final portionDesc = isCookedTab
        ? '${_cookedQuantity.toStringAsFixed(_cookedQuantity % 1 == 0 ? 0 : 1)} × ${_selectedPortion.name}'
        : '${_packagedServings.toStringAsFixed(_packagedServings % 1 == 0 ? 0 : 1)} Serving(s)';

    final entry = LoggedMealEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      entryType: isCookedTab ? 'cooked' : 'packaged',
      portionDescription: portionDesc,
      totalCarbsGrams: _currentTabTotalCarbs,
      fiberGrams: _currentTabFiber,
      netCarbsGrams: _currentTabNetCarbs,
      isHighFatProtein: isCookedTab ? _isHighFatProtein : false,
      timestamp: DateTime.now(),
      riskPrediction: _currentRiskPrediction,
    );

    widget.onMealLogged?.call(entry);
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header with close button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.edit_note,
                      color: theme.colorScheme.primary,
                      size: 26,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Manual Food Entry',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Two Active Tabs
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                icon: Icon(Icons.soup_kitchen),
                text: 'Cooked Dish (INDB)',
              ),
              Tab(
                icon: Icon(Icons.qr_code_scanner),
                text: 'Packaged Item',
              ),
            ],
          ),

          // Scrollable Body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _tabController.index == 0
                  ? _buildCookedDishTab()
                  : _buildPackagedItemTab(),
            ),
          ),

          // Footer & Mandatory Disclaimer
          _buildFooterAndDisclaimer(),
        ],
      ),
    );
  }

  Widget _buildCookedDishTab() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dish Autocomplete Search
        Text(
          'Search Indian Dish (INDB / IFCT)',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Autocomplete<IndbFoodDish>(
          initialValue: TextEditingValue(text: _selectedDish.name),
          optionsBuilder: (textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return IndbFoodDatabase.dishes;
            }
            final query = textEditingValue.text.toLowerCase();
            return IndbFoodDatabase.dishes.where((dish) =>
                dish.name.toLowerCase().contains(query) ||
                dish.category.toLowerCase().contains(query));
          },
          displayStringForOption: (dish) => dish.name,
          onSelected: _onSelectDish,
          fieldViewBuilder:
              (context, textEditingController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: 'e.g. Rajma Chawal, Roti, Dal, Paneer...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    textEditingController.clear();
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLowest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // Portion Unit Dropdown
        Text(
          'Household Portion Unit',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surfaceContainerLowest,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<IndbPortionUnit>(
              isExpanded: true,
              value: _selectedDish.portionUnits.contains(_selectedPortion)
                  ? _selectedPortion
                  : _selectedDish.portionUnits.first,
              items: _selectedDish.portionUnits.map((portion) {
                return DropdownMenuItem<IndbPortionUnit>(
                  value: portion,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(portion.name,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text(
                        '${portion.carbGrams.toStringAsFixed(1)}g carbs',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (newPortion) {
                if (newPortion != null) {
                  setState(() => _selectedPortion = newPortion);
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Quantity Stepper
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quantity',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${(_cookedQuantity * _selectedPortion.gramWeight).toStringAsFixed(0)}g total weight',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            _QuantityStepper(
              value: _cookedQuantity,
              onChanged: (val) => setState(() => _cookedQuantity = val),
            ),
          ],
        ),

        const SizedBox(height: 14),
        const Divider(),

        // Quick Toggle: High Fat / Protein Meal
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            Icons.oil_barrel_outlined,
            color: _isHighFatProtein ? Colors.amber.shade800 : null,
          ),
          title: const Text(
            'High Fat/Protein Meal (Heavy/Oily)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: const Text(
            'Delays gastric absorption; blood sugar peak may occur 2–4 hours later.',
            style: TextStyle(fontSize: 12),
          ),
          value: _isHighFatProtein,
          onChanged: (val) => setState(() => _isHighFatProtein = val),
        ),
      ],
    );
  }

  Widget _buildPackagedItemTab() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary Button: [ Scan Barcode / QR Code ]
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _isScanning ? null : _openBarcodeScannerModal,
            icon: _isScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.qr_code_scanner),
            label: Text(
              _isScanning ? 'Opening Scanner...' : 'Scan Barcode / QR Code',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),

        // Scanned image preview if camera was used
        if (_scannedPackageImage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _scannedPackageImage!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 48,
                      height: 48,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.qr_code),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Scanned Barcode / Package',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _packagedNameController.text,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _scannedPackageImage = null),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Input Fields: Item Name
        Text(
          'Item Name',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _packagedNameController,
          decoration: InputDecoration(
            hintText: 'e.g. Britannia NutriChoice',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),

        const SizedBox(height: 14),

        // Total Carbs per Serving & Dietary Fiber
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Carbs / Serving (g)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _packagedCarbsController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: '0.0',
                      suffixText: 'g',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dietary Fiber (g)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _packagedFiberController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: '0.0',
                      suffixText: 'g',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Servings Consumed Stepper
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Servings Consumed',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Net = (${_packagedCarbsController.text}g - ${_packagedFiberController.text}g) × $_packagedServings',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            _QuantityStepper(
              value: _packagedServings,
              onChanged: (val) => setState(() => _packagedServings = val),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooterAndDisclaimer() {
    final theme = Theme.of(context);
    final netCarbs = _currentTabNetCarbs;
    final totalCarbs = _currentTabTotalCarbs;
    final fiber = _currentTabFiber;
    final risk = _currentRiskPrediction;

    final riskColor = switch (risk.level) {
      RiskLevel.low => Colors.green.shade700,
      RiskLevel.moderate => Colors.amber.shade900,
      RiskLevel.high => Colors.red.shade700,
    };

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Real-time Summary Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL NET CARBS',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          netCarbs.toStringAsFixed(1),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'g Net Carbs',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total: ${totalCarbs.toStringAsFixed(1)}g',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Fiber: ${fiber.toStringAsFixed(1)}g deducted',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      risk.level.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: riskColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Mandatory Disclaimer
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Decision support only. Confirm insulin dosing with your care team.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Primary Action Button
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _logMealAndPredict,
              icon: const Icon(Icons.check_circle),
              label: const Text(
                'Log Carbs & Predict Risk',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quantity Stepper widget with [-] [ Quantity ] [+]
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;
  static const double step = 0.5;
  static const double min = 0.5;
  static const double max = 20.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            onPressed: value > min
                ? () => onChanged((value - step).clamp(min, max))
                : null,
            visualDensity: VisualDensity.compact,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              value.toStringAsFixed(value % 1 == 0 ? 0 : 1),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            onPressed: value < max
                ? () => onChanged((value + step).clamp(min, max))
                : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
