import 'run_stop.dart';

/// Finding one stop in a run of sixty.
///
/// Every word typed has to appear somewhere on the stop - customer, address,
/// order number, docket, phone or a product - so "orari 18" finds 18 Orari
/// Street and "toyota service" finds the service lounge rather than every
/// Toyota. Case and punctuation are ignored: "mitre10" finds "Mitre 10".
///
/// Ranked so the stop the owner most likely means comes first: a customer
/// name that starts with the query, then one that contains it, then a match
/// anywhere else. Within a rank, route order - which is how the owner
/// thinks about the run.
///
/// Pure, so it is tested directly (test/stop_search_test.dart) rather than
/// through a screen that needs Firebase to build.
List<({RunStop stop, int index})> searchStops(List<RunStop> stops, String query) {
  final words = _normalise(query).split(' ').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return const [];

  final matches = <({RunStop stop, int index, int rank})>[];
  for (var i = 0; i < stops.length; i++) {
    final stop = stops[i];
    final haystack = _normalise(
      [
        stop.customerName,
        stop.address,
        stop.orderNumber,
        stop.docket,
        stop.phone,
        for (final item in stop.items) item.product,
      ].whereType<String>().join(' '),
    );
    // Compared with the spaces taken out as well, so "mitre10" still finds
    // "Mitre 10" and "0274" finds "027 4...".
    final compact = haystack.replaceAll(' ', '');
    if (!words.every((word) => haystack.contains(word) || compact.contains(word))) continue;

    final name = _normalise(stop.customerName);
    final phrase = words.join(' ');
    final rank = name.startsWith(phrase) ? 0 : (name.contains(phrase) ? 1 : 2);
    matches.add((stop: stop, index: i, rank: rank));
  }
  matches.sort((a, b) => a.rank != b.rank ? a.rank.compareTo(b.rank) : a.index.compareTo(b.index));
  return [for (final match in matches) (stop: match.stop, index: match.index)];
}

String _normalise(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
