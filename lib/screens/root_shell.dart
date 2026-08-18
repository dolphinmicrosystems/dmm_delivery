import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import 'customer/customer_home_screen.dart';
import 'customer/customer_receipt_screen.dart';
import 'customer/customer_tracking_screen.dart';
import 'owner/owner_settings_screen.dart';
import 'rider/rider_active_screen.dart';
import 'rider/rider_earnings_screen.dart';
import 'rider/rider_orders_screen.dart';

/// Hosts the existing prototype screens behind real auth. A signed-in
/// driver (AuthRole.driver) is locked to the Rider mock tabs with no
/// Customer/Rider toggle - the Customer-facing mock concept doesn't apply
/// to them. A signed-in owner keeps the original toggle (useful for
/// previewing both) plus a Settings entry for driver invitations, which
/// isn't part of the persistent IndexedStack tabs below - it's pushed on
/// top when tapped, matching "settings at the bottom" as a bottom-bar
/// action rather than a fourth mock data tab.
class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.authState});

  final AuthState authState;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  final AppState appState = AppState();

  bool get _isDriver => widget.authState.role == AuthRole.driver;

  @override
  void initState() {
    super.initState();
    if (_isDriver) {
      appState.switchRole(AppRole.rider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final isCustomer = !_isDriver && appState.role == AppRole.customer;
        final tabIndex = isCustomer ? appState.customerTabIndex : appState.riderTabIndex;
        final screens = isCustomer
            ? [
                CustomerHomeScreen(appState: appState),
                CustomerTrackingScreen(appState: appState),
                CustomerReceiptScreen(appState: appState),
              ]
            : [
                RiderOrdersScreen(appState: appState),
                RiderActiveScreen(appState: appState),
                RiderEarningsScreen(appState: appState),
              ];
        final labels = isCustomer
            ? const ['Home', 'Tracking', 'Receipt']
            : const ['Orders', 'Active', 'Earnings'];
        final icons = isCustomer
            ? const [Icons.home_rounded, Icons.local_shipping_outlined, Icons.receipt_long_outlined]
            : const [Icons.list_alt_rounded, Icons.pedal_bike_outlined, Icons.account_balance_wallet_outlined];

        return Scaffold(
          appBar: AppBar(
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
            actions: [
              if (!_isDriver)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _RoleSwitch(
                    role: appState.role,
                    onChanged: appState.switchRole,
                  ),
                ),
            ],
          ),
          body: IndexedStack(
            index: tabIndex,
            children: screens,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tabIndex,
            onDestinationSelected: (index) {
              if (!_isDriver && index == labels.length) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => OwnerSettingsScreen(authState: widget.authState)),
                );
                return;
              }
              if (isCustomer) {
                appState.setCustomerTab(index);
              } else {
                appState.setRiderTab(index);
              }
            },
            destinations: [
              for (var i = 0; i < labels.length; i++)
                NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
              if (!_isDriver)
                const NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}

class _RoleSwitch extends StatelessWidget {
  const _RoleSwitch({required this.role, required this.onChanged});

  final AppRole role;
  final ValueChanged<AppRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.hairline)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoleChip(label: 'Customer', selected: role == AppRole.customer, onTap: () => onChanged(AppRole.customer)),
          _RoleChip(label: 'Rider', selected: role == AppRole.rider, onTap: () => onChanged(AppRole.rider)),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.inkMuted,
          ),
        ),
      ),
    );
  }
}
