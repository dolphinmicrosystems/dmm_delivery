import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The header both shells share: the Blue Dot mark and name, plus whatever
/// [actions] a shell adds (the driver's Online switch).
class BlueDotAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BlueDotAppBar({super.key, this.actions});

  final List<Widget>? actions;

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
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
