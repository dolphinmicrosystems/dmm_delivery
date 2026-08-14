/// A delivery job on the rider side: shown in the nearby-orders list, and
/// carries the extra detail needed once it becomes the active delivery.
class RiderJob {
  const RiderJob({
    required this.id,
    required this.vendor,
    required this.payout,
    required this.routeFrom,
    required this.routeTo,
    required this.distanceKm,
    required this.etaMinutes,
    this.badge,
    this.customerName = '',
    this.dropoffAddress = '',
    this.dropoffNotes = '',
    this.nextStepDistanceM = 0,
    this.nextStepInstruction = '',
    this.contactlessDropoff = true,
    this.activeEtaMinutes = 0,
    this.activeEtaTime = '',
  });

  final String id;
  final String vendor;
  final double payout;
  final String routeFrom;
  final String routeTo;
  final double distanceKm;
  final int etaMinutes;
  final String? badge;

  // Populated for the active job.
  final String customerName;
  final String dropoffAddress;
  final String dropoffNotes;
  final int nextStepDistanceM;
  final String nextStepInstruction;
  final bool contactlessDropoff;
  final int activeEtaMinutes;
  final String activeEtaTime;
}
