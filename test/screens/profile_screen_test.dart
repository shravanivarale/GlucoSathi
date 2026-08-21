import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glucosaathi/models/user_profile.dart';
import 'package:glucosaathi/screens/profile/profile_screen.dart';

void main() {
  group('ProfileScreen Widget Tests', () {
    testWidgets('renders user demographic and clinical therapy settings',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      UserProfile? savedProfile;

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            initialProfile: const UserProfile(
              name: 'Dr. Sharma',
              age: 42,
              diabetesType: 'Type 1',
              targetMinGlucose: 80,
              targetMaxGlucose: 150,
              insulinToCarbRatio: 12,
              insulinSensitivityFactor: 45,
            ),
            onProfileSaved: (profile) => savedProfile = profile,
          ),
        ),
      );

      // Verify fields
      expect(find.text('User Profile & Clinical Settings'), findsOneWidget);
      expect(find.text('Dr. Sharma'), findsWidgets);
      expect(find.text('Personal & Demographic'), findsOneWidget);
      expect(find.text('Diabetes Therapy Parameters'), findsOneWidget);
      expect(find.text('Save Profile & Settings'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);

      // Edit age
      final ageField = find.widgetWithText(TextField, '42');
      await tester.enterText(ageField, '43');
      await tester.pumpAndSettle();

      // Tap Save Profile
      await tester.tap(find.text('Save Profile & Settings'));
      await tester.pumpAndSettle();

      expect(savedProfile, isNotNull);
      expect(savedProfile!.age, 43);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Profile & Therapy Settings saved!'), findsOneWidget);
    });

    testWidgets('shows confirmation dialog when Log Out is tapped',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );

      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to log out of GlucoSaathi?'),
          findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Log Out'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to log out of GlucoSaathi?'),
          findsNothing);
    });
  });
}
