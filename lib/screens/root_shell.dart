import 'package:flutter/material.dart';

import '../driver/driver_shell.dart';
import '../state/auth_state.dart';
import '../util/app_log.dart';
import '../widgets/blue_dot_app_bar.dart';
import 'owner/owner_drivers_screen.dart';
import 'owner/owner_home_screen.dart';
import 'owner/owner_menu_drawer.dart';
import 'owner/owner_routes_screen.dart';
import 'owner/runs_screen.dart';

/// Picks the shell for the signed-in role: drivers get DriverShell
/// (lib/driver/), everyone else the owner's four tabs below. The old
/// Customer/Rider mock toggle is gone entirely: it only ever existed as a
/// placeholder for what's now OwnerHomeScreen.
class RootShell extends StatelessWidget {
  const RootShell({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    // Note this falls through to the owner shell for *any* non-driver role,
    // including a null one - so log the role that actually drove the choice.
    AppLog.owner('RootShell build', {'role': authState.role?.name, 'uid': authState.user?.uid});
    return authState.role == AuthRole.driver
        ? DriverShell(authState: authState)
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
      appBar: const BlueDotAppBar(),
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
