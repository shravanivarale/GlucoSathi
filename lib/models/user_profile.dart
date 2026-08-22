/// Model for user profile and diabetes therapy settings.
library;

class UserProfile {
  const UserProfile({
    this.name = 'Patient Demo',
    this.email = 'patient@glucosaathi.com',
    this.age = 32,
    this.diabetesType = 'Type 1',
    this.targetMinGlucose = 70,
    this.targetMaxGlucose = 140,
    this.insulinToCarbRatio = 10,
    this.insulinSensitivityFactor = 40,
    this.bolusInsulin = 'Novorapid / Regular',
    this.basalInsulin = 'Lantus / Glargine',
    this.weightKg = 68.0,
  });

  final String name;
  final String email;
  final int age;
  final String diabetesType;
  final double targetMinGlucose;
  final double targetMaxGlucose;
  final double insulinToCarbRatio; // 1 unit per X grams of carbs
  final double insulinSensitivityFactor; // 1 unit drops X mg/dL
  final String bolusInsulin;
  final String basalInsulin;
  final double weightKg;

  UserProfile copyWith({
    String? name,
    String? email,
    int? age,
    String? diabetesType,
    double? targetMinGlucose,
    double? targetMaxGlucose,
    double? insulinToCarbRatio,
    double? insulinSensitivityFactor,
    String? bolusInsulin,
    String? basalInsulin,
    double? weightKg,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      age: age ?? this.age,
      diabetesType: diabetesType ?? this.diabetesType,
      targetMinGlucose: targetMinGlucose ?? this.targetMinGlucose,
      targetMaxGlucose: targetMaxGlucose ?? this.targetMaxGlucose,
      insulinToCarbRatio: insulinToCarbRatio ?? this.insulinToCarbRatio,
      insulinSensitivityFactor:
          insulinSensitivityFactor ?? this.insulinSensitivityFactor,
      bolusInsulin: bolusInsulin ?? this.bolusInsulin,
      basalInsulin: basalInsulin ?? this.basalInsulin,
      weightKg: weightKg ?? this.weightKg,
    );
  }
}
