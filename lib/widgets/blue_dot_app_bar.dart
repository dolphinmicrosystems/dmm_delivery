import 'package:flutter/material.dart';

import '../models/business_profile.dart';
import '../services/business_profile_store.dart';
import '../settings/cards/business_card.dart';

/// The header both shells share: the business's logo and name when the owner
/// has set them (Settings -> Business), else the Blue Dot mark and name -
/// plus any [actions] a screen adds.
class BlueDotAppBar extends StatefulWidget implements PreferredSizeWidget {
  const BlueDotAppBar({super.key, this.ownerUid, this.actions});

  /// The business signed in to; null shows plain Blue Dot.
  final String? ownerUid;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<BlueDotAppBar> createState() => _BlueDotAppBarState();
}

class _BlueDotAppBarState extends State<BlueDotAppBar> {
  // One subscription for the bar's life: a new stream on every rebuild (a
  // tab change) would flash the plain Blue Dot mark while it reconnects.
  Stream<BusinessProfile>? _profile;
  String? _for;

  Stream<BusinessProfile>? _stream() {
    final uid = widget.ownerUid;
    if (uid != _for) {
      _for = uid;
      _profile = uid == null ? null : BusinessProfileStore(uid).watch();
    }
    return _profile;
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream();
    return AppBar(
      titleSpacing: 20,
      title: stream == null
          ? const _Brand(profile: BusinessProfile.empty)
          : StreamBuilder<BusinessProfile>(
              stream: stream,
              builder: (context, snapshot) => _Brand(profile: snapshot.data ?? BusinessProfile.empty),
            ),
      actions: widget.actions,
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.profile});

  final BusinessProfile profile;

  @override
  Widget build(BuildContext context) {
    final name = profile.name;
    return Row(
      children: [
        BusinessLogo(profile: profile),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            name == null || name.isEmpty ? 'Blue Dot' : name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
