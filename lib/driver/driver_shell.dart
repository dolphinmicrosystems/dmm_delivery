import 'package:flutter/material.dart';

import '../notifications/notification_permission_banner.dart';
import '../state/auth_state.dart';
import '../widgets/blue_dot_app_bar.dart';
import 'driver_data.dart';
import 'driver_home_screen.dart';
import 'driver_menu_drawer.dart';
import 'driver_routes_screen.dart';
import 'driver_runs_screen.dart';
import 'online_switch.dart';

/// Everything a driver sees once signed in: the Online switch in the bar,
/// and three tabs - Home (the run live now, or the next one), Runs (Upcoming /
/// Today / Past) and Routes.
///
/// Replaces the original prototype's mock tabs (Orders / Active / Earnings),
/// which showed made-up jobs and earnings to real drivers. All three tabs read the
/// same live data (DriverDataBuilder), gathered once here.
class DriverShell extends StatefulWidget {
  const DriverShell({super.key, required this.authState});

  final AuthState authState;

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: BlueDotAppBar(
        actions: [
          OnlineSwitch(authState: widget.authState),
          // Scaffold puts the menu button here once actions are given, so it
          // is added back explicitly.
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: DriverMenuDrawer(authState: widget.authState),
      body: Column(
        children: [
          const NotificationPermissionBanner(),
          Expanded(
            child: DriverDataBuilder(
              authState: widget.authState,
              builder: (context, data) => IndexedStack(
                index: _tab,
                children: [
                  DriverHomeScreen(authState: widget.authState, data: data),
                  DriverRunsScreen(authState: widget.authState, data: data),
                  DriverRoutesScreen(authState: widget.authState, data: data),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), label: 'Runs'),
          NavigationDestination(icon: Icon(Icons.alt_route_rounded), label: 'Routes'),
        ],
      ),
    );
  }
}
