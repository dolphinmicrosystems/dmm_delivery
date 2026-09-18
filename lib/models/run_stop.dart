import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// One delivery_stop document, with the run sheet's product lines kept
/// intact.
///
/// process_run_sheet_upload.py has always written an `items` array per stop
/// (the parser reads it straight off the PDF's product lines), but nothing
/// on the client read it until now - the route list showed only a name and
/// an address, which is the one thing a driver standing at the door already
/// knows. The quantities are the payload.
class RunStop {
  const RunStop({
    required this.id,
    required this.seqOrder,
    required this.customerName,
    required this.address,
    required this.location,
    required this.items,
    this.orderNumber,
    this.docket,
    this.phone,
    this.instructions,
    this.addressKey,
    this.precision = PinPrecision.exact,
  });

  final String id;

  /// Position in the *stored* sequence. Kept as read so a locally reordered
  /// list can be compared against what the backend last sequenced, rather
  /// than re-deriving "did this move?" from list indices alone.
  final int seqOrder;

  final String customerName;
  final String address;
  final LatLng location;
  final List<StopItem> items;
  final String? orderNumber;
  final String? docket;
  final String? phone;
  final String? instructions;

  /// The backend's `address_key` - what learned leg times are keyed by.
  final String? addressKey;

  /// How the pin was found. Anything short of a building gets called out on
  /// the stop's card, so the owner knows which pins to check.
  final PinPrecision precision;

  /// Total units across every product line - the run sheet's own "Sub
  /// Totals" quantity column.
  int get unitCount => items.fold(0, (running, item) => running + item.quantity);

  /// Every product line on one line, for places too tight for chips.
  /// Empty when the stop has no products, so callers can test it directly
  /// rather than checking `items` and formatting separately.
  String get itemsSummary => [for (final item in items) item.label].join(' · ');

  static RunStop? fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    // A stop that never geocoded has no place on a map and no meaningful
    // slot in a route order. Dropping it here keeps every downstream
    // consumer (polyline, pins, reorder) free of null checks, at the cost
    // of a stop the owner can't see - which the review screen calls out
    // explicitly rather than silently swallowing.
    if (lat == null || lng == null) return null;

    return RunStop(
      id: doc.id,
      seqOrder: (data['seq_order'] as num?)?.toInt() ?? 0,
      customerName: data['customer_name'] as String? ?? '',
      address: data['address'] as String? ?? '',
      location: LatLng(lat, lng),
      items: [
        for (final item in (data['items'] as List?) ?? const [])
          if (item is Map) StopItem.fromMap(item.cast<String, dynamic>()),
      ],
      orderNumber: data['order_number'] as String?,
      docket: data['docket'] as String?,
      phone: data['phone'] as String?,
      instructions: data['instructions'] as String?,
      addressKey: data['address_key'] as String?,
      precision: PinPrecision.parse(data['precision'] as String?),
    );
  }
}

/// `delivery_stop.precision`, written by process_run_sheet_upload.py - see
/// `PRECISIONS` in the backend's ports/geocoding.py, plus `learned`.
enum PinPrecision {
  /// The building at that street address.
  exact,

  /// Where drivers have repeatedly marked it delivered. The best there is.
  learned,

  /// The business named on the sheet, found by name.
  business,

  /// Somewhere on the right street; the house number did not match.
  street,

  /// Only the suburb or town.
  area;

  /// Absent means exact: every stop written before precision was recorded
  /// came from a lookup that either matched or failed the whole upload.
  static PinPrecision parse(String? wire) => switch (wire) {
    'learned' => learned,
    'business' => business,
    'street' => street,
    'area' => area,
    _ => exact,
  };

  /// What to tell the owner about this pin, or null when nothing needs saying.
  String? get caution => switch (this) {
    street => 'Approximate pin: street only, no house number matched',
    area => 'Approximate pin: suburb only, please check',
    _ => null,
  };
}

/// One product line on a stop: "3 x 2 L Standard Milk".
class StopItem {
  const StopItem({
    required this.code,
    required this.product,
    required this.quantity,
    required this.crates,
    required this.loose,
  });

  /// DMM's catalogue code (10, 20, 30, 50, 80, 90, 100, 159). Used as the
  /// grouping key for totals rather than the product name, because the name
  /// is display text and the code is the identity - "1l Oat Milk" and "1 L
  /// Oat Milk" are the same product to the depot.
  final String code;
  final String product;
  final int quantity;
  final int crates;
  final int loose;

  /// How a product line reads everywhere it appears: "10 × 1 L Standard
  /// Milk". Defined once here rather than formatted at each call site - the
  /// review card, the route sheet and any future driver view have to agree,
  /// and a quantity rendered two different ways is a support call.
  String get label => '$quantity × $product';

  factory StopItem.fromMap(Map<String, dynamic> map) {
    return StopItem(
      code: map['code']?.toString() ?? '',
      product: map['product'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      crates: (map['crates'] as num?)?.toInt() ?? 0,
      loose: (map['loose'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Load-out total for one product across every stop on the run.
class MilkTotal {
  const MilkTotal({
    required this.code,
    required this.product,
    required this.quantity,
    required this.crates,
    required this.loose,
  });

  final String code;
  final String product;
  final int quantity;
  final int crates;
  final int loose;
}

/// Aggregates every stop's product lines into one per-product total,
/// heaviest first.
///
/// This is what the owner loads onto the van, so it is deliberately
/// independent of stop order - reordering the list must not change it, and a
/// test pins that.
List<MilkTotal> milkTotals(Iterable<RunStop> stops) {
  final byCode = <String, MilkTotal>{};

  for (final stop in stops) {
    for (final item in stop.items) {
      final existing = byCode[item.code];
      byCode[item.code] = MilkTotal(
        code: item.code,
        product: existing?.product ?? item.product,
        quantity: (existing?.quantity ?? 0) + item.quantity,
        crates: (existing?.crates ?? 0) + item.crates,
        loose: (existing?.loose ?? 0) + item.loose,
      );
    }
  }

  final totals = byCode.values.toList()
    ..sort((a, b) {
      final byQuantity = b.quantity.compareTo(a.quantity);
      return byQuantity != 0 ? byQuantity : a.product.compareTo(b.product);
    });
  return totals;
}
