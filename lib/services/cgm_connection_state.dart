/// App-level CGM connection state that persists across screen navigation.
///
/// On first access, loads connection state from the backend database.
/// Subsequent changes are written to both the in-memory singleton and
/// the backend via the API.
library;

import '../models/cgm_connection.dart';
import '../services/cgm_api_service.dart';

/// Singleton holding the CGM connection map for the entire app session.
///
/// Because [ProfileScreen] is re-created on every push, widget-level state
/// is lost.  This singleton keeps the connection state alive across
/// navigation so that Connect → Back → Profile still shows Connected.
class CgmConnectionState {
  CgmConnectionState._();
  static final CgmConnectionState instance = CgmConnectionState._();

  final Map<CgmProvider, CgmConnection> connections = {
    CgmProvider.dexcom: const CgmConnection(),
    CgmProvider.freeStyleLibre: const CgmConnection(),
    CgmProvider.other: const CgmConnection(),
  };

  bool _loaded = false;

  /// Load connection state from the backend (once per app session).
  Future<void> loadFromBackend() async {
    if (_loaded) return;
    await _fetchFromBackend();
    _loaded = true;
  }

  /// Force-refresh connection state from the backend.
  Future<void> refresh() async {
    await _fetchFromBackend();
  }

  Future<void> _fetchFromBackend() async {
    try {
      final apiService = CgmApiService();
      final status = await apiService.getCGMStatus();
      if (status.isConnected) {
        final provider = CgmProvider.values.firstWhere(
          (p) => p.name.toLowerCase() == status.providerName.toLowerCase(),
          orElse: () => CgmProvider.dexcom,
        );
        connections[provider] = CgmConnection(
          status: CgmConnectionStatus.connected,
          provider: provider,
          connectedAt: status.connectedAt != null
              ? DateTime.tryParse(status.connectedAt!)
              : null,
          lastSyncedAt: status.lastSyncAt != null
              ? DateTime.tryParse(status.lastSyncAt!)
              : null,
        );
        print('[CGM] CgmConnectionState refreshed: '
              'provider=${provider.name}, '
              'lastSyncedAt=${status.lastSyncAt}');
      }
    } catch (_) {
      // Backend not available — keep current state.
    }
  }

  void connect(CgmProvider provider, CgmConnection connection) {
    connections[provider] = connection;
  }

  void disconnect(CgmProvider provider) {
    connections[provider] = const CgmConnection();
  }

  bool get hasConnected =>
      connections.values.any((c) => c.isConnected);

  CgmProvider? get connectedProvider {
    for (final entry in connections.entries) {
      if (entry.value.isConnected) return entry.key;
    }
    return null;
  }
}
