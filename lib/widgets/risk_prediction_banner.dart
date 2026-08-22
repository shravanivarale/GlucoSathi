/// Dynamic Risk Banner widget (Green / Yellow / Red).
library;

import 'package:flutter/material.dart';
import '../models/logged_meal_entry.dart';

/// Renders a color-coded dynamic risk banner with contextual explanations
/// and recommendations.
class RiskPredictionBanner extends StatelessWidget {
  const RiskPredictionBanner({
    super.key,
    required this.prediction,
    this.onTapDetails,
  });

  final RiskPrediction prediction;
  final VoidCallback? onTapDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (Color bgColor, Color borderColor, Color textColor, IconData icon) =
        switch (prediction.level) {
      RiskLevel.low => (
          Colors.green.shade50,
          Colors.green.shade400,
          Colors.green.shade900,
          Icons.check_circle_outline,
        ),
      RiskLevel.moderate => (
          Colors.amber.shade50,
          Colors.amber.shade600,
          Colors.amber.shade900,
          Icons.warning_amber_rounded,
        ),
      RiskLevel.high => (
          Colors.red.shade50,
          Colors.red.shade600,
          Colors.red.shade900,
          Icons.error_outline,
        ),
    };

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: textColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  prediction.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: borderColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  prediction.level.label.toUpperCase(),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            prediction.explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor.withValues(alpha: 0.9),
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
          if (prediction.recommendedAction.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.arrow_right,
                  size: 16,
                  color: textColor,
                ),
                Expanded(
                  child: Text(
                    prediction.recommendedAction,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
