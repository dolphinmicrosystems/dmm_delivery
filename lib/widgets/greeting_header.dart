import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The blue card at the top of both Homes, owner's and driver's: today's
/// date, "Kia ora, Pawan", and one line on how the day is going, with a dot
/// in [tone] ([good], [warn] or [quiet]).
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({
    super.key,
    required this.name,
    required this.summary,
    required this.tone,
    required this.now,
  });

  /// First name only: a greeting that reads out a full name or an email
  /// address stops sounding like one. Null for just "Kia ora".
  final String? name;
  final String summary;
  final Color tone;
  final DateTime now;

  static const good = Color(0xFF86EFAC);
  static const warn = Color(0xFFFFB4B4);
  static const quiet = Colors.white70;

  /// "Pawan" from "Pawan Arora"; null when there is no name to use.
  static String? firstName(String? displayName) {
    final first = displayName?.trim().split(RegExp(r'\s+')).first;
    return first == null || first.isEmpty ? null : first;
  }

  @override
  Widget build(BuildContext context) {
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', //
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brand, AppColors.brandDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${weekdays[now.weekday - 1]} ${now.day} ${months[now.month - 1]}'.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name == null ? 'Kia ora' : 'Kia ora, $name',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    summary,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
