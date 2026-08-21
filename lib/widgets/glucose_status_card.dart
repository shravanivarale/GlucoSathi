/// Top Section Tiles: Current Glucose & Active Insulin (IOB).
library;

import 'package:flutter/material.dart';

/// Renders the current glucose reading tile and active insulin (IOB) tile
/// with tap-to-edit capabilities for smooth demonstrations.
class GlucoseStatusCard extends StatelessWidget {
  const GlucoseStatusCard({
    super.key,
    this.glucoseValue = 124,
    this.glucoseTrend = '➔',
    this.activeInsulinUnits = 1.8,
    this.insulinType = 'Regular',
    this.lastReadingTime = '5m ago',
    this.onTapGlucose,
    this.onTapInsulin,
  });

  /// Current glucose level in mg/dL.
  final double glucoseValue;

  /// Trend arrow indicator (e.g. '➔', '↗', '↘', '↑', '↓').
  final String glucoseTrend;

  /// Active Insulin on Board (IOB) in units.
  final double activeInsulinUnits;

  /// Type of insulin, e.g. "Regular", "Rapid-Acting", "Humalog".
  final String insulinType;

  /// Readable timestamp of last glucose reading.
  final String lastReadingTime;

  /// Optional tap callback for editing glucose.
  final VoidCallback? onTapGlucose;

  /// Optional tap callback for editing active insulin.
  final VoidCallback? onTapInsulin;

  Color _getGlucoseColor(BuildContext context) {
    if (glucoseValue < 70) {
      return Colors.red.shade700;
    }
    if (glucoseValue > 180) {
      return Colors.orange.shade800;
    }
    return Colors.teal.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glucoseColor = _getGlucoseColor(context);

    return Row(
      children: [
        // Tile 1: Current Glucose
        Expanded(
          child: Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: glucoseColor.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: InkWell(
              onTap: onTapGlucose,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.water_drop, size: 15, color: glucoseColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Glucose',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                lastReadingTime,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9.5,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.edit_outlined,
                                size: 9,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            glucoseValue.toStringAsFixed(0),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: glucoseColor,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'mg/dL',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            glucoseTrend,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: glucoseColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        glucoseValue < 70
                            ? 'Low (Tap to Edit)'
                            : glucoseValue > 180
                                ? 'Elevated (Tap to Edit)'
                                : 'In Range (Tap to Edit)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: glucoseColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Tile 2: Active Insulin / IOB
        Expanded(
          child: Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: InkWell(
              onTap: onTapInsulin,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.medication_outlined,
                          size: 15,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Active Insulin',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'IOB',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.edit_outlined,
                                size: 9,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${activeInsulinUnits.toStringAsFixed(1)} U',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Active',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$insulinType (Tap to Edit)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
