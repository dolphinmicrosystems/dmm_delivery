Dart and Flutter test-driven development:

Purpose and scope:
  This is a manually read workflow for the Flutter application at this repository
  root. The folder does not install a hook, run tests automatically, or create a
  named agent. Read AGENTS.md, CLAUDE.md and BUILD.md for current project boundaries.
  Change only the behavior requested; preserve existing staged and unstaged work.
  Never delete someone else's implementation to satisfy a test-first ritual.
  Existing behavior can be characterized with tests, but do not call that RED
  unless a regression test actually failed before the fix.

Tooling grounded in this checkout:
  pubspec.yaml declares package dmm_delivery, Dart ^3.12.0, Flutter >=3.44.0,
  flutter_test and flutter_lints. analysis_options.yaml includes
  package:flutter_lints/flutter.yaml and excludes build/ and all native platform
  directories. Analyzer success is not native build verification.
  There is no need for pytest, uv, Ruff, an invented backend/ or frontend/ zone,
  a new mocking framework, or an assumed FVM installation.

  Run these commands from the repository root. This local SDK was checked as
  Flutter 3.47.7 / Dart 3.13.5 when preparing this guide. On another machine choose
  a verified compatible SDK; do not upgrade or reset a shared SDK automatically.

    FLUTTER=/Volumes/MacintoshHDEXT/Library/Android/flutter-3.47.7/bin/flutter
    "$FLUTTER" --version

  Existing resolved dependencies are required for --no-pub. If resolution is
  missing, report that setup blocker rather than calling it a failing test.
  Only with permission to resolve dependencies, use the committed lockfile:

    "$FLUTTER" pub get --enforce-lockfile

  Do not upgrade dependencies, introduce frameworks, read .env or
  dart_defines.json, regenerate cloud configuration, or call live services as
  default test setup. --no-pub skips dependency resolution; it is not a sandbox
  and does not prevent a test's own network calls. Flutter can write local
  build/cache artifacts, so inspect git status after verification.

One behavior at a time:
  State the observable behavior, boundary and failure mode before editing.
  Read its current model, call sites and adjacent tests. Prefer a real input and
  output assertion over mock call counts or assertions about private internals.
  Inject time and data where the existing API allows it; avoid sleeps and live
  Firebase/GPS/network access. Choose one vertical slice, not a speculative pile
  of tests followed by a broad implementation.

RED:
  Add one named regression or requirement test before new production behavior.
  Run that file and, for a fast loop, the named test. Record the command, selected
  test name, exit status and expected/actual assertion. The test must execute and
  fail for the intended missing behavior. An undefined method, compiler error,
  missing import, plugin/Firebase initialization failure, missing dependency or
  zero matching tests is NOT behavioral RED. Repair the harness/API setup, then
  obtain the meaningful failure before implementing.
  If it passes immediately, investigate whether the behavior already exists,
  the case misses the bug, or the assertion checks the wrong thing. Do not change
  an otherwise correct expected result just to manufacture a red run.

GREEN:
  Make the smallest implementation change that satisfies that behavior. Keep the
  expected result tied to the requirement, not the observed implementation.
  Rerun exactly the same selected test, then its whole file and related files.
  Investigate regressions; do not hide them by deleting tests, adding broad
  ignores or weakening assertions. Use doubles only for external boundaries
  when necessary, with their side effects and limitations documented.

REFACTOR:
  Simplify duplication or names only after GREEN. Keep behavior unchanged and
  rerun affected tests after each small step. If a refactor goes red, take a
  smaller step and revert only your own specific change if needed, not the
  user's work. Start the next behavior with its own RED. Before completion,
  run the full test suite and analyzer and report all failures and warnings.

