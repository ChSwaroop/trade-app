import 'package:flutter/material.dart';

import 'theme.dart';

/// Temporary stand-in for a destination whose feature has not landed yet.
/// Removed as each feature is implemented.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.title,
    required this.message,
    super.key,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, style: AppTypography.headlineMd)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.edge * 2),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(color: AppColors.muted),
          ),
        ),
      ),
    );
  }
}
