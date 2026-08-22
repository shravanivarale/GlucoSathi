/// Profile & Clinical Settings screen for GlucoSaathi.
library;

import 'package:flutter/material.dart';
import '../../auth/auth_service.dart';
import '../../models/user_profile.dart';

/// Screen allowing the user to view and edit age, diabetes therapy parameters,
/// and log out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.initialProfile,
    this.authService,
    this.onProfileSaved,
  });

  final UserProfile? initialProfile;
  final AuthService? authService;
  final ValueChanged<UserProfile>? onProfileSaved;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthService _authService = widget.authService ?? AuthService();
  late UserProfile _profile;

  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _weightController;
  late final TextEditingController _targetMinController;
  late final TextEditingController _targetMaxController;
  late final TextEditingController _icrController;
  late final TextEditingController _isfController;
  late final TextEditingController _bolusController;
  late final TextEditingController _basalController;

  String _selectedDiabetesType = 'Type 1';
  bool _isLoggingOut = false;

  final List<String> _diabetesTypes = [
    'Type 1',
    'Type 2',
    'LADA / 1.5',
    'Gestational',
    'Pre-diabetes',
  ];

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile ?? const UserProfile();

    _nameController = TextEditingController(text: _profile.name);
    _ageController = TextEditingController(text: _profile.age.toString());
    _weightController =
        TextEditingController(text: _profile.weightKg.toStringAsFixed(0));
    _targetMinController = TextEditingController(
        text: _profile.targetMinGlucose.toStringAsFixed(0));
    _targetMaxController = TextEditingController(
        text: _profile.targetMaxGlucose.toStringAsFixed(0));
    _icrController = TextEditingController(
        text: _profile.insulinToCarbRatio.toStringAsFixed(0));
    _isfController = TextEditingController(
        text: _profile.insulinSensitivityFactor.toStringAsFixed(0));
    _bolusController = TextEditingController(text: _profile.bolusInsulin);
    _basalController = TextEditingController(text: _profile.basalInsulin);

    _selectedDiabetesType = _profile.diabetesType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _targetMinController.dispose();
    _targetMaxController.dispose();
    _icrController.dispose();
    _isfController.dispose();
    _bolusController.dispose();
    _basalController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    final updated = _profile.copyWith(
      name: _nameController.text.trim(),
      age: int.tryParse(_ageController.text) ?? _profile.age,
      weightKg: double.tryParse(_weightController.text) ?? _profile.weightKg,
      diabetesType: _selectedDiabetesType,
      targetMinGlucose: double.tryParse(_targetMinController.text) ??
          _profile.targetMinGlucose,
      targetMaxGlucose: double.tryParse(_targetMaxController.text) ??
          _profile.targetMaxGlucose,
      insulinToCarbRatio:
          double.tryParse(_icrController.text) ?? _profile.insulinToCarbRatio,
      insulinSensitivityFactor: double.tryParse(_isfController.text) ??
          _profile.insulinSensitivityFactor,
      bolusInsulin: _bolusController.text.trim(),
      basalInsulin: _basalController.text.trim(),
    );

    setState(() => _profile = updated);
    widget.onProfileSaved?.call(updated);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.greenAccent),
            SizedBox(width: 8),
            Text('Profile & Therapy Settings saved!'),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out of GlucoSaathi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoggingOut = true);
    try {
      await _authService.logout();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoggingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to logout: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile & Clinical Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save Profile',
            onPressed: _saveProfile,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User Avatar Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          _nameController.text.isNotEmpty
                              ? _nameController.text[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nameController.text,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _profile.email,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _selectedDiabetesType,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Section: Personal Details
              Text(
                'Personal & Demographic',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Age (Years)',
                        prefixIcon: Icon(Icons.cake_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _weightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Weight (kg)',
                        prefixIcon: Icon(Icons.monitor_weight_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Section: Diabetes Therapy Parameters
              Text(
                'Diabetes Therapy Parameters',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),

              // Diabetes Type Dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedDiabetesType,
                decoration: const InputDecoration(
                  labelText: 'Diabetes Diagnosis Type',
                  prefixIcon: Icon(Icons.medical_services_outlined),
                  border: OutlineInputBorder(),
                ),
                items: _diabetesTypes.map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedDiabetesType = val);
                },
              ),

              const SizedBox(height: 12),

              // Target Glucose Range
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetMinController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Target Min (mg/dL)',
                        border: OutlineInputBorder(),
                        suffixText: 'mg/dL',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _targetMaxController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Target Max (mg/dL)',
                        border: OutlineInputBorder(),
                        suffixText: 'mg/dL',
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ICR and ISF
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _icrController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ICR (1U : X g carbs)',
                        border: OutlineInputBorder(),
                        helperText: 'Insulin-to-Carb Ratio',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _isfController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ISF (1U drops X mg/dL)',
                        border: OutlineInputBorder(),
                        helperText: 'Sensitivity Factor',
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              TextField(
                controller: _bolusController,
                decoration: const InputDecoration(
                  labelText: 'Mealtime (Bolus) Insulin',
                  prefixIcon: Icon(Icons.medication_outlined),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              TextField(
                controller: _basalController,
                decoration: const InputDecoration(
                  labelText: 'Long-Acting (Basal) Insulin',
                  prefixIcon: Icon(Icons.vaccines_outlined),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 24),

              // Save Button
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _saveProfile,
                icon: const Icon(Icons.save_outlined),
                label: const Text(
                  'Save Profile & Settings',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 14),

              // Logout Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isLoggingOut ? null : _logout,
                icon: _isLoggingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout),
                label: const Text(
                  'Log Out',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
