/// Dexcom CGM connection confirmation screen.
library;

import 'package:flutter/material.dart';
import '../../core/errors/app_failure.dart';
import '../../models/cgm_connection.dart';
import '../../services/cgm_api_service.dart';

/// Confirmation screen before connecting Dexcom.
///
/// In the future this will initiate OAuth flow.
/// For now it simulates a successful connection, then verifies
/// the backend CGM provider status.
class DexcomConnectionScreen extends StatefulWidget {
  const DexcomConnectionScreen({super.key});

  @override
  State<DexcomConnectionScreen> createState() =>
      _DexcomConnectionScreenState();
}

class _DexcomConnectionScreenState extends State<DexcomConnectionScreen> {
  bool _isConnecting = false;
  String? _statusMessage;

  Future<void> _connectDexcom() async {
    print('[CGM-DEBUG] ── FLUTTER: _connectDexcom started ──');
    setState(() {
      _isConnecting = true;
      _statusMessage = null;
    });

    // Simulate connection delay (future: OAuth flow)
    print('[CGM-DEBUG] ── FLUTTER: Simulating 2s connection delay…');
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Verify backend CGM status
    print('[CGM-DEBUG] ── FLUTTER: Calling apiService.connectCGM()…');
    setState(() => _statusMessage = 'Verifying backend status...');

    try {
      final apiService = CgmApiService();
      // Persist connection state on the backend.
      await apiService.connectCGM();
      print('[CGM-DEBUG] ── FLUTTER: connectCGM() succeeded, calling getCGMStatus()…');
      final status = await apiService.getCGMStatus();

      if (!mounted) return;

      print('[CGM-DEBUG] ── FLUTTER: status.isConnected = ${status.isConnected}');
      if (status.isConnected) {
        print('[CGM-DEBUG] ── FLUTTER: Connection successful ✓ ──');
        // Backend confirms mock provider is available
        final result = CgmConnection(
          status: CgmConnectionStatus.connected,
          provider: CgmProvider.dexcom,
          connectedAt: DateTime.now(),
          lastSyncedAt: DateTime.now(),
        );
        Navigator.pop(context, result);
      } else {
        print('[CGM-DEBUG] ── FLUTTER: Backend reports not connected ✗ ──');
        setState(() {
          _isConnecting = false;
          _statusMessage = 'Backend CGM provider is not available. Please try again.';
        });
      }
    } on AppFailure catch (e) {
      if (!mounted) return;
      print('[CGM-DEBUG] ── FLUTTER: AppFailure: ${e.message} ──');
      setState(() {
        _isConnecting = false;
        _statusMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      print('[CGM-DEBUG] ── FLUTTER: Exception: $e ──');
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Could not connect to the CGM service. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Dexcom'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.monitor_heart_outlined,
                  size: 40,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Connect Dexcom',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Connect your Dexcom account to securely sync your glucose readings with GlucoSaathi.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your glucose data will only be used to provide personalized health insights.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isConnecting ? null : _connectDexcom,
                  child: _isConnecting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Connect Dexcom',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
