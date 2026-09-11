/// Screen for managing CGM provider connections.
library;

import 'package:flutter/material.dart';
import '../../models/cgm_connection.dart';
import 'dexcom_connection_screen.dart';

/// Provider selection and management screen for CGM devices.
///
/// Shows all providers with their current connection status.
/// Each provider manages its own connection state independently.
class ConnectCgmScreen extends StatefulWidget {
  const ConnectCgmScreen({
    super.key,
    required this.connections,
  });

  /// Current connection state for each provider.
  final Map<CgmProvider, CgmConnection> connections;

  @override
  State<ConnectCgmScreen> createState() => _ConnectCgmScreenState();
}

class _ConnectCgmScreenState extends State<ConnectCgmScreen> {
  late Map<CgmProvider, CgmConnection> _connections;

  @override
  void initState() {
    super.initState();
    _connections = Map.of(widget.connections);
  }

  bool _isConnected(CgmProvider provider) =>
      _connections[provider]?.isConnected ?? false;

  Future<void> _connectProvider(CgmProvider provider) async {
    switch (provider) {
      case CgmProvider.dexcom:
        final result = await Navigator.push<CgmConnection>(
          context,
          MaterialPageRoute(
            builder: (_) => const DexcomConnectionScreen(),
          ),
        );
        if (result != null && mounted) {
          _connections[provider] = result;
          Navigator.pop(context, _connections);
        }
        break;
      case CgmProvider.freeStyleLibre:
      case CgmProvider.other:
        break;
    }
  }

  Future<void> _disconnectProvider(CgmProvider provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Provider'),
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
      _connections[provider] = const CgmConnection();
      Navigator.pop(context, _connections);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect your CGM'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose your Continuous Glucose Monitor provider.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              ...CgmProvider.values.map(
                (provider) => _ProviderCard(
                  provider: provider,
                  isConnected: _isConnected(provider),
                  onConnect: provider.isAvailable && !_isConnected(provider)
                      ? () => _connectProvider(provider)
                      : null,
                  onDisconnect: provider.isAvailable && _isConnected(provider)
                      ? () => _disconnectProvider(provider)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.isConnected,
    this.onConnect,
    this.onDisconnect,
  });

  final CgmProvider provider;
  final bool isConnected;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = !provider.isAvailable;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: isDisabled ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isDisabled
                ? theme.colorScheme.outlineVariant.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Opacity(
            opacity: isDisabled ? 0.5 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isConnected
                            ? Colors.green.shade700.withValues(alpha: 0.1)
                            : isDisabled
                                ? theme.colorScheme.surfaceContainerHighest
                                : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.monitor_heart_outlined,
                        color: isConnected
                            ? Colors.green.shade700
                            : isDisabled
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            provider.description,
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
                Row(
                  children: [
                    if (isConnected) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDisabled
                              ? theme.colorScheme.surfaceContainerHighest
                              : theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isDisabled ? 'Coming Soon' : 'Not Connected',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDisabled
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (onConnect != null)
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: onConnect,
                        child: const Text(
                          'Connect',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      )
                    else if (onDisconnect != null)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: onDisconnect,
                        child: const Text(
                          'Disconnect',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
