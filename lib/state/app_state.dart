import 'package:flutter/material.dart';

import '../models/customer_order.dart';
import '../models/receipt.dart';
import '../models/recent_trip.dart';
import '../models/rider_job.dart';
import '../models/saved_address.dart';

enum AppRole { customer, rider }

/// Holds all mock data and cross-screen navigation state for the prototype.
class AppState extends ChangeNotifier {
  AppRole role = AppRole.customer;
  int customerTabIndex = 0;
  int riderTabIndex = 0;

  final List<SavedAddress> savedAddresses = const [
    SavedAddress(
      label: 'Home',
      line: '42 Franklin Rd, Ponsonby',
      icon: Icons.home_rounded,
      isDefault: true,
    ),
    SavedAddress(
      label: "Nan's place",
      line: '8 Kohimarama Rd, Auckland',
      icon: Icons.star_rounded,
    ),
    SavedAddress(
      label: 'Work',
      line: 'Level 5, 12 Madden St, Wynyard',
      icon: Icons.navigation_rounded,
    ),
  ];

  final List<RiderJob> nearbyJobs = [
    const RiderJob(
      id: 'KW-2418',
      vendor: 'Kōwhai Bakery',
      payout: 11.40,
      badge: 'Hot',
      routeFrom: "K'Rd, Auckland",
      routeTo: 'Ponsonby',
      distanceKm: 3.2,
      etaMinutes: 14,
      customerName: 'Sarah W.',
      dropoffAddress: '42 Franklin Rd, Ponsonby',
      dropoffNotes: 'Leave at door · gate code #4821',
      nextStepDistanceM: 400,
      nextStepInstruction: 'Turn right onto Franklin Rd',
      activeEtaMinutes: 12,
      activeEtaTime: '6:42 pm',
    ),
    const RiderJob(
      id: 'AK-9910',
      vendor: 'Sushi Bay',
      payout: 13.80,
      routeFrom: 'Queen St',
      routeTo: 'Grey Lynn',
      distanceKm: 4.6,
      etaMinutes: 18,
      customerName: 'Noah P.',
      dropoffAddress: '15 Crummer Rd, Grey Lynn',
      dropoffNotes: 'Buzz apartment 3B',
      nextStepDistanceM: 900,
      nextStepInstruction: 'Continue onto Great North Rd',
      activeEtaMinutes: 16,
      activeEtaTime: '6:51 pm',
    ),
    const RiderJob(
      id: 'PT-5521',
      vendor: 'Pita Pit',
      payout: 9.50,
      routeFrom: 'Wynyard Qtr',
      routeTo: 'Herne Bay',
      distanceKm: 2.8,
      etaMinutes: 11,
      customerName: 'Liam T.',
      dropoffAddress: '4 Sarsfield St, Herne Bay',
      dropoffNotes: 'Meet at gate',
      nextStepDistanceM: 250,
      nextStepInstruction: 'Merge onto Jervois Rd',
      activeEtaMinutes: 9,
      activeEtaTime: '6:36 pm',
    ),
  ];

  RiderJob? activeJob;

  CustomerOrder? activeCustomerOrder;

  final List<RecentTrip> recentTrips = [
    const RecentTrip(
      vendor: 'Kōwhai Bakery',
      status: TripStatus.delivered,
      time: '6:42 pm',
      distanceKm: 3.2,
      payout: 11.40,
    ),
    const RecentTrip(
      vendor: 'Sushi Bay',
      status: TripStatus.delivered,
      time: '5:18 pm',
      distanceKm: 4.6,
      payout: 13.80,
    ),
    const RecentTrip(
      vendor: 'Pita Pit',
      status: TripStatus.delayed,
      time: '4:04 pm',
      distanceKm: 2.8,
      payout: 9.50,
    ),
    const RecentTrip(
      vendor: 'Bird on a Wire',
      status: TripStatus.delivered,
      time: '2:31 pm',
      distanceKm: 3.9,
      payout: 12.10,
    ),
  ];

  final Receipt receipt = const Receipt(
    orderId: 'KW-2418',
    dateTime: 'Fri 24 Jul · 6:41 pm NZST',
    vendor: 'Kōwhai Bakery',
    vendorAddress: '128 Karangahape Rd, Auckland',
    dropoffLabel: '42 Franklin Rd',
    dropoffAddress: 'Ponsonby, Auckland 1011',
    items: [
      ReceiptItem(qty: 1, name: 'Manuka sourdough', price: 12.50),
      ReceiptItem(qty: 1, name: 'Kumara scones (4)', price: 9.00),
      ReceiptItem(qty: 2, name: 'Flat white', price: 11.00),
    ],
    subtotal: 32.50,
    deliveryFee: 6.90,
    gst: 5.91,
    total: 45.31,
    cardLast4: '4021',
    riderName: 'Tama',
    riderInitials: 'TA',
  );

  // Weekly payout bar chart, px heights lifted from the prototype (max 103).
  static const List<double> weeklyBarHeights = [45, 69, 54, 87, 103, 78, 38];
  static const List<String> weekdayLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const int highlightedWeekday = 4; // Fri

  void switchRole(AppRole newRole) {
    if (role == newRole) return;
    role = newRole;
    notifyListeners();
  }

  void setCustomerTab(int index) {
    customerTabIndex = index;
    notifyListeners();
  }

  void setRiderTab(int index) {
    riderTabIndex = index;
    notifyListeners();
  }

  /// Confirms a drop-off pin on the customer Home screen and starts tracking
  /// the (mock) order.
  void confirmDropoff() {
    activeCustomerOrder = const CustomerOrder(
      id: 'KW-2418',
      status: 'On the way',
      etaMinutes: 12,
      etaTime: '6:42 pm',
      distanceKm: 4.1,
      riderName: 'Tama R.',
      riderInitials: 'TA',
      riderRating: 4.9,
      riderVehicle: 'Blue Suzuki',
      riderPlate: 'KWR-482',
    );
    customerTabIndex = 1;
    notifyListeners();
  }

  void acceptJob(String id) {
    final index = nearbyJobs.indexWhere((job) => job.id == id);
    if (index == -1) return;
    activeJob = nearbyJobs.removeAt(index);
    riderTabIndex = 1;
    notifyListeners();
  }

  void completeActiveJob() {
    final job = activeJob;
    if (job == null) return;
    recentTrips.insert(
      0,
      RecentTrip(
        vendor: job.vendor,
        status: TripStatus.delivered,
        time: job.activeEtaTime,
        distanceKm: job.distanceKm,
        payout: job.payout,
      ),
    );
    activeJob = null;
    riderTabIndex = 2;
    notifyListeners();
  }
}
