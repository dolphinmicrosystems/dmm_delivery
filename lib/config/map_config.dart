/// Where the basemap tiles under every map in this app come from.
///
/// Deliberately not part of [InfraConfig]: that file is *generated* from live
/// GCP state by `tool/generate_infra_config.sh` and must never be hand-edited,
/// and the CARTO key does not come from GCP - it comes from CARTO.
class MapConfig {
  const MapConfig._();

  /// CARTO stopped serving unkeyed basemap tiles in August 2026. There is
  /// nothing for a tile layer to fail on when the key is missing: every tile
  /// still returns HTTP 200 and a valid PNG, stamped "API KEY REQUIRED" right
  /// across the middle. So a missing key is a *cosmetic* fault that no error
  /// handling will ever surface - which is why it is called out here rather
  /// than left to be rediscovered from a screenshot.
  ///
  /// Request one at https://carto.com/basemaps/apikey - it is emailed
  /// immediately, needs no CARTO account, and covers 5 million tiles a month.
  /// Then pass it at build time:
  ///
  ///     flutter run --dart-define=CARTO_API_KEY=<key>
  ///     flutter build appbundle --release --dart-define=CARTO_API_KEY=<key>
  ///
  /// A `--dart-define` rather than a committed constant, so the key can change
  /// without a code change. It is not a secret - it ships inside the APK and
  /// is visible in every tile request - but it is also not ours to paste into
  /// a public repository, and CARTO's terms say keys are per-customer and must
  /// not be shared across unrelated projects.
  static const cartoApiKey = String.fromEnvironment('CARTO_API_KEY');

  /// CARTO's "Positron" light basemap - the pale grey that the brand-blue
  /// route line and numbered pins are drawn to sit on top of. Swapping it for
  /// a full-colour basemap costs the route line most of its contrast.
  ///
  /// The key rides as a query parameter; `flutter_map` substitutes the `{...}`
  /// placeholders and leaves the rest of the string alone. Omitted entirely
  /// when unset rather than sent empty - a bare `?key=` is a malformed
  /// request, where no parameter at all is merely an anonymous one.
  static String get basemapUrlTemplate => basemapUrlFor(cartoApiKey);

  /// Split out from [basemapUrlTemplate] so both branches can be tested:
  /// [cartoApiKey] is a compile-time constant, so a test of the getter can
  /// only ever see whichever branch the test run itself was built with.
  static String basemapUrlFor(String apiKey) =>
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png'
      '${apiKey.isEmpty ? '' : '?key=$apiKey'}';

  static const basemapSubdomains = ['a', 'b', 'c', 'd'];

  /// Required by CARTO's terms ("CARTO and OpenStreetMap must be credited on
  /// every map"), and by OpenStreetMap's before that. Rendered through
  /// flutter_map's attribution widget rather than baked into a corner of the
  /// design, so it stays legible whatever the map is showing.
  static const basemapAttribution = '© CARTO © OpenStreetMap contributors';
}
