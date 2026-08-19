import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import 'owner/owner_home_screen.dart';
import 'owner/owner_settings_screen.dart';
import 'rider/rider_active_screen.dart';
import 'rider/rider_earnings_screen.dart';
import 'rider/rider_orders_screen.dart';

/// Hosts real Owner screens (circuits list + Settings) and, for now, the
/// original prototype's Rider mock tabs for drivers - the driver-facing
/// circuit view (DMM-11+) isn't part of this plan, so a driver's landing
/// experience is unchanged from before this feature. The old Customer/Rider
/// mock toggle is gone entirely: it only ever existed as a placeholder for
/// what's now OwnerHomeScreen.
class RootShell extends StatelessWidget {
  const RootShell({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return authState.role == AuthRole.driver ? _DriverShell(authState: authState) : _OwnerShell(authState: authState);
  }
}

class _OwnerShell extends StatefulWidget {
  const _OwnerShell({required this.authState});

  final AuthState authState;

  @override
  State<_OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<_OwnerShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const _BlueDotAppBar(),
      body: IndexedStack(
        index: _tabIndex,
        children: [OwnerHomeScreen(authState: widget.authState), OwnerSettingsScreen(authState: widget.authState)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

class _DriverShell extends StatefulWidget {
  const _DriverShell({required this.authState});

  final AuthState authState;

  @override
  State<_DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<_DriverShell> {
  final AppState appState = AppState();

  @override
  void initState() {
    super.initState();
    appState.switchRole(AppRole.rider);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final tabIndex = appState.riderTabIndex;
        return Scaffold(
          appBar: const _BlueDotAppBar(),
          body: IndexedStack(
            index: tabIndex,
            children: [
              RiderOrdersScreen(appState: appState),
              RiderActiveScreen(appState: appState),
              RiderEarningsScreen(appState: appState),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tabIndex,
            onDestinationSelected: appState.setRiderTab,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.list_alt_rounded), label: 'Orders'),
              NavigationDestination(icon: Icon(Icons.pedal_bike_outlined), label: 'Active'),
              NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Earnings'),
            ],
          ),
        );
      },
    );
  }
}

class _BlueDotAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _BlueDotAppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 20,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: const Text('B', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          const Text('Blue Dot', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
