import 'package:dmm_delivery/models/driver_presence_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 15, 16, 0); // Thursday

  test('online, and when an offline driver was last seen', () {
    expect(const DriverPresenceStatus(online: true).label(now), 'Online now');
    expect(
      DriverPresenceStatus(online: false, changedAt: DateTime(2026, 10, 15, 14, 15)).label(now),
      'Last seen 2:15 pm',
    );
    expect(
      DriverPresenceStatus(online: false, changedAt: DateTime(2026, 10, 14, 7, 0)).label(now),
      'Last seen yesterday',
    );
    expect(
      DriverPresenceStatus(online: false, changedAt: DateTime(2026, 10, 12, 7, 0)).label(now),
      'Last seen Mon 12 Oct',
    );
  });

  test('a driver who never opened the app says so', () {
    expect(DriverPresenceStatus.unknown.label(now), "Hasn't opened the app yet");
    expect(DriverPresenceStatus.fromMap(null).online, isFalse);
  });
}
