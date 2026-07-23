import 'package:flutter/material.dart';

/// Rootsphere brand palette.
///
/// Derived from the design mockups: warm espresso browns paired with soft
/// cream surfaces, neutral greys for secondary text, and accent colours for
/// status states (open / claimed / verified).
abstract class AppColors {
  AppColors._();

  // Brand — espresso brown used for primary actions and the active tree node.
  static const Color primary = Color(0xFF3B2A20);
  static const Color primaryHover = Color(0xFF4A362A);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Cream surfaces.
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFAF7F4);
  static const Color surfaceMuted = Color(0xFFF3EEE9);
  static const Color cream = Color(0xFFF7F1EA);

  // Text.
  static const Color textPrimary = Color(0xFF1C1917);
  static const Color textSecondary = Color(0xFF6B6660);
  static const Color textTertiary = Color(0xFF9C968E);

  // Borders & dividers.
  static const Color border = Color(0xFFE7E1DA);
  static const Color divider = Color(0xFFEDE8E2);

  // Status accents.
  static const Color statusOpen = Color(0xFFE8920C); // amber — "Open"
  static const Color statusClaimed = Color(0xFF8A8580); // grey — "Claimed"
  static const Color statusVerified = Color(0xFF2E7D5B); // green — "Verified"
  static const Color link = Color(0xFF2563EB); // blue — "Claim ->"

  // Feedback.
  static const Color error = Color(0xFFB3261E);
  static const Color success = Color(0xFF2E7D5B);

  // Avatar tints used on dashboard recent-activity rows.
  static const Color avatarBlue = Color(0xFFDCE7F5);
  static const Color avatarGreen = Color(0xFFD8EBDD);
  static const Color avatarAmber = Color(0xFFF6E6C8);

  // Tree person-card photo tints, keyed by sex.
  static const Color maleTint = Color(0xFF6E86A6); // slate blue
  static const Color femaleTint = Color(0xFFC76A4D); // terracotta
  static const Color neutralTint = Color(0xFF9A938B); // warm grey

  // Tree canvas backgrounds + connectors (theme-aware; chosen in the widget).
  static const Color treeCanvasDark = Color(0xFF3A3735);
  static const Color treeCanvasLight = Color(0xFFF1ECE6);
  static const Color connectorDark = Color(0xFF6F6A65);

  // African ancestry hero palette.
  static const Color sunGold = Color(0xFFEAB53E);
  static const Color sunGoldLight = Color(0xFFF5D47A);
  static const Color heroCream = Color(0xFFFDF8F0);
  static const Color heroText = Color(0xFF2A2118);
}
