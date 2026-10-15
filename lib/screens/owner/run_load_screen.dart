import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../widgets/load_sheet_view.dart';

/// The owner's view of one run's load sheet: what goes on the truck, the
/// driver's ticks and shortages, and "Add or take off" - which tells the
/// driver (notify-load-change). Opened from the run screen.
class RunLoadScreen extends StatelessWidget {
  const RunLoadScreen({
    super.key,
    required this.authState,
    required this.runId,
    required this.routeName,
    required this.finished,
    required this.driverAssigned,
  });

  final AuthState authState;
  final String runId;
  final String routeName;

  /// A finished run's load is history: shown, not changed.
  final bool finished;

  /// Whether the run has a driver (`rider_id`) to tell about a change.
  final bool driverAssigned;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text('Load · $routeName', overflow: TextOverflow.ellipsis)),
      body: LoadSheetView(
        authState: authState,
        runId: runId,
        role: LoadRole.owner,
        editable: !finished,
        driverAssigned: driverAssigned,
      ),
    );
  }
}
