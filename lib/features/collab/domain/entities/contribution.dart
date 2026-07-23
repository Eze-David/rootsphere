import 'package:flutter/material.dart';

/// A badge earned by contributing to the community record-gathering board.
enum ContributionBadge {
  newcomer,
  helper,
  researcher,
  recordKeeper,
  communityChampion,
}

extension ContributionBadgeX on ContributionBadge {
  String get label {
    switch (this) {
      case ContributionBadge.newcomer:
        return 'Newcomer';
      case ContributionBadge.helper:
        return 'Helper';
      case ContributionBadge.researcher:
        return 'Researcher';
      case ContributionBadge.recordKeeper:
        return 'Record Keeper';
      case ContributionBadge.communityChampion:
        return 'Community Champion';
    }
  }

  String get description {
    switch (this) {
      case ContributionBadge.newcomer:
        return 'Claimed your first opportunity.';
      case ContributionBadge.helper:
        return '5 verified contributions.';
      case ContributionBadge.researcher:
        return '10 verified contributions.';
      case ContributionBadge.recordKeeper:
        return '25 verified contributions.';
      case ContributionBadge.communityChampion:
        return '50 verified contributions.';
    }
  }

  IconData? get icon {
    switch (this) {
      case ContributionBadge.newcomer:
        return Icons.emoji_people;
      case ContributionBadge.helper:
        return Icons.volunteer_activism;
      case ContributionBadge.researcher:
        return Icons.search;
      case ContributionBadge.recordKeeper:
        return Icons.menu_book;
      case ContributionBadge.communityChampion:
        return Icons.workspace_premium;
    }
  }

  static List<ContributionBadge> forVerifiedCount(int count) {
    final List<ContributionBadge> badges = <ContributionBadge>[];
    if (count >= 1) badges.add(ContributionBadge.newcomer);
    if (count >= 5) badges.add(ContributionBadge.helper);
    if (count >= 10) badges.add(ContributionBadge.researcher);
    if (count >= 25) badges.add(ContributionBadge.recordKeeper);
    if (count >= 50) badges.add(ContributionBadge.communityChampion);
    return badges;
  }
}

/// Summary of a user's contributions and reputation on the board.
class UserContribution {
  const UserContribution({
    required this.userId,
    required this.userName,
    this.claimedCount = 0,
    this.verifiedCount = 0,
  });

  final String userId;
  final String userName;
  final int claimedCount;
  final int verifiedCount;

  int get reputation => verifiedCount * 10 + claimedCount * 2;

  List<ContributionBadge> get badges =>
      ContributionBadgeX.forVerifiedCount(verifiedCount);
}
