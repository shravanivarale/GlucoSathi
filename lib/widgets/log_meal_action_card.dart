/// Central "Log Meal" Action Card widget containing 4 entry options.
library;

import 'package:flutter/material.dart';

/// Clean card container with a 2x2 grid offering visual and manual logging options.
class LogMealActionCard extends StatelessWidget {
  const LogMealActionCard({
    super.key,
    required this.onTakePhoto,
    required this.onUploadImage,
    required this.onCookedDish,
    required this.onPackagedItem,
    this.isLoading = false,
  });

  /// Action when "Take Photo" is tapped.
  final VoidCallback onTakePhoto;

  /// Action when "Upload Image" is tapped.
  final VoidCallback onUploadImage;

  /// Action when "Cooked Dish" is tapped.
  final VoidCallback onCookedDish;

  /// Action when "Packaged Item" is tapped.
  final VoidCallback onPackagedItem;

  /// Disables interactions when an analysis is in flight.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.restaurant_menu,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Log Meal',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Visual & Manual',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Top Row (Visual)
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.camera_alt_outlined,
                    label: 'Take Photo',
                    subtitle: 'Camera AI Scan',
                    isFilled: true,
                    onPressed: isLoading ? null : onTakePhoto,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Upload Image',
                    subtitle: 'Gallery Analysis',
                    isTonal: true,
                    onPressed: isLoading ? null : onUploadImage,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Bottom Row (Manual Entry)
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.soup_kitchen_outlined,
                    label: 'Cooked Dish',
                    subtitle: 'INDB / IFCT Indian',
                    isOutlined: true,
                    onPressed: isLoading ? null : onCookedDish,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.qr_code_scanner_outlined,
                    label: 'Packaged Item',
                    subtitle: 'Barcode / Label',
                    isOutlined: true,
                    onPressed: isLoading ? null : onPackagedItem,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onPressed,
    this.isFilled = false,
    this.isTonal = false,
    this.isOutlined = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onPressed;
  final bool isFilled;
  final bool isTonal;
  final bool isOutlined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isFilled) {
      return FilledButton(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (isTonal) {
      return FilledButton.tonal(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Default Outlined
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 1.2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
