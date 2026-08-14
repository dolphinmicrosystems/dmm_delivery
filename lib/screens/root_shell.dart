import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_colors.dart';
import 'customer/customer_home_screen.dart';
import 'customer/customer_receipt_screen.dart';
import 'customer/customer_tracking_screen.dart';
import 'rider/rider_active_screen.dart';
import 'rider/rider_earnings_screen.dart';
import 'rider/rider_orders_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  final AppState appState = AppState();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final isCustomer = appState.role == AppRole.customer;
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
                  child: const Text('K', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                const Text('Kōwhai', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
            actions: [
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
              if (isCustomer) {
                appState.setCustomerTab(index);
              } else {
                appState.setRiderTab(index);
              }
            },
            destinations: [
              for (var i = 0; i < labels.length; i++)
                NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
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
