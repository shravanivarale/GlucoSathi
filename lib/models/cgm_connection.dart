/// Model for CGM (Continuous Glucose Monitor) connection state and mock data.
library;

/// Supported CGM providers.
enum CgmProvider {
  dexcom('Dexcom', 'Connect your Dexcom account to sync glucose readings.',
      true),
  freeStyleLibre(
      'FreeStyle Libre', 'Connect your FreeStyle Libre account.', false),
  other('Other CGM', 'More CGM providers will be supported in the future.', false);

  const CgmProvider(this.displayName, this.description, this.isAvailable);
  final String displayName;
  final String description;
  final bool isAvailable;
}

/// Connection status of the CGM.
enum CgmConnectionStatus {
  notConnected,
  connecting,
  connected,
  syncing,
  connectionError,
  disconnected,
}

/// Represents the current CGM connection state.
class CgmConnection {
  const CgmConnection({
    this.status = CgmConnectionStatus.notConnected,
    this.provider,
    this.connectedAt,
    this.lastSyncedAt,
  });

  final CgmConnectionStatus status;
  final CgmProvider? provider;
  final DateTime? connectedAt;
  final DateTime? lastSyncedAt;

  bool get isConnected => status == CgmConnectionStatus.connected;

  CgmConnection copyWith({
    CgmConnectionStatus? status,
    CgmProvider? provider,
    DateTime? connectedAt,
    DateTime? lastSyncedAt,
  }) {
    return CgmConnection(
      status: status ?? this.status,
      provider: provider ?? this.provider,
      connectedAt: connectedAt ?? this.connectedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

/// Glucose trend direction.
enum GlucoseTrend {
  risingFast('↑↑', 'Rapidly Rising'),
  rising('↑', 'Rising'),
  stable('→', 'Stable'),
  falling('↓', 'Falling'),
  fallingFast('↓↓', 'Rapidly Falling');

  const GlucoseTrend(this.symbol, this.label);
  final String symbol;
  final String label;
}

/// Risk level for glucose readings.
enum GlucoseRisk {
  low('Low', 'green'),
  moderate('Moderate', 'amber'),
  high('High', 'red');

  const GlucoseRisk(this.label, this.colorName);
  final String label;
  final String colorName;
}

/// Mock CGM glucose reading data.
class CgmGlucoseReading {
  const CgmGlucoseReading({
    required this.glucoseMgDl,
    required this.trend,
    required this.risk,
    required this.lastUpdated,
  });

  final int glucoseMgDl;
  final GlucoseTrend trend;
  final GlucoseRisk risk;
  final DateTime lastUpdated;

  /// Returns a mock reading for demo purposes.
  factory CgmGlucoseReading.mock() => CgmGlucoseReading(
        glucoseMgDl: 118,
        trend: GlucoseTrend.stable,
        risk: GlucoseRisk.low,
        lastUpdated: DateTime.now(),
      );
}

/// Backend CGM provider status response.
class CgmBackendStatus {
  const CgmBackendStatus({
    required this.providerName,
    required this.isConnected,
    required this.readingCount,
    this.latestTimestamp,
    this.connectedAt,
    this.lastSyncAt,
  });

  final String providerName;
  final bool isConnected;
  final int readingCount;
  final String? latestTimestamp;
  final String? connectedAt;
  final String? lastSyncAt;

  factory CgmBackendStatus.fromJson(Map<String, dynamic> json) {
    return CgmBackendStatus(
      providerName: json['provider_name'] as String? ?? 'Unknown',
      isConnected: json['is_connected'] as bool? ?? false,
      readingCount: json['reading_count'] as int? ?? 0,
      latestTimestamp: json['latest_timestamp'] as String?,
      connectedAt: json['connected_at'] as String?,
      lastSyncAt: json['last_sync_at'] as String?,
    );
  }
}

/// Backend CGM glucose reading response.
class CgmBackendReading {
  const CgmBackendReading({
    required this.timestamp,
    required this.cbg,
    this.basal = 0.0,
    this.hr = 0.0,
    this.gsr = 0.0,
    this.carbInput = 0.0,
    this.bolus = 0.0,
  });

  final String timestamp;
  final double cbg;
  final double basal;
  final double hr;
  final double gsr;
  final double carbInput;
  final double bolus;

  factory CgmBackendReading.fromJson(Map<String, dynamic> json) {
    return CgmBackendReading(
      timestamp: json['timestamp'] as String? ?? '',
      cbg: (json['cbg'] as num?)?.toDouble() ?? 0.0,
      basal: (json['basal'] as num?)?.toDouble() ?? 0.0,
      hr: (json['hr'] as num?)?.toDouble() ?? 0.0,
      gsr: (json['gsr'] as num?)?.toDouble() ?? 0.0,
      carbInput: (json['carb_input'] as num?)?.toDouble() ?? 0.0,
      bolus: (json['bolus'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Convert to the format expected by the existing glucose predict-raw endpoint.
  Map<String, dynamic> toRawMap() {
    return {
      'timestamp': timestamp,
      'cbg': cbg,
      'basal': basal,
      'hr': hr,
      'gsr': gsr,
      'carbInput': carbInput,
      'bolus': bolus,
    };
  }
}

/// Backend CGM glucose prediction response.
class CgmPrediction {
  const CgmPrediction({
    required this.prediction30Min,
    required this.prediction60Min,
    required this.unit,
    required this.readingsUsed,
    this.totalIob = 0.0,
  });

  final double prediction30Min;
  final double prediction60Min;
  final String unit;
  final int readingsUsed;
  final double totalIob;

  factory CgmPrediction.fromJson(Map<String, dynamic> json) {
    return CgmPrediction(
      prediction30Min:
          (json['prediction_30_min'] as num?)?.toDouble() ?? 0.0,
      prediction60Min:
          (json['prediction_60_min'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] as String? ?? 'mg/dL',
      readingsUsed: json['readings_used'] as int? ?? 0,
      totalIob: (json['total_iob'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
