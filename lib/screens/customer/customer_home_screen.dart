import 'package:flutter/material.dart';

import '../../models/saved_address.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _MapHeader()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text('Where to?', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Drop a pin or pick a saved place.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 20, color: AppColors.inkMuted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Search address or place',
                        style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionLabel('Saved addresses'),
              const SizedBox(height: 8),
              SurfaceCard(
                child: Column(
                  children: [
                    for (final address in appState.savedAddresses)
                      _AddressTile(
                        address: address,
                        isLast: address == appState.savedAddresses.last,
                        onTap: appState.confirmDropoff,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Confirm this pin', onPressed: appState.confirmDropoff),
            ]),
          ),
        ),
      ],
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({required this.address, required this.isLast, required this.onTap});

  final SavedAddress address;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(address.icon, size: 18, color: AppColors.brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        address.label,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      if (address.isDefault) ...[
                        const SizedBox(width: 8),
                        const PillBadge(label: 'Default'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address.line,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 220,
          decoration: const BoxDecoration(color: Color(0xFFEEF2F7)),
          child: CustomPaint(painter: _MapPainter()),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RoundIconButton(icon: Icons.menu_rounded),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on, size: 16, color: AppColors.brand),
                    SizedBox(width: 6),
                    Text(
                      'Ponsonby, Auckland',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const _RoundIconButton(icon: Icons.notifications_none_rounded, showDot: true),
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.brand,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Drop-off',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
            const SizedBox(height: 2),
            const Icon(Icons.location_on, size: 34, color: AppColors.brand),
          ],
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, this.showDot = false});

  final IconData icon;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
      ),
      child: Stack(
        children: [
          Center(child: Icon(icon, size: 20, color: AppColors.ink)),
          if (showDot)
            Positioned(
              right: 11,
              top: 11,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final block = Paint()..color = const Color(0xFFE2E8F0);
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 10;
    final park = Paint()..color = const Color(0xFFD7EAD7);
    final water = Paint()..color = const Color(0xFFCFE0EE);

    for (double x = 0; x < size.width; x += 40) {
      for (double y = 0; y < size.height; y += 40) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + 4, y + 4, 16, 16), const Radius.circular(3)),
          block,
        );
      }
    }
    canvas.drawLine(Offset(0, size.height * 0.3), Offset(size.width, size.height * 0.35), road);
    canvas.drawLine(Offset(0, size.height * 0.6), Offset(size.width, size.height * 0.55), road);
    canvas.drawLine(Offset(size.width * 0.35, 0), Offset(size.width * 0.4, size.height), road);

    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.5, size.height * 0.55, 60, 40),
      park,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.85, size.width, size.height * 0.15),
      water,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
