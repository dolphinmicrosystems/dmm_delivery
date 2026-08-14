import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/surface_card.dart';

class CustomerReceiptScreen extends StatelessWidget {
  const CustomerReceiptScreen({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final receipt = appState.receipt;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const StatusDot(label: 'Delivered', color: AppColors.success),
            IconButton(onPressed: () {}, icon: const Icon(Icons.close_rounded)),
          ],
        ),
        Text('Receipt', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Order #${receipt.orderId} · ${receipt.dateTime}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Route', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: AppColors.inkMuted)),
              const SizedBox(height: 12),
              _RouteRow(icon: Icons.storefront_outlined, title: receipt.vendor, subtitle: receipt.vendorAddress),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6, horizontal: 15),
                child: SizedBox(
                  height: 16,
                  child: VerticalDivider(color: AppColors.hairline, thickness: 2),
                ),
              ),
              _RouteRow(icon: Icons.location_on_outlined, title: receipt.dropoffLabel, subtitle: receipt.dropoffAddress),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Items', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: AppColors.inkMuted)),
              const SizedBox(height: 12),
              for (final item in receipt.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text('${item.qty}×', style: const TextStyle(fontSize: 14, color: AppColors.inkMuted)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item.name, style: const TextStyle(fontSize: 14))),
                      Text('\$${item.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              const Divider(height: 24),
              _MoneyRow('Subtotal', receipt.subtotal),
              _MoneyRow('Delivery', receipt.deliveryFee),
              _MoneyRow('GST (15%)', receipt.gst),
              const Divider(height: 24),
              _MoneyRow('Total paid', receipt.total, isTotal: true),
              const SizedBox(height: 8),
              Text('Visa ···· ${receipt.cardLast4}', style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.brandSoft,
                child: Text(receipt.riderInitials, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('How was ${receipt.riderName}?', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => const Icon(Icons.star_rounded, color: AppColors.warning, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Order again', onPressed: () => appState.setCustomerTab(0)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: SecondaryButton(label: 'Download PDF', onPressed: () {})),
            const SizedBox(width: 12),
            Expanded(child: SecondaryButton(label: 'Get help', onPressed: () {})),
          ],
        ),
      ],
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 16, color: AppColors.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(this.label, this.amount, {this.isTotal = false});

  final String label;
  final double amount;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: isTotal ? 16 : 14,
      fontWeight: isTotal ? FontWeight.w800 : FontWeight.w400,
      color: isTotal ? AppColors.ink : AppColors.inkMuted,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('\$${amount.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}
