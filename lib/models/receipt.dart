class ReceiptItem {
  const ReceiptItem({required this.qty, required this.name, required this.price});

  final int qty;
  final String name;
  final double price;
}

class Receipt {
  const Receipt({
    required this.orderId,
    required this.dateTime,
    required this.vendor,
    required this.vendorAddress,
    required this.dropoffLabel,
    required this.dropoffAddress,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.gst,
    required this.total,
    required this.cardLast4,
    required this.riderName,
    required this.riderInitials,
  });

  final String orderId;
  final String dateTime;
  final String vendor;
  final String vendorAddress;
  final String dropoffLabel;
  final String dropoffAddress;
  final List<ReceiptItem> items;
  final double subtotal;
  final double deliveryFee;
  final double gst;
  final double total;
  final String cardLast4;
  final String riderName;
  final String riderInitials;
}
