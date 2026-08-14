enum TripStatus { delivered, delayed }

class RecentTrip {
  const RecentTrip({
    required this.vendor,
    required this.status,
    required this.time,
    required this.distanceKm,
    required this.payout,
  });

  final String vendor;
  final TripStatus status;
  final String time;
  final double distanceKm;
  final double payout;
}
