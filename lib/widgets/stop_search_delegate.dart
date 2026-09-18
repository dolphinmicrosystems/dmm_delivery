import 'package:flutter/material.dart';

import '../models/run_stop.dart';
import '../models/stop_search.dart';
import '../theme/app_colors.dart';
import 'route_preview_map.dart';

/// Opens a search over a run's stops and returns the chosen stop's index in
/// [stops], or null if the owner backed out.
///
/// Shared by the review screen and the confirmed route screen; each decides
/// what "take me to it" means (scroll the list, open the stop's sheet), and
/// both call the pin out on the map.
Future<int?> searchForStop(BuildContext context, List<RunStop> stops) =>
    showSearch<int?>(context: context, delegate: _StopSearchDelegate(stops));

class _StopSearchDelegate extends SearchDelegate<int?> {
  _StopSearchDelegate(this.stops)
    : super(
        searchFieldLabel: 'Customer, street, order or product',
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.search,
      );

  final List<RunStop> stops;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  // Results update as the owner types - there is no separate "submit" step
  // worth waiting for on a list this size.
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  @override
  Widget buildResults(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    if (query.trim().isEmpty) {
      return _Hint('${stops.length} stops on this run. Search by customer, street, order number or product.');
    }
    final matches = searchStops(stops, query);
    if (matches.isEmpty) return _Hint('No stop matches “${query.trim()}”.');

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: matches.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 60, color: AppColors.hairline),
      itemBuilder: (context, i) {
        final match = matches[i];
        return ListTile(
          leading: StopPin(number: match.index + 1, compact: true),
          title: Text(match.stop.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [match.stop.address, if (match.stop.itemsSummary.isNotEmpty) match.stop.itemsSummary].join('\n'),
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
          isThreeLine: match.stop.itemsSummary.isNotEmpty,
          onTap: () => close(context, match.index),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, style: const TextStyle(color: AppColors.inkMuted)),
    );
  }
}
