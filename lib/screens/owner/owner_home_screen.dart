import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/driver_invitation.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/section_label.dart';
import 'owner_routes_screen.dart';
import 'owner_settings_screen.dart';

/// The Owner's landing screen, ported from owner-home.html: a greeting and
/// three quick actions, rather than a data list. The route list that used to
/// live here moved to OwnerRoutesScreen, behind the "Update routes" action.
class OwnerHomeScreen extends StatelessWidget {
  const OwnerHomeScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    AppLog.owner('OwnerHomeScreen build', {'uid': authState.user?.uid, 'role': authState.role?.name});
    // First name only - the prototype's "Kia ora, Aroha" is a greeting, and
    // a greeting that reads out a full name or an email address stops
    // sounding like one.
    final displayName = authState.user?.displayName?.split(' ').first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Text(
          displayName == null ? 'Kia ora' : 'Kia ora, $displayName',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text("Run today's deliveries.", style: TextStyle(fontSize: 14, color: AppColors.inkMuted)),
        const SizedBox(height: 20),
        const SectionLabel('Quick actions'),
        const SizedBox(height: 12),
        _QuickAction(
          badge: 'Calendar',
          title: 'Delivery roster',
          // Deliberately not faking the prototype's "12 riders scheduled
          // this week": there is no roster data yet, and a made-up number on
          // a real screen is indistinguishable from a broken one.
          subtitle: 'Scheduling not built yet',
          icon: Icons.calendar_month_rounded,
          onPressed: null,
        ),
        const SizedBox(height: 16),
        _InviteQuickAction(authState: authState),
        const SizedBox(height: 16),
        _QuickAction(
          // "Upload sheet" named the file rather than the outcome, and the
          // outcome is the part that isn't obvious: an existing route keeps
          // its name, its stop order and its delivery instructions, and only
          // takes on what this week's sheet actually changed. Owners read
          // "upload" as "replace".
          badge: 'Run sheets',
          title: 'Update routes',
          subtitle: 'Bring a route up to date from its latest PDF',
          icon: Icons.published_with_changes_rounded,
          onPressed: () {
            AppLog.owner('open OwnerRoutesScreen');
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => OwnerRoutesScreen(authState: authState)));
          },
        ),
      ],
    );
  }
}

/// The invites card, with a live count of outstanding invitations in place
/// of the prototype's hardcoded "3 invites pending acceptance".
class _InviteQuickAction extends StatelessWidget {
  const _InviteQuickAction({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: authState.invitations(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('invitations stream failed', snapshot.error, snapshot.stackTrace);
        }
        final docs = snapshot.data?.docs;
        // Counted here rather than queried, because "expired" is a
        // comparison against the clock and Firestore cannot express it as a
        // query that stays true as time passes.
        final now = DateTime.now();
        return _QuickAction(
          badge: 'Invites',
          title: 'Invite riders',
          subtitle: docs == null
              ? 'Checking invitations…'
              : DriverInvitation.rosterSummary(docs.map((doc) => DriverInvitation.fromDoc(doc, now: now))),
          icon: Icons.person_add_alt_1_rounded,
          onPressed: () => showInviteDriverDialog(context, authState),
        );
      },
    );
  }
}

/// One quick-action card. The prototype's shape - a full-width pill-topped
/// band with the icon straddling its lower edge - is the whole visual
/// identity of this screen, so it's reproduced rather than flattened into a
/// stock ListTile.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
  });

  final String badge;
  final String title;
  final String subtitle;
  final IconData icon;

  /// Null disables the card, which dims it rather than removing it - the
  /// action is planned, and hiding it would make the screen look finished.
  final VoidCallback? onPressed;

  /// Height of the tinted band the icon straddles, and the vertical radius
  /// of the dome drawn over it.
  static const _bandHeight = 80.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // The prototype's `rounded-t-[999px]` is a dome as wide as the card and
    // as tall as the tinted band. A plain circular radius can't express
    // that: the card's outline would scale 999 against the card's full
    // height and the band against its own, drawing two different curves -
    // one of which lands as a stray arc across the white body. An explicit
    // ellipse keeps every layer on the same curve at any width.
    return LayoutBuilder(
      builder: (context, constraints) {
        final radius = BorderRadius.vertical(
          top: Radius.elliptical(constraints.maxWidth / 2, _bandHeight),
          bottom: const Radius.circular(20),
        );
        return _buildCard(enabled, radius);
      },
    );
  }

  Widget _buildCard(bool enabled, BorderRadius radius) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.white,
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: radius,
              border: Border.all(color: AppColors.hairline),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.05),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  height: _bandHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.brandSoft,
                          borderRadius: BorderRadius.only(topLeft: radius.topLeft, topRight: radius.topRight),
                        ),
                      ),
                      Positioned(
                        top: 28,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.brand,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.brand.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Icon(icon, color: Colors.white, size: 24),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 36, 20, 18),
                  child: Column(
                    children: [
                      PillBadge(
                        label: badge,
                        background: AppColors.surfaceMuted,
                        foreground: AppColors.inkMuted,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            enabled ? 'Open' : 'Coming soon',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              // A disabled action shouldn't wear the brand
                              // colour that means "tap me".
                              color: enabled ? AppColors.brand : AppColors.inkMuted,
                            ),
                          ),
                          if (enabled)
                            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.brand),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
