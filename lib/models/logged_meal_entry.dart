/// Models for logged meal entries and glycemic risk assessments.
library;

/// Glycemic / hypoglycemia risk prediction levels.
enum RiskLevel {
  low,
  moderate,
  high;

  String get label => switch (this) {
        RiskLevel.low => 'Low Risk',
        RiskLevel.moderate => 'Moderate Risk',
        RiskLevel.high => 'High Risk',
      };
}

/// Dynamic risk prediction result.
class RiskPrediction {
  const RiskPrediction({
    required this.level,
    required this.title,
    required this.explanation,
    required this.recommendedAction,
  });

  final RiskLevel level;
  final String title;
  final String explanation;
  final String recommendedAction;

  /// Computes a clinical decision support risk prediction based on glucose,
  /// active insulin (IOB), and carbs.
  factory RiskPrediction.calculate({
    required double currentGlucose,
    required double activeInsulinUnits,
    double mealNetCarbs = 0,
    bool isHighFatProtein = false,
  }) {
    // Decision logic based on glucose, IOB, and carbs:
    // 1. High Risk: Glucose < 80 mg/dL or IOB > 2.5U with 0 carbs
    // 2. Moderate Risk: Glucose between 80-110 mg/dL with IOB > 1.5U or High Fat/Protein delayed spike
    // 3. Low Risk: Glucose in normal target 90-140 with balanced IOB / meal carbs

    if (currentGlucose < 70) {
      return const RiskPrediction(
        level: RiskLevel.high,
        title: 'Hypoglycemia Alert (< 70 mg/dL)',
        explanation:
            'Blood sugar is below target range. Immediate fast-acting carbs required.',
        recommendedAction: 'Take 15g fast-acting sugar (e.g. 3-4 glucose tabs or juice) and re-check in 15 mins.',
      );
    }

    if (currentGlucose < 90 && activeInsulinUnits > 1.5 && mealNetCarbs < 15) {
      return RiskPrediction(
        level: RiskLevel.high,
        title: 'High Drop Risk Predicted',
        explanation:
            'High active insulin (${activeInsulinUnits}U) relative to current glucose with minimal carbs.',
        recommendedAction: 'Monitor closely. Consider taking 10-15g carbs if trend continues downward.',
      );
    }

    if (isHighFatProtein && mealNetCarbs > 20) {
      return const RiskPrediction(
        level: RiskLevel.moderate,
        title: 'Delayed Glucose Rise Expected',
        explanation:
            'High fat/protein meal slows gastric emptying. Peak glucose rise may be delayed by 2–4 hours.',
        recommendedAction: 'Discuss split or extended bolus dosing with your care team.',
      );
    }

    if (activeInsulinUnits > 2.0 && mealNetCarbs < 30) {
      return RiskPrediction(
        level: RiskLevel.moderate,
        title: 'Moderate Low-Sugar Risk',
        explanation:
            'Active insulin (${activeInsulinUnits}U) exceeds anticipated carb intake.',
        recommendedAction: 'Keep fast-acting snacks accessible. Re-check glucose in 1 hour.',
      );
    }

    if (currentGlucose > 180) {
      return const RiskPrediction(
        level: RiskLevel.moderate,
        title: 'Elevated Glucose',
        explanation: 'Current reading is above target. Carbs will add to glycemic load.',
        recommendedAction: 'Consult your meal bolus calculator or care team guidelines.',
      );
    }

    return const RiskPrediction(
      level: RiskLevel.low,
      title: 'Low Risk — Stable Glycemia',
      explanation: 'Steady glucose expected over the next 2-3 hours with current profile.',
      recommendedAction: 'Confirm insulin dosing with your care team before eating.',
    );
  }
}

/// Representation of a logged meal entry.
class LoggedMealEntry {
  const LoggedMealEntry({
    required this.id,
    required this.name,
    required this.entryType,
    required this.portionDescription,
    required this.totalCarbsGrams,
    required this.fiberGrams,
    required this.netCarbsGrams,
    required this.isHighFatProtein,
    required this.timestamp,
    this.riskPrediction,
  });

  final String id;
  final String name;
  final String entryType; // 'cooked', 'packaged', 'quick_log', 'photo'
  final String portionDescription;
  final double totalCarbsGrams;
  final double fiberGrams;
  final double netCarbsGrams;
  final bool isHighFatProtein;
  final DateTime timestamp;
  final RiskPrediction? riskPrediction;
}