Focused commands already exercised for this guide:
  These commands each selected one real existing test and returned exit 0 with
  'All tests passed!'. They verify the selectors and existing behavior, not a
  new RED-GREEN cycle or the whole suite. Group names form part of the test name;
  --plain-name is a plain-text substring filter, not a guaranteed unique ID.
  Check the actual names and count in the output; never accept zero matches.

    "$FLUTTER" test --no-pub test/driver_invitation_test.dart --plain-name 'status an invitation sitting exactly on its deadline is still pending'
    "$FLUTTER" test --no-pub test/basemap_test.dart --plain-name 'Google tile headers can be handed to a TileLayer, which adds to them'

  The entire existing basemap example was also exercised successfully:

    "$FLUTTER" test --no-pub test/basemap_test.dart

  Both tests passed. The documented runnable snippet was checked against that
  file and matched exactly after removing comments. The docs were checked as
  ASCII with no fenced code/headings; git diff --check returned exit 0.

Further gates to run for a behavior change, not claimed run by this guide:

    "$FLUTTER" test --no-pub test/driver_invitation_test.dart
    "$FLUTTER" test --no-pub test/driving_logic_test.dart test/turn_by_turn_test.dart
    "$FLUTTER" test --no-pub
    "$FLUTTER" analyze --no-pub
    git diff --check

  Select related files based on the actual change, not these examples alone.
  Do not infer today's test total from an older guide or a previous run.

Small runnable example from the current repository:
  test/basemap_test.dart:1-21 tests the real flutter_map provider's header
  mutation. The complete test below uses the existing imports and API, with
  comments omitted. Read/run the existing file; do not add a duplicate file.
  It creates a provider and TileLayer without rendering or fetching tiles and
  does not initialize Firebase. The first test would catch handing the const
  MapConfig headers directly to the mutating provider; the copy is intentional.
  It is an existing GREEN regression example, not evidence of a RED performed
  while writing these docs.

    import 'package:dmm_delivery/config/map_config.dart';
    import 'package:flutter_map/flutter_map.dart';
    import 'package:flutter_test/flutter_test.dart';

    void main() {
      test('Google tile headers can be handed to a TileLayer, which adds to them', () {
        final provider = NetworkTileProvider(headers: {...MapConfig.googleMapTilesHeaders});

        TileLayer(urlTemplate: 'https://example.com/{z}/{x}/{y}', userAgentPackageName: 'x', tileProvider: provider);

        expect(provider.headers['X-Android-Package'], 'com.delivery.dmm_delivery');
        expect(provider.headers.containsKey('User-Agent'), isTrue);
      });

      test('the const headers themselves are left untouched', () {
        expect(MapConfig.googleMapTilesHeaders.containsKey('User-Agent'), isFalse);
      });
    }

Fixture and test choices:
  Time/expiry:
    test/driver_invitation_test.dart:1-31 supplies actual imports, a fixed now
    and an invitation() helper around DriverInvitation. Lines 63-68 pin exact
    expiry equality as pending; lib/models/driver_invitation.dart:148-159 uses
    strictly now.isAfter(expiry). Also cover just before/after, missing expiry,
    accepted/removed precedence, calendar dates and timezone/DST expectations.
    Resend spacing is >= one day, while a full 14-in-14 window remains full at
    exactly 14 days. Compare model code and test exact boundaries rather than
    assuming labels enforce server authorization.

  Unknown enums and malformed wire data:
    test/driver_invitation_test.dart:341-371 covers owner/rider and unknown
    invitation roles falling back to rider. Auth claims are different:
    lib/state/auth_state.dart:96-105 maps an unknown role to needsRole and a
    missing owner_uid to staleSession, not an authorized driver.
    PinPrecision.parse in lib/models/run_stop.dart:109-117 defaults unknown
    strings to exact. Test/document that current policy; do not assume every
    unknown enum is rejected. Typed casts in fromDoc can still throw for a
    malformed field type; string/null tests do not prove arbitrary-data safety.

  Delivery and quantities:
    test/driving_logic_test.dart:1-18 has the real RunStop/LatLng fixture; lines
    20-34 exercise next-undelivered selection and distance/accuracy allowance.
    Add the requested empty/all-delivered/duplicate or reordered IDs scenario
    and exact 60 m / capped 40 m boundary cases separately as appropriate.
    test/run_sheet_review_test.dart:13-23 provides RunStop and StopItem helpers;
    lines 26-69 cover milkTotals, including order-independent quantities.
    This proves pure logic, not DeliveryWriter writes, photo upload, GPS
    permission, server timestamps, offline replay or double-tap behavior.

  Route contract:
    test/route_assignment_test.dart:12-25 has the actual assignment helper.
    Existing cases cover effective dates, unordered rows, createdAt tie-breaks,
    null-driver unassignment, one-day cover and cancellation. Preserve
    inherited start/end pairs; a cover with its own start does not inherit an
    unrelated regular end. Read lines 175-201 for the precise existing case.
    test/run_time_test.dart covers HH:MM/time-window logic. Include missing or
    invalid times, midnight and date boundaries when the change touches them.
    test/turn_by_turn_test.dart:60-86 uses a literal computeRoutes response with
    NavRoute.fromResponse; it is not a test of RoutesClient HTTP requests.
    For a parser change cover the actual response fields, empty routes and
    malformed durations/polylines. For network behavior test timeout, refusal
    and no destination only through an approved test boundary, not paid calls.

