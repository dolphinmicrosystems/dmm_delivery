import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../util/app_log.dart';
import 'owner/owner_drivers_screen.dart';
import 'owner/owner_home_screen.dart';
import 'owner/owner_menu_drawer.dart';
import 'owner/owner_routes_screen.dart';
import 'owner/runs_screen.dart';
import 'rider/driver_menu_drawer.dart';
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
    // Note this falls through to the owner shell for *any* non-driver role,
    // including a null one - so log the role that actually drove the choice.
    AppLog.owner('RootShell build', {'role': authState.role?.name, 'uid': authState.user?.uid});
    return authState.role == AuthRole.driver
        ? _DriverShell(authState: authState)
        : _OwnerShell(authState: authState);
  }
}

class _OwnerShell extends StatefulWidget {
  const _OwnerShell({required this.authState});

  final AuthState authState;

  @override
  State<_OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<_OwnerShell> {
  static const _routesTab = 1;

  int _tabIndex = 0;

  void _selectTab(int index) {
    AppLog.owner('owner tab selected', {'index': index});
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // Owner screens are bodies, not Scaffolds: the header (with its
    // hamburger), the end drawer and the bottom bar are identical on every
    // tab, so they're hosted once here and survive tab switches along with
    // each tab's scroll position.
    //
    // Four tabs - the things an owner uses every day. Routes and Drivers
    // used to sit a tap or two deep (Home -> "Update routes", menu ->
    // Settings). More than five would crowd a phone's bar; Alerts is the
    // candidate fifth once drivers deliver through the app.
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const _BlueDotAppBar(),
      endDrawer: OwnerMenuDrawer(authState: widget.authState),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          OwnerHomeScreen(authState: widget.authState, onOpenRoutes: () => _selectTab(_routesTab)),
          OwnerRoutesScreen(authState: widget.authState),
          RunsScreen(authState: widget.authState),
          OwnerDriversScreen(authState: widget.authState),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.alt_route_rounded), label: 'Routes'),
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), label: 'Runs'),
          NavigationDestination(icon: Icon(Icons.people_alt_outlined), label: 'Drivers'),
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
          // Gives Scaffold a hamburger to render - without an endDrawer there
          // was no menu affordance at all, and therefore no way to sign out.
          endDrawer: DriverMenuDrawer(authState: widget.authState),
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
            child: const Text(
              'B',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
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
