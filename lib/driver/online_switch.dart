import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../util/app_log.dart';
import 'driver_presence.dart';

/// "Online" / "Offline" and a switch, in the driver's app bar.
///
/// Flipping it saves `driver_presence/{uid}` (DriverPresence), shows the
/// driver "You're online", and the backend tells their owners. It starts from
/// what is saved, so it is right after the app was closed - a driver who left
/// it on is still online.
class OnlineSwitch extends StatefulWidget {
  const OnlineSwitch({super.key, required this.authState});

  final AuthState authState;

  @override
  State<OnlineSwitch> createState() => _OnlineSwitchState();
}

class _OnlineSwitchState extends State<OnlineSwitch> {
  late final Stream<bool> _presence = DriverPresence.watch(widget.authState.user!.uid);

  /// What the driver just chose, shown until Firestore confirms it, so the
  /// switch moves under their thumb rather than a beat later.
  bool? _pending;

  Future<void> _set(bool online) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending = online);
    try {
      await DriverPresence.set(
        uid: widget.authState.user!.uid,
        ownerUid: widget.authState.ownerUid!,
        online: online,
      );
    } on FirebaseException catch (error, stack) {
      AppLog.auth.error('presence write failed', error, stack, {'online': online});
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't switch ${online ? 'online' : 'offline'}. Check your connection.")),
      );
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _presence,
      builder: (context, snapshot) {
        final online = _pending ?? snapshot.data ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              online ? 'Online' : 'Offline',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: online ? AppColors.success : AppColors.inkMuted,
              ),
            ),
            Switch(
              value: online,
              activeThumbColor: AppColors.brand,
              onChanged: snapshot.hasData ? _set : null,
            ),
          ],
        );
      },
    );
  }
}
