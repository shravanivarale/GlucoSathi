/// Profile & Clinical Settings screen for GlucoSaathi.
library;

import 'package:flutter/material.dart';
import '../../auth/auth_service.dart';
import '../../models/cgm_connection.dart';
import '../../models/user_profile.dart';
import '../../services/cgm_api_service.dart';
import '../../services/cgm_connection_state.dart';
import '../cgm/connect_cgm_screen.dart';
import '../cgm/cgm_status_screen.dart';

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
  bool _usesInsulin = true;
  String _selectedInsulinType = 'Rapid-acting';

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

    // Refresh CGM connection state from the backend (gets latest last_sync_at).
    CgmConnectionState.instance.refresh().then((_) {
      if (mounted) setState(() {});
    });

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
    _usesInsulin = _profile.usesInsulin;
    _selectedInsulinType = _profile.insulinType;
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
      usesInsulin: _usesInsulin,
      insulinType: _selectedInsulinType,
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

  bool get _hasConnectedCgm =>
      CgmConnectionState.instance.hasConnected;

  CgmProvider? get _connectedProvider =>
      CgmConnectionState.instance.connectedProvider;

  Future<void> _connectCgm() async {
    final result = await Navigator.push<Map<CgmProvider, CgmConnection>>(
      context,
      MaterialPageRoute(
        builder: (_) => ConnectCgmScreen(
          connections: CgmConnectionState.instance.connections,
        ),
      ),
    );

    if (result != null && mounted) {
      CgmConnectionState.instance.connections
        ..clear()
        ..addAll(result);
      setState(() {});
    }
  }

  void _viewCgmStatus() {
    final provider = _connectedProvider;
    if (provider == null) return;
    final connection = CgmConnectionState.instance.connections[provider];
    if (connection == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CgmStatusScreen(connection: connection),
      ),
    );
  }

  Future<void> _disconnectCgm() async {
    final provider = _connectedProvider;
    if (provider == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect CGM'),
        content: Text(
          'Are you sure you want to disconnect ${provider.displayName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      CgmConnectionState.instance.disconnect(provider);
      // Persist disconnect on the backend.
      CgmApiService().disconnectCGM().catchError((_) => CgmBackendStatus(
            providerName: provider.name,
            isConnected: false,
            readingCount: 0,
          ));
      setState(() {});
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

              // Section: Treatment Information
              Text(
                'Treatment Information',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),

              const SizedBox(height: 24),

              // Section: CGM
              Text(
                'Continuous Glucose Monitor',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _hasConnectedCgm
                      ? _ConnectedCgmSummary(
                          provider: _connectedProvider!,
                          connection: CgmConnectionState.instance.connections[_connectedProvider]!,
                          onViewStatus: _viewCgmStatus,
                          onDisconnect: _disconnectCgm,
                        )
                      : _ConnectCgmPrompt(onConnect: _connectCgm),
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

/// CGM prompt card shown when no provider is connected.
class _ConnectCgmPrompt extends StatelessWidget {
  const _ConnectCgmPrompt({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.monitor_heart_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CGM',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Not Connected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Connect your CGM to automatically monitor your glucose levels and receive personalized insights.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onConnect,
            icon: const Icon(Icons.add, size: 18),
            label: const Text(
              'Connect CGM',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}

/// CGM summary card shown when a provider is connected.
class _ConnectedCgmSummary extends StatelessWidget {
  const _ConnectedCgmSummary({
    required this.provider,
    required this.connection,
    required this.onViewStatus,
    required this.onDisconnect,
  });

  final CgmProvider provider;
  final CgmConnection connection;
  final VoidCallback onViewStatus;
  final VoidCallback onDisconnect;

  String _lastSyncedText() {
    if (connection.lastSyncedAt == null) return 'Never';
    final diff = DateTime.now().difference(connection.lastSyncedAt!);
    print('[PROFILE] Timestamp received: ${connection.lastSyncedAt}');
    print('[PROFILE]   diff = ${diff.inSeconds}s → ${diff.inMinutes}m');
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.green.shade700.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.monitor_heart_outlined,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CGM Connected',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                  Text(
                    'Provider: ${provider.displayName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade700.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Connected',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.access_time,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              'Last Synced: ${_lastSyncedText()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onViewStatus,
                icon: const Icon(Icons.analytics_outlined, size: 18),
                label: const Text(
                  'View CGM Status',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text(
                  'Disconnect',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
