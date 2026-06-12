import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-navigation shell hosting the five primary destinations
/// (Home · Tree · Records · Collab · Profile) seen across the mockups.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<_Destination> _destinations = <_Destination>[
    _Destination(Icons.home_outlined, Icons.home, 'Home'),
    _Destination(Icons.park_outlined, Icons.park, 'Tree'),
    _Destination(Icons.description_outlined, Icons.description, 'Records'),
    _Destination(Icons.groups_outlined, Icons.groups, 'Collab'),
    _Destination(Icons.person_outline, Icons.person, 'Profile'),
  ];

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: _onTap,
        items: <BottomNavigationBarItem>[
          for (final _Destination d in _destinations)
            BottomNavigationBarItem(
              icon: Icon(d.icon),
              activeIcon: Icon(d.activeIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}
