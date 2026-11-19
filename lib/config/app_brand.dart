/// The app's name as people see it. The package name
/// (`com.delivery.dmm_delivery`) is separate and can never change on Play;
/// this can.
abstract final class AppBrand {
  /// On Play, in the app, and in the backend's invitation emails
  /// (`app_display_name` in its Terraform).
  static const name = 'Dunedin Milk & More';

  /// Under the home-screen icon and in Android's Settings > Apps, where a
  /// longer name is cut to "Dunedin Mil...". Mirrors `android:label` in
  /// AndroidManifest.xml.
  static const shortName = 'Milk & More';
}
