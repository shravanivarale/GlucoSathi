/// CGM Status screen with continuous polling and automatic prediction.
library;

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../core/errors/app_failure.dart';
import '../../models/cgm_connection.dart';
import '../../services/cgm_api_service.dart';
import '../../services/cgm_connection_state.dart';
import '../../services/insulin_api_service.dart';

/// Screen that displays live CGM glucose data with automatic polling.
///
/// Polls ``GET /api/v1/cgm/reading/latest`` on a timer, maintains a rolling
/// history of the latest 24 readings, and automatically runs the ONNX
/// prediction pipeline once sufficient history is available.
class CgmStatusScreen extends StatefulWidget {
  const CgmStatusScreen({super.key, required this.connection});

  final CgmConnection connection;

  @override
  State<CgmStatusScreen> createState() => _CgmStatusScreenState();
}

class _CgmStatusScreenState extends State<CgmStatusScreen>
    with WidgetsBindingObserver {
  final _apiService = CgmApiService();
  final _insulinApi = InsulinApiService();
  Timer? _pollTimer;

  CgmBackendReading? _latestReading;
  CgmPrediction? _prediction;
  final List<CgmBackendReading> _readings = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isPredicting = false;

  /// Current IOB fetched from the backend (single source of truth).
  double _currentIob = 0.0;

  /// Tracks whether at least one prediction has succeeded.
  /// Once true, [_prediction] is never cleared — stale values persist
  /// until a fresh prediction replaces them.
  bool _hasPrediction = false;

  /// When the app was last paused (for detecting stale data on resume).
  DateTime? _pausedAt;

  /// Polling interval — 5 minutes, matching real CGM reading cadence.
  static const _pollInterval = Duration(minutes: 5);

  /// Maximum readings kept in the rolling history window.
  static const _maxReadings = 24;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitialData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      print('[CGM-REFRESH] App paused at $_pausedAt');
    } else if (state == AppLifecycleState.resumed) {
      final pausedDuration = _pausedAt != null
          ? DateTime.now().difference(_pausedAt!)
          : Duration.zero;
      print('[CGM-REFRESH] App resumed after ${pausedDuration.inSeconds}s');
      _pausedAt = null;
      // If we were paused for longer than the poll interval, fetch immediately.
      if (pausedDuration >= _pollInterval) {
        print('[CGM-REFRESH] Stale data detected — polling immediately');
        _pollLatestReading();
      }
    }
  }

  // ── Data loading ────────────────────────────────────────────────────

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch the latest 24 readings immediately so the prediction
      // pipeline can run right away without waiting to collect them.
      final history = await _apiService.getCGMHistory(limit: _maxReadings);
      if (!mounted) return;

      final latest = history.isNotEmpty ? history.first : null;
      setState(() {
        _latestReading = latest;
        _readings
          ..clear()
          ..addAll(history);
        _isLoading = false;
      });
      _startPolling();
      _runPrediction();

      // Fetch IOB immediately — doesn't depend on CGM readings.
      _fetchIOB();

      // If the latest reading is stale (older than the poll interval),
      // immediately fetch a fresh one so the UI shows "Just now".
      if (latest != null) {
        final age = DateTime.now().difference(
          DateTime.parse(latest.timestamp).toLocal(),
        );
        if (age >= _pollInterval) {
          print('[CGM-REFRESH] Initial load stale (${age.inSeconds}s old) '
              '— fetching fresh reading');
          _pollLatestReading();
        }
      }
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Could not connect to the CGM service. Please try again.';
        _isLoading = false;
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollLatestReading());
    print('[CGM-REFRESH] Timer started: interval=$_pollInterval');
  }

  Future<void> _pollLatestReading() async {
    print('[CGM-REFRESH] ─── Timer triggered at ${DateTime.now()} ───');
    try {
      final reading = await _apiService.getLatestCGMReading();
      if (!mounted) return;

      print('[CGM-REFRESH] New reading fetched: ts=${reading.timestamp}, cbg=${reading.cbg}');
      print('[CGM-REFRESH] Previous:  ts=${_latestReading?.timestamp}');

      final isNew = _latestReading?.timestamp != reading.timestamp;

      // Always update the latest reading and refresh UI.
      final oldOldest = _readings.isNotEmpty ? _readings.last.timestamp : 'none';
      setState(() {
        _latestReading = reading;
        if (isNew) {
          _readings.insert(0, reading);
          if (_readings.length > _maxReadings) {
            _readings.removeLast();
          }
        }
      });

      if (isNew) {
        final newOldest = _readings.last.timestamp;
        print('[CGM-REFRESH] ✅ NEW reading added to rolling window');
        print('[CGM-REFRESH]   Window: ${_readings.length} readings '
            '[${newOldest} → ${_readings.first.timestamp}]');

        // Update CgmConnectionState singleton so Profile screen
        // shows the same sync time as CGM Status screen.
        final provider = CgmConnectionState.instance.connectedProvider;
        if (provider != null) {
          final old = CgmConnectionState.instance.connections[provider];
          CgmConnectionState.instance.connections[provider] = old!.copyWith(
            lastSyncedAt: DateTime.now(),
          );
          print('[CGM] Profile lastSyncedAt updated: ${DateTime.now()}');
        }
      } else {
        print('[CGM-REFRESH] Same timestamp — UI refreshed, running prediction for IOB recalc');
      }

      // ALWAYS run prediction to recalculate IOB with current timestamps.
      _runPrediction();
    } catch (e) {
      print('[CGM-REFRESH] ❌ Error: $e');
    }
  }

  // ── Prediction ──────────────────────────────────────────────────────

  Future<void> _runPrediction() async {
    print('[CGM-REFRESH] ─── Prediction started ───');
    print('[CGM-REFRESH]   Readings in window: ${_readings.length}');
    setState(() => _isPredicting = true);

    try {
      final prediction = await _apiService.predictFromCGM();
      if (!mounted) {
        _isPredicting = false;
        return;
      }
      print('[CGM-REFRESH] ✅ Prediction completed');
      print('[CGM-REFRESH]   30-min: ${prediction.prediction30Min} mg/dL');
      print('[CGM-REFRESH]   60-min: ${prediction.prediction60Min} mg/dL');
      print('[CGM-REFRESH]   Readings used: ${prediction.readingsUsed}');
      print('[CGM-REFRESH]   Total IOB (from prediction): ${prediction.totalIob} U');
      setState(() {
        _prediction = prediction;
        _hasPrediction = true;
      });

      // Fetch IOB from the dedicated endpoint (single source of truth).
      await _fetchIOB();

      if (mounted) setState(() => _isPredicting = false);
      print('[CGM-REFRESH]   UI updated with fresh prediction');
    } catch (e) {
      print('[CGM-REFRESH] ❌ Prediction error: $e');
      if (mounted) setState(() => _isPredicting = false);
    }
  }

  /// Fetch current IOB from the backend (single source of truth).
  Future<void> _fetchIOB() async {
    try {
      final iob = await _insulinApi.getIOB();
      if (!mounted) return;
      setState(() {
        _currentIob = iob.totalIob;
      });
      print('[CGM-REFRESH]   IOB from backend: ${iob.totalIob} U '
          '(rapid=${iob.iobRapid}, regular=${iob.iobRegular}, nph=${iob.iobNph})');
    } catch (_) {
      // Non-critical: keep previous IOB if backend unreachable.
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  Color _glucoseColor(BuildContext context) {
    final glucose = _latestReading?.cbg ?? 0;
    if (glucose < 70) return Colors.red.shade700;
    if (glucose <= 140) return Colors.teal.shade700;
    return Colors.orange.shade800;
  }

  String _glucoseRangeLabel() {
    final glucose = _latestReading?.cbg ?? 0;
    if (glucose < 70) return 'Low';
    if (glucose <= 140) return 'In Range';
    return 'Elevated';
  }

  String _lastUpdatedText() {
    final ts = _latestReading?.timestamp;
    if (ts == null || ts.isEmpty) return 'Never';
    try {
      final dt = DateTime.parse(ts).toLocal();
      final diff = DateTime.now().difference(dt);
      print('[CGM STATUS] Timestamp received: $ts');
      print('[CGM STATUS]   diff = ${diff.inSeconds}s → ${diff.inMinutes}m');
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return ts;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CGM Status'),
        actions: [
          if (_latestReading != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Live',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _ErrorState(
                    message: _errorMessage!,
                    onRetry: _loadInitialData,
                  )
                : _buildContent(theme),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Current Glucose Card
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    'Current Glucose',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(_latestReading?.cbg ?? 0).toStringAsFixed(0)} mg/dL',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _glucoseColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _glucoseColor(context).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _glucoseRangeLabel(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _glucoseColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Last Updated + Reading Count
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Last Updated',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _lastUpdatedText(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Readings Collected',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_readings.length} / $_maxReadings',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Glucose Trend Graph
          Text(
            'Glucose Trend',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          _GlucoseTrendGraph(readings: _readings),
          const SizedBox(height: 24),

          // Prediction Section
          Text(
            'Glucose Prediction',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _PredictionCard(
                  title: '30 Minutes',
                  value: _prediction != null
                      ? '${_prediction!.prediction30Min.toStringAsFixed(0)} mg/dL'
                      : 'Collecting…',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PredictionCard(
                  title: '60 Minutes',
                  value: _prediction != null
                      ? '${_prediction!.prediction60Min.toStringAsFixed(0)} mg/dL'
                      : 'Collecting…',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _prediction != null
                ? 'Based on ${_prediction!.readingsUsed} CGM readings'
                : 'Collecting CGM readings for prediction…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),

          if (_isPredicting && _hasPrediction) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Refreshing prediction…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],

          // Active Insulin section
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer
                  .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.medication_outlined,
                      size: 18,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Active Insulin (IOB)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _hasPrediction
                      ? '${_currentIob.toStringAsFixed(2)} U'
                      : 'Collecting…',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Information Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your CGM readings are automatically updated every 5 minutes '
                    'and processed by GlucoSaathi to provide glucose trends and '
                    'personalized risk insights.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

/// Error state widget with retry button.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Connection Error',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glucose trend line graph showing recent CGM readings over time.
class _GlucoseTrendGraph extends StatelessWidget {
  const _GlucoseTrendGraph({required this.readings});

  final List<CgmBackendReading> readings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (readings.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No CGM history available yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    // Readings are newest-first; reverse for chronological display.
    final chronological = readings.reversed.toList();

    final spots = <FlSpot>[];
    for (var i = 0; i < chronological.length; i++) {
      spots.add(FlSpot(i.toDouble(), chronological[i].cbg));
    }

    final glucoseValues = chronological.map((r) => r.cbg).toList();
    final minY = (glucoseValues.reduce((a, b) => a < b ? a : b) - 20)
        .clamp(0.0, double.infinity);
    final maxY = glucoseValues.reduce((a, b) => a > b ? a : b) + 20;

    // Build time labels for the X axis.
    final timeLabels = <int, String>{};
    final step = (chronological.length / 6).ceil().clamp(1, chronological.length);
    for (var i = 0; i < chronological.length; i += step) {
      final ts = chronological[i].timestamp;
      if (ts.isNotEmpty) {
        try {
          final dt = DateTime.parse(ts).toLocal();
          timeLabels[i] = '${dt.hour.toString().padLeft(2, '0')}:'
              '${dt.minute.toString().padLeft(2, '0')}';
        } catch (_) {
          timeLabels[i] = '';
        }
      }
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: 0,
                  maxX: (chronological.length - 1).toDouble(),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: ((maxY - minY) / 4).clamp(1.0, double.infinity),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: ((maxY - minY) / 4).clamp(1.0, double.infinity),
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: step.toDouble(),
                        getTitlesWidget: (value, meta) {
                          final label = timeLabels[value.toInt()];
                          if (label == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) =>
                          theme.colorScheme.inverseSurface.withValues(alpha: 0.9),
                      getTooltipItems: (spots) {
                        return spots.map((spot) {
                          final idx = spot.x.toInt();
                          final label = idx < chronological.length
                              ? '${spot.y.toStringAsFixed(0)} mg/dL'
                              : '${spot.y.toStringAsFixed(0)}';
                          return LineTooltipItem(
                            label,
                            TextStyle(
                              color: theme.colorScheme.onInverseSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          );
                        }).toList();
                      },
                    ),
                    handleBuiltInTouches: true,
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: theme.colorScheme.primary,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: spots.length <= 12,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                          radius: 3,
                          color: theme.colorScheme.primary,
                          strokeColor: theme.colorScheme.surface,
                          strokeWidth: 1.5,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prediction result card.
class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
