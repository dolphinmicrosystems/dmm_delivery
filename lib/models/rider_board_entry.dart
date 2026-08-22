import 'package:cloud_firestore/cloud_firestore.dart';

/// Whether a driver is currently running a route. The prototype
/// (owner-maps.html) showed three states - "On route", "Picking up" and
/// "Idle" - but only the first is a real, observable state: the others were
/// placeholder flavour. Anything that isn't actively on a route reads as
/// offline until the backend can distinguish more.
enum RiderPresence {
  onRoute('On route'),
  offline('Offline');

  const RiderPresence(this.label);

  final String label;

  static RiderPresence parse(String? raw) => switch (raw) {
    'on_route' => RiderPresence.onRoute,
    _ => RiderPresence.offline,
  };
}

/// One card on the Owner's Maps board: a driver, the drop they're heading
/// to, and when it lands.
///
/// Deliberately a *summary* of a driver's run rather than the run itself.
/// The board draws one card per driver, so one document per driver means a
/// driver moving repaints exactly one card. The alternative - streaming
/// every delivery_stop and grouping client-side - would push every drop of
/// every driver to every owner device on every stop update, and would have
/// to group on `driver_name`, a display string that firestore.rules cannot
/// gate on and that breaks on duplicates or a rename. The ordered stop list
/// stays where it already is, under delivery_run/{runId}/delivery_stop
/// (`seq_order`), and is read only when drilling into a single rider.
class RiderBoardEntry {
  const RiderBoardEntry({
    required this.riderKey,
    required this.driverName,
    required this.presence,
    this.nextCustomerName,
    this.nextAddress,
    this.etaMinutes,
    this.dropsLeft = 0,
  });

  /// Stable identity for the card. The rider's Firebase uid once the driver
  /// has signed in; the invitation's lowercased email before that, which is
  /// the invitation document id.
  final String riderKey;
  final String driverName;
  final RiderPresence presence;

  /// Company the next drop belongs to - `customer_name` on the run sheet
  /// row, which is a business, not a person.
  final String? nextCustomerName;
  final String? nextAddress;
  final int? etaMinutes;
  final int dropsLeft;

  /// The grey subscript under the driver's name: the company and street
  /// address of the next drop, joined the way the prototype joins them.
  /// Falls back to a state description rather than an empty line, so a card
  /// never renders as a name floating above nothing.
  String get subtitle {
    final parts = [nextCustomerName, nextAddress].whereType<String>().where((p) => p.isNotEmpty);
    if (parts.isEmpty) return presence == RiderPresence.offline ? 'Awaiting run' : 'No next drop';
    return parts.join(' · ');
  }

  /// An offline driver has no next drop, so there is no honest number to
  /// show - the prototype's em dash says "not applicable" where a "0 min"
  /// would read as "arriving now".
  String get etaLabel {
    if (presence == RiderPresence.offline || etaMinutes == null) return '—';
    return '$etaMinutes min';
  }

  /// The live board document the backend owns (see plan.md, "Rider board
  /// data shape"). Not yet written by any deployed function - until it is,
  /// [RiderBoardEntry.fromInvitation] supplies the roster and every driver
  /// reads as offline.
  factory RiderBoardEntry.fromBoardDoc(String riderKey, Map<String, dynamic> data) {
    final nextStop = data['next_stop'] as Map<String, dynamic>?;
    return RiderBoardEntry(
      riderKey: riderKey,
      driverName: data['driver_name'] as String? ?? riderKey,
      presence: RiderPresence.parse(data['presence'] as String?),
      nextCustomerName: nextStop?['customer_name'] as String?,
      nextAddress: nextStop?['address'] as String?,
      etaMinutes: (data['eta_minutes'] as num?)?.toInt(),
      dropsLeft: (data['drops_left'] as num?)?.toInt() ?? 0,
    );
  }

  /// One rider from the `rider-board` endpoint's `riders` array.
  ///
  /// Same field names as [fromBoardDoc] because both describe the same board
  /// entry - the HTTP endpoint shapes its response to match the Firestore
  /// document it will eventually be replaced by, so swapping transports later
  /// doesn't ripple into the widgets.
  factory RiderBoardEntry.fromApiRider(Map<String, dynamic> rider) {
    final nextStop = rider['next_stop'] as Map<String, dynamic>?;
    return RiderBoardEntry(
      riderKey: rider['rider_key'] as String? ?? 'unknown',
      driverName: rider['driver_name'] as String? ?? 'Driver',
      presence: RiderPresence.parse(rider['presence'] as String?),
      nextCustomerName: nextStop?['customer_name'] as String?,
      nextAddress: nextStop?['address'] as String?,
      etaMinutes: (rider['eta_minutes'] as num?)?.toInt(),
      dropsLeft: (rider['drops_left'] as num?)?.toInt() ?? 0,
    );
  }

  /// A driver who accepted an invitation but has no live board document -
  /// which is every driver today. They belong on the board (the owner
  /// invited them, so they expect to see them) with nothing claimed about
  /// where they are.
  factory RiderBoardEntry.fromInvitation(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final email = data['driver_email'] as String? ?? doc.id;
    return RiderBoardEntry(
      riderKey: data['accepted_uid'] as String? ?? doc.id,
      driverName: data['driver_name'] as String? ?? _nameFromEmail(email),
      presence: RiderPresence.offline,
    );
  }

  /// "aimee.grant@wae.co.nz" -> "Aimee Grant". A placeholder until the
  /// backend records a real display name at sign-in: showing a raw email
  /// address where the design shows a person's name makes the whole list
  /// read as debug output.
  static String _nameFromEmail(String email) {
    final local = email.split('@').first;
    final words = local.split(RegExp(r'[._-]+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return email;
    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }
}
