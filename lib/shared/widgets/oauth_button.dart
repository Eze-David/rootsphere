import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Outlined "continue with [provider]" button used on the auth screen.
class OAuthButton extends StatelessWidget {
  const OAuthButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[Icon(icon, size: 20), AppSpacing.gapMd, Text(label)],
      ),
    );
  }
}
