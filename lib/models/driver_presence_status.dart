import 'package:cloud_firestore/cloud_firestore.dart';

import 'driver_stats.dart';
import 'run_time.dart';

/// Whether a driver has the Blue Dot app open, and since when - one
/// `driver_presence/{uid}` document (DriverPresence writes it as the app is
/// opened and left). What the owner's Drivers tab shows beside each name.
class DriverPresenceStatus {
  const DriverPresenceStatus({required this.online, this.changedAt});

  /// Never opened the app since presence was recorded.
  static const unknown = DriverPresenceStatus(online: false);

  final bool online;

  /// When they last opened (online) or left (offline) the app.
  final DateTime? changedAt;

  static DriverPresenceStatus fromMap(Map<String, dynamic>? data) {
    if (data == null) return unknown;
    final at = data['changed_at'];
    return DriverPresenceStatus(
      online: data['online'] == true,
      changedAt: at is Timestamp ? at.toDate() : (at is DateTime ? at : null),
    );
  }

  /// "Online now", "Last seen 2:15 pm", "Last seen yesterday",
  /// "Last seen Mon 12 Oct", or "Hasn't opened the app yet".
  String label(DateTime now) {
    if (online) return 'Online now';
    final at = changedAt?.toLocal();
    if (at == null) return "Hasn't opened the app yet";
    return switch (relativeDayLabel(at, now)) {
      'Today' => 'Last seen ${formatClock(at.hour, at.minute)}',
      'Yesterday' => 'Last seen yesterday',
      final day => 'Last seen $day',
    };
  }
}
