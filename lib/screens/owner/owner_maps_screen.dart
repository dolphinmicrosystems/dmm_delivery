import 'package:flutter/material.dart';

import '../../models/rider_board_entry.dart';
import '../../services/rider_board_api.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';
import 'owner_rider_screen.dart';

/// The Maps tab from owner-maps.html: the drivers running today's drops, one
/// card each, with the stop they're heading to and its ETA.
///
/// The prototype rendered a map above this list; this port drops it. The
/// list is the screen - a fixed map panel would eat the top third of the
/// canvas to show pins the owner can't act on, while pushing the cards
/// (which are the actual controls) into a cramped sheet. Per-route
/// geography already has a dedicated full-screen map in RouteMapScreen.
///
/// Fed by the rider-board Cloud Function rather than a Firestore stream, so
/// it's a pull-to-refresh screen, not a live one. The endpoint reads this
/// owner's drivers and runs from Firestore, scoped to the `owner_uid` claim
/// on the caller's token - it used to walk the whole run_sheets bucket, which
/// meant every owner's board showed every other owner's customers.
///
/// One card per driver on this owner's roster. A driver with no run assigned
/// reads as offline with nothing claimed about them, which is the truth for
/// every driver today: nothing sets `delivery_run.rider_id` yet. Routes with
/// no driver are called out above the list rather than being invisible.
class OwnerMapsScreen extends StatefulWidget {
  const OwnerMapsScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<OwnerMapsScreen> createState() => _OwnerMapsScreenState();
}

class _OwnerMapsScreenState extends State<OwnerMapsScreen> {
  final RiderBoardApi _api = RiderBoardApi();
  late Future<RiderBoard> _board;

  @override
  void initState() {
    super.initState();
    _board = _load();
  }

  Future<RiderBoard> _load() {
    AppLog.owner('OwnerMapsScreen loading board', {'uid': widget.authState.user?.uid});
    // No client-side sort any more: the server already returns busiest first,
    // and two orderings of the same list is how they come to disagree.
    return _api.fetchBoard();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _board = future);
    // Awaited so RefreshIndicator keeps spinning until the request settles;
    // swallowed because the FutureBuilder below is what renders the failure.
    await future.catchError((_) => const RiderBoard(riders: []));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<RiderBoard>(
        future: _board,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            AppLog.owner.error('rider board load failed', snapshot.error, snapshot.stackTrace);
            return _Scrollable(
              child: _BoardMessage(
                icon: Icons.error_outline_rounded,
                title: 'Couldn\'t load the board',
                body: '${snapshot.error}\n\nPull down to try again.',
              ),
            );
          }

          final board = snapshot.data ?? const RiderBoard(riders: []);
          final riders = board.riders;
          AppLog.owner('rider board rendered', {
            'total': riders.length,
            'live': board.liveCount,
            'unassigned': board.unassignedRuns.length,
          });

          if (riders.isEmpty) {
            return const _Scrollable(
              child: _BoardMessage(
                icon: Icons.groups_outlined,
                title: 'No drivers yet',
                // Names the actual next step. The board is a roster now, not
                // a view of the bucket - uploading a sheet adds no drivers.
                body:
                    'Register a driver in Settings, and they appear here '
                    'once they accept and sign in.',
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  '${board.liveCount} of ${riders.length} with a route to deliver',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (board.unassignedNotice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0x1AE4A83A),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.warning),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            board.unassignedNotice!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: SectionLabel('Drivers')),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: riders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _RiderCard(entry: riders[index]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// RefreshIndicator only fires on a scrollable child, and both the empty and
/// error states are shorter than the screen - without this they'd be the two
/// states you most need to retry from and can't.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.entry});

  final RiderBoardEntry entry;

  @override
  Widget build(BuildContext context) {
    final isLive = entry.presence == RiderPresence.onRoute;
    return InkWell(
      onTap: () {
        AppLog.owner('open OwnerRiderScreen', {'riderKey': entry.riderKey});
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => OwnerRiderScreen(entry: entry)));
      },
      borderRadius: BorderRadius.circular(20),
      child: _cardBody(isLive),
    );
  }

  Widget _cardBody(bool isLive) {
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isLive ? AppColors.brandSoft : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.local_shipping_rounded,
              size: 20,
              color: isLive ? AppColors.brand : AppColors.inkMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.driverName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusDot(
                      label: entry.presence.label,
                      color: isLive ? AppColors.success : AppColors.inkMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // Company then street address, the two run-sheet fields that
                // together say where this driver is actually heading.
                Text(
                  entry.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                entry.etaLabel,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isLive ? AppColors.ink : AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'ETA',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoardMessage extends StatelessWidget {
  const _BoardMessage({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: AppColors.inkMuted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
