/// What to do about an update to the app, from what Google Play reports.
///
/// Pure, so it is tested without Play: the plugin's enums are passed in as
/// their names (`updateAvailable`, `downloaded`, ...) rather than imported.
enum AppUpdateStep {
  /// Nothing newer on Play, or nothing to do right now.
  none,

  /// A newer version is on Play: ask Play to show its "Update available"
  /// dialog and download it in the background while the app keeps working.
  download,

  /// A newer version has already finished downloading: offer to restart
  /// into it.
  install;

  /// [availability] and [installStatus] are Play's UpdateAvailability and
  /// InstallStatus names.
  ///
  /// [alreadyAsked] is true once the person has been offered this update in
  /// this session: saying "No thanks" to Play's dialog should not bring it
  /// straight back every time the app returns to the front.
  static AppUpdateStep decide({
    required String availability,
    required String installStatus,
    required bool flexibleAllowed,
    required bool alreadyAsked,
  }) {
    // Checked first: a download finished in an earlier session (or while
    // the app was in the background) is waiting for nothing but a restart.
    if (installStatus == 'downloaded') return AppUpdateStep.install;
    // Already downloading or installing: let it carry on.
    if (const {'pending', 'downloading', 'installing'}.contains(installStatus)) return AppUpdateStep.none;
    if (availability != 'updateAvailable' || !flexibleAllowed || alreadyAsked) return AppUpdateStep.none;
    return AppUpdateStep.download;
  }
}