Current integration limits and manual verification:
  Pure model/logic tests can run without Firebase initialization even when
  models import cloud_firestore types. Construct real models/maps directly;
  do not instantiate AuthState or Firebase-dependent screens in a unit test
  expecting them to be automatically isolated. Existing widget tests such as
  test/run_sheet_review_test.dart pump MaterialApp/Scaffold and inspect widgets;
  map tile image behavior, real permissions and backend triggers remain gaps.
  pubspec.yaml currently declares flutter_test, not an integration_test harness
  or a Firebase rules-test dependency. Adding one is a separate approved change.

  The sibling ../dmm-delivery-app was absent when these docs were prepared.
  Backend paths named in comments are contract pointers, not locally verified
  server implementations or commands. Client tests cannot prove deployed
  Firestore rules, indexes, tenant authorization, sign-in blocking, notification
  fan-out, upload confirmation, route refresh or learned delivery data.

  Plan manual checks only with an explicitly chosen test environment/accounts
  and permission for writes: owner/driver role routing, stale/expired/removed
  sign-in, denied/cross-tenant reads and writes, route start ready/refused,
  confirm/reorder/undo, duplicate delivery taps, offline/resume, photo failures,
  location/camera permission denial, notifications, TTS and actual map credit.
  Live invitations, uploads, route edits and delivery writes are NOT default
  regression tests. Record device/build/environment and read back the intended
  record after an authorized mutation. Do not use production as a fixture.

Controlled native scope:
  Consult BUILD.md before native validation. Request scope for platform,
  build mode, target device and artifact; native builds can download Gradle,
  CocoaPods or SDK dependencies. Tests/analyzer are not build/install success.
  An explicitly requested Android build may use the compatible SDK:

    "$FLUTTER" build apk --debug --no-pub --target-platform android-arm64

  This command is an optional example, not exercised for these docs. Do not
  run cloud-config generation, flutterfire configure, gcloud mutations,
  install/uninstall/clear-data, release signing changes or publishing as part
  of ordinary TDD. If an approved build needs dart_defines.json, pass it using
  the established BUILD.md flow without printing its contents.

Completion evidence:
  Report the changed behavior, RED assertion, GREEN command/results, related
  and full-suite/analyzer outputs, remaining native/backend/manual gaps and
  any blocker. An unrun check is NOT RUN, a setup failure is BLOCKED, and a
  passing focused test is only PASS for its stated scope. Never imply all
  tests passed, TDD occurred or a device/backend worked without real output.
  No automatic staging, commits, format-all, stash, reset or auto-fix loop.

Public references consulted, adapted rather than copied:
  https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md
    Behavioral RED, minimal GREEN and refactoring with tests kept green.
  https://github.com/obra/superpowers/blob/main/skills/requesting-code-review/SKILL.md
    Give a reviewer concrete requirements, change scope and verification.
  https://github.com/flutter/flutter/blob/master/CONTRIBUTING.md
    Reproducible regression tests, useful QA and evidence-based review.
  These are upstream principles, not this application's tool installation or
  commands. This guide does not adopt upstream automatic agents or commits.
