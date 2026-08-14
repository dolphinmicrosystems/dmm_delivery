class CustomerOrder {
  const CustomerOrder({
    required this.id,
    required this.status,
    required this.etaMinutes,
    required this.etaTime,
    required this.distanceKm,
    required this.riderName,
    required this.riderInitials,
    required this.riderRating,
    required this.riderVehicle,
    required this.riderPlate,
  });

  final String id;
  final String status;
  final int etaMinutes;
  final String etaTime;
  final double distanceKm;
  final String riderName;
  final String riderInitials;
  final double riderRating;
  final String riderVehicle;
  final String riderPlate;
}
