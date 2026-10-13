Technical low-level design:

Purpose, ownership and evidence:

  This is the detailed implementation reference for dmm_delivery, separated
  from startup agent instructions. It reorganizes the earlier detailed
  .claude/CLAUDE.md into responsibilities, data contracts and failure behavior.
  AGENTS.md is the intended shared coding guide; root CLAUDE.md is intended to
  route Claude to it. See .claude/README.md for routing and migration status.
  Functional features, sequence diagrams and exact dependency versions live in
  .claude/architecture.md. BUILD.md governs environment-affecting builds.

  Current source establishes client behavior. Python filenames, rules and
  Terraform referenced below are EXTERNAL BACKEND CONTRACTS documented by
  client code and the earlier guide, not locally inspected implementation or
  verified deployment. The expected ../dmm-delivery-app checkout is absent.
  Obtain that repository and read its own instructions before changing a
  cross-repository contract. Do not claim rules, functions or backend tests
  passed from client code alone. Old test totals and deployment assurances
  are not retained as current facts.

  .claude/plan.md preserves historical rationale, but its mock board, three
  invitation states, missing driver UI and missing schedule descriptions are
  obsolete. Do not reconstruct those screens from the plan. The old detailed
  .claude/CLAUDE.md remains temporarily while its protected-file migration awaits
  approval; it contains stale statements corrected in this reference.

Tooling and layout:

  lib/ is mostly layered: models/, services/, screens/, widgets/, theme/.
  Driver behavior is grouped in lib/driver/, with driving/ below it.
  Notifications, settings and observability have dedicated feature folders.
  There is no live repository abstraction or general state package between
  owner screens and Firestore; StreamBuilder/FutureBuilder compose live data.
  Do not create backend/ or frontend/ zones based on generic instructions.

  pubspec.yaml and pubspec.lock establish compatible SDK/package requirements.
  Declared SDKs: Dart ^3.12.0 and Flutter >=3.44.0. The local compatible SDK is
  /Volumes/MacintoshHDEXT/Library/Android/flutter-3.47.7/bin/flutter, verified as
  Flutter 3.47.7 / Dart 3.13.5. Select a compatible SDK on other machines.
  Inspect the selected executable, not just PATH or an FVM link.
  Commands, from the app repository with resolved dependencies:

    flutter pub get --enforce-lockfile
    flutter analyze --no-pub
    flutter test --no-pub
    flutter test --no-pub test/run_sheet_review_test.dart --plain-name 'is independent of stop order'

  test/ contains 20 *_test.dart files at this migration, covering pure models
  and constructible widgets. No Firebase integration harness is implied.
  Do not assert a permanent passing test total; run the actual suite.
  Use the existing South Runsheet quantities for relevant load-out fixtures.
  No meaningful parser/schedule/aggregation logic should be trapped inside a
  Firebase-dependent screen build method just to avoid adding a test seam.

  Match surrounding Dart style by hand; do not run dart format . or mass-rewrite
  untouched files. analysis_options.yaml includes flutter_lints and excludes
  native/build directories; native packaging needs its own build verification.
  Current Android release signing explicitly uses the shared non-secret debug
  keystore. It is signed, but not production-signed. No automatic signing change,
  deployment, live invite/delivery, staging, commit or publishing is authorized
  by reading a guide. Use .claude/tdd/README.md and .claude/review/README.md.

Generated configuration and environment boundaries:

  lib/config/infra_config.dart is generated; never hand-edit it.
  tool/generate_infra_config.sh discovers bindings from live GCP/Firebase,
  not the backend's filesystem or presumed Terraform resources.

    runSheetsBucket: process-run-sheet-upload's own Storage trigger bucket.
      Do not select a bucket by a similar name or substitute default Storage.
    googleSignInServerClientId: Firebase Auth Google IdP configuration.
    podPhotosBucket: the one matching POD bucket; absent/ambiguous becomes empty.
    riderBoardUrl: generated legacy endpoint; no current runtime consumer.
    driverAccessUrl: server endpoint used by DriverAccessApi.

  GCP_PROJECT_ID disagreement with committed firebase_options.dart can trigger
  flutterfire configure and rewrite platform Firebase registration. Read BUILD.md
  and obtain environment-change approval first. Those changes need human review;
  ephemeral CI writes are not a durable environment migration.
  Plain local builds require no gcloud credentials and no config sync.
  cloudbuild.yaml is manually scoped verify/build configuration; a file alone
  is not proof of a registered trigger, passing CI or deployed infrastructure.
  It uses floating stable images, not a guarantee of the locally verified SDK.
  It does not replace a full client test gate.

Identity, tenancy and navigation:

  main.dart initializes Firebase and creates one long-lived AuthState.
  AuthState uses Firebase Auth, GoogleSignIn.instance and idTokenChanges.
  AuthGate maps AuthStatus to screens. RootShell selects the owner or driver
  shell; it is presentation and not the server authorization boundary.

    role claim 'owner' -> AuthRole.owner.
    role claim 'rider' -> AuthRole.driver.
    Unknown role -> needsRole; it must not become an authorized driver.
    Recognized role without owner_uid -> staleSession; show recovery rather
      than a correctly rendered but empty tenant-scoped app.
    AuthStatus.signedIn requires recognized role and business claim.

  AuthRole.driver and backend/rules 'rider' differ intentionally. Preserve both.
  owner_uid can differ from the signed-in user's uid for colleagues in a
  business. Business queries/records use ownerUid; personal preferences use uid.
  AuthState.invitations filters invited_by; routeAssignments filters owner_uid.
  Driver run queries scope both owner_uid and rider_id.

  Google sign-in passes the Google ID token to Firebase credential sign-in,
  then forces getIdTokenResult(true). The blocking-function claim is set during
  that sign-in; a stale token can incorrectly look unassigned. The server's
  before_sign_in_fn.py / application/handle_sign_in.py enrollment and claim
  policy is an external contract, not code the mobile client can administer.
  Role selection/sign-in copy never grants a role.

  Sign-out marks a driver offline, unregisters the device token and clears
  crash identity before Firebase signOut, while rules still know the user.
  Read lib/state/auth_state.dart and lib/screens/auth/ before auth edits.
  SignInScreen is pushed over AuthGate and must dismiss its own route on success.

  Owner shell: Home / Routes / Runs / Drivers in one Scaffold and IndexedStack;
  owner tabs are bodies, not nested Scaffolds. The shell owns the header/drawer.
  DriverShell: Home / Runs / Routes with online switch in its app bar.
  RootShell falls through to the owner shell for non-driver roles including null;
  AuthGate must remain the entry guard. Never use that fallback as permission.

Owner preparation and confirmed-route flow:

  UploadRunSheetScreen uploads PDF bytes to InfraConfig.runSheetsBucket at
  {roundKey}/{uploadId}.pdf with identifying/owner/name metadata. The bucket's
  Storage-finalize processing is a backend contract. Uploading to default
  Firebase Storage does not establish that pipeline trigger.

  RunSheetProgressScreen watches run_sheet_upload/{uploadId}.status.
  It handles error before data, missing documents, ready_for_review, no_changes
  and a 90-second stall hint restarted when status changes. The stall hint
  provides recovery while keeping the stream; it does not cancel processing.
  A backend timeout may never write an error document. Backend runtime limits
  are not verified in this checkout; do not turn a hint into a client deadline.

  RunSheetReviewScreen reads the draft delivery_run and delivery_stop children
  ordered by seq_order, resolves the depot from addresses and composes map,
  load totals, instructions, diff, route name and local reorder/removal state.
  Changes remain local until Confirm/Discard updates run_sheet_upload.
  Successful status-write acknowledgement is not acknowledgement that a
  downstream confirm-run-sheet function has finished publishing the circuit.

  The confirmation payload owns status, optional manual_order and optional
  route_name/route_name_source. Do not write parsed/server fields directly.
  manual_order means retained stop IDs in order: a subset, not a permutation.
  Omit removed IDs; append _unlocatedIds so stops without map coordinates are
  retained instead of accidentally removed. Send it only if stops were edited.
  An untouched review must not reassert the optimizer's order as an owner choice.
  The backend confirm_run_sheet_upload.py soft-exclusion behavior is a contract.

  RunStop.fromDoc returns null without coordinates. Other consumers therefore
  receive located stops, but review records omitted IDs explicitly. Backend
  retention of precision='none' stops is not permission to drop them on confirm.
  PinPrecision defaults unknown string values to exact; only street/area warn.
  Typed parsers do not guarantee safety for arbitrary malformed field types.

  onReorderItem already compensates for the lifted row. Do not repeat the
  deprecated onReorder newIndex decrement. Reset order preserves removals;
  its label is not permission to restore excluded rows. Undo owns restoration.
  Action SnackBars use persist:false and a duration to avoid indefinite display.

  RouteMapScreen streams circuit.latest_run_id, run/stops and road legs.
  RouteEditor performs one batch: stop seq_order/excluded updates and parent
  order_revision exactly currentRevision+1 plus order_source='owner'. Removal
  is soft exclusion, not stop deletion. Backend refresh-run road/estimate/
  summary regeneration is an external contract; the batch does not prove
  concurrent multi-owner conflict resolution or successful downstream refresh.

  RouteRenamer is the sole existing-circuit rename adapter. It writes exactly
  round and round_source='owner', no updated_at. Owner provenance preserves
  names across later PDF uploads. RouteName.maxLength is 80 and its normalized
  isRenameOf test avoids false dirty dialogs. It mirrors backend rules.
  On upload/review the chosen name travels in confirmation, because the circuit
  might not yet exist. pdf_round retains the original heading for mismatch checks.

  Re-upload is an amendment: preserve owner naming, order and instruction overrides.
  RunSheetDiff recognizes optimized/reused/merged/learned strategy labels. Unknown
  values are described as optimized, never a promise that order survived.
  Earlier prose's 'three strategies' was stale; four labels exist. Billing/routing
  cost assertions require backend inspection, not just a client strategy string.

  Dirty screens compare normalized parsed values, not raw controller text.
  PopScope.canPop must rebuild when text changes; use the existing Listenable
  pattern. After approval, reissue Navigator.pop rather than maybePop, which
  would ask again. Review also accounts for stop edits. Update may save an
  existing route's name without a PDF; review has only Confirm or Discard.

Owner stop instructions and estimates:

  DepotLocator.addressKey is SHA256 of trimmed, lowercased address, mirroring
  external firestore_paths.address_key. Keep the algorithm and fixture in step.
  stopInstructionsId incorporates the ownerUid as well as addressKey.
  StopInstructionsSheet merges owner_uid, owner_instructions (trimmed or null
  for an explicit clear) and owner_instructions_updated_at/updated_by.
  Preserve file-sourced text and owner-over-file resolution; do not claim
  'only one field is written' when provenance fields are present in the client.

  DeliveryEstimate / EstimateInputs centralize estimate interpretation:
    learned_legs seconds stand as measured for that driver;
    otherwise road_legs seconds are scaled by speed_factor;
    otherwise straight-line distance uses the existing distance/speed fallback
      and speed_factor;
    dwell_by_key wins, otherwise default_dwell_s/business stop time.
  domain/travel_time.py is the external parity contract. Regression fixtures
  in test/delivery_estimate_test.dart guard client values, not deployed parity.
  Reordering updates local arrival offsets and total; an offset is not a clock
  time because the review does not record a departure time.
  milkTotals is order-independent and product text comes from StopItem.label.

Runs, progress, schedules and liveness:

  OwnerRunDataBuilder streams owner-scoped confirmed runs, circuits, assignments,
  invitations and vehicles for Runs/Home. Live run heartbeat reads are separate.
  RunListing.phase places finished runs in Past; otherwise the sheet's parsed
  DD/MM/YYYY delivery_date determines Upcoming / Today / Past. Exclude deleted
  circuits and superseded runs. Progress/history fields on runs are backend-owned
  projections; the client does not invent live data from mock board responses.

  RunDetailScreen streams run/stops, progress, delivered pins and start/finish/
  total time. RunPhotosScreen orders evidence by route sequence. RunListing
  uses the earlier driver Start/first-delivery time as started, and recognizes
  delivery completion or explicit driver End as finished.

  RunTiming is shared by owner/driver cards and driving, with tested constants:
    lateStartAfter: 10 minutes; late start only strictly after the boundary.
    silentAfter: 20 minutes; no signal at or after the boundary.
    lateMargin: 5 minutes; projected/finished lateness only over that margin.
  Expected finish is schedule end, else scheduled start plus estimate. Overnight
  windows add a day when end is not after start. Projected finish adds the
  estimate's share for remaining stops. Last-heard is the latest start, delivery
  and heartbeat. Left-without-resume is distinct from no signal. domain/run_alerts.py
  is the external threshold/notification parity contract. Change both together.

  Home Live now includes ongoing and overdue-not-started runs, problems first,
  driver/vehicle/progress/next stop and expected-back details. It is hidden if
  empty. run_live coordinates exist but are not drawn as an owner live van.

  Scheduling is implemented through showScheduleRunSheet from Routes or Driver
  detail. Choose a date, start/finish, recurring-from-date or one_day cover.
  Finish initially follows RouteEstimates.forRoute from latest estimated_total_s;
  warn when the chosen window is shorter. Times store HH:MM and use run_time.dart.
  A stale Home roster placeholder does not mean assignments are unimplemented.

  RouteAssigner appends route_assignments rows for assignment, time changes,
  unassignment and cover cancellation; it does not update/delete schedule history.
  RouteAssignment.activeAt resolves dates, ties, null-driver rows and one-day
  overrides. Cover inherits regular times only according to the existing model;
  an explicit cover start must not borrow an unrelated regular end.
  External domain/route_assignment.py and assign_route_runs.py govern backend
  matching/re-stamping on open runs; past runs keep their historical driver.

  DriverDataBuilder shares live runs/circuits/whole-business assignments and
  assigned-vehicle queries across driver tabs. The whole schedule matters because
  a colleague's one-day cover removes your job for that day. DriverSchedule builds
  real runs/bookings and Home's live/next selections; test/driver_schedule_test.dart
  guards those decisions. A plan can exist before its run sheet, and past runs
  are not reassigned merely to offer a preview.

Roster, invitation and access contracts:

  DriverInvitation is clock-injected and derives pending/expired/accepted/removed.
  removed outranks every other state; accepted outranks expiry; expiry is strictly
  now > expiresAt. Displaying removed as expired would incorrectly offer renewal.
  Display names use owner name, Google name, then nameFromEmail fallback.
  driver_name_source='owner' prevents server sign-in naming from replacing it.

  InvitationRole stores owner/rider wire strings and label separately. Missing
  or unknown invitation role resolves down to rider, unlike AuthState's unknown
  role guard. The live roster dialog invites drivers only; owner enum/API support
  does not prove an owner-invitation UI. The earlier owner dropdown/confirmation
  description was stale. Inspect actual owner enrollment in the external backend
  before proposing owner-account permissions.

  The driver_invitations document keyed by normalized email is the authorization
  record at next Google sign-in, not an invitation link/token. Email is a courtesy,
  not another credential mechanism. Do not invent links/OTP without an explicit
  auth migration. expires_at controls an unaccepted invitation; accepted access
  is not retroactively removed by changing invitation TTL.

  DriverInviter owns client writes. invite/resend uses set(merge:true), writing
  invitation shape and retaining server counters. Rename is exactly driver_name
  and driver_name_source via update; it must not reset accepted_at.
  No accepted/removed invitation can be resent. Resend carries role and an
  owner-sourced name intentionally; omitted optional merge fields do not clear
  an existing value. Server counters are never minted/modified on the client.

  Resend model gates mirror external rules: one-day spacing, at most 14 invites
  in a still-live 14-day window. The window remains full exactly at day 14.
  InviteForm.maxNameLength is 80; TTL is 1..90 days, fallback 7. Bounds and
  normalized validation are contract requirements; a permission-denied may mean
  a refused shape/value rather than an expired sign-in.

  DriverAccessApi handles remove/restore via driver-access HTTP with Firebase
  Bearer token, normalized email and action. The backend manage_driver_access.py
  must preserve invitation/UID/run history and disable/enable the Auth account.
  A client delete only removes the roster row and does not revoke a minted token.
  Direct removed_at changes or client claims are not equivalent operations.
  Existing ID-token lifetime can delay effective revocation; do not promise
  instant disablement from the UI. Deployed same-tenant/owner checks remain
  unverified until external code/rules are inspected.

Settings, profiles and fleet:

  SettingsStore is the settings read/write owner, not AuthState. Business settings
  merge at app_settings/{ownerUid}: invitation_ttl_days and default_stop_seconds.
  Personal preferences merge at user_settings/{uid}: driver_presence_alerts,
  late_start_alerts, run_reminders, reminder_lead_minutes, voice_prompts.
  app_settings/invitations is a historical path, not current SettingsStore use.
  New cards live in lib/settings/cards with save_setting.dart for reporting.

  OwnerProfile is descriptive client-owned data, not pipeline identity or proof
  of a person's age/name. Optional fields are display_name, age, gender, phone.
  Bounds mirror external rules: name 80, phone 32, age 16..120. toMap omits unset
  fields; AuthState.saveProfile replaces the document plus updated_at so clearing
  removes keys. A blanket merge policy would retain cleared fields. Null age is
  a present invalid key under the documented rules; do not write it.
  ProfileGender stores snake_case wire values, not enum indexes; unknown parses
  null. Profile screen takes starting values, not a stream that edits text under
  the cursor. Dirty checks compare parsed fields and rebuild on all controllers.

  Driver detail reads external backend-written driver_stats and run history,
  combines schedule/circuit data, and uses VehicleService for fleet changes.
  Vehicles are business-scoped and assigned by driver UID. Existing adapter uses
  batches for replacing vehicle assignment; inspect it before widening fields.

Maps and navigation:

  Maps use BasemapLayer and BasemapAttribution, not arbitrary hand-built TileLayers.
  MapStyle is app-wide: Simple/CARTO Positron; Detailed/Google road; Satellite/
  Google labeled imagery. Without GOOGLE_MAP_TILES_KEY only Simple is offered.
  Missing Google session falls back to Simple, not a permanently blank map.
  CARTO_API_KEY is compile-time configuration; provider watermark behavior in
  existing comments must not be represented as independently verified policy.
  Keep CARTO/OpenStreetMap credit and Google logo/viewport copyright unobscured.
  Detailed/Satellite use GoogleMapTiles style sessions, reused until an hour
  before expiry, and DisabledMapCachingProvider to avoid disk tile caching.
  Google Android package/certificate headers and backend maps.tf restrictions
  must match signing; production signing requires the corresponding certificate
  configuration. Never hardcode/disclose map keys or bypass their restrictions.

  RoutePreviewMap is shared by draft review and confirmed routes, including
  depot legs. RoadLegs.fromRun decodes Google precision-5 encoded geometry keyed
  by address pair, not stop index; changed legs fall back to straight segments
  until a backend road refresh. roadSecondsFromRun reads time without decoding.
  Driver RoutesClient also consumes Google's precision-5 Routes API geometry.
  The earlier precision-6 'rider map' comment describes the removed mock board,
  not the current in-app driver navigation format.

  StopHighlight carries RunStop.id and a tick: repeat taps blink again without
  relying on reorderable indexes. Called-out pin is above all others, pulses and
  stays filled. Pan only when outside view. Preview pin tiers are dots below
  zoom 13, compact badges below 14.5, full pins above; selected remains full.
  Zoom-driven marker state changes by tier, not every animation frame. Rotation
  is disabled in preview maps; driving navigation has separate heading behavior.
  Controls handle zoom, whole-route fit and optional expansion; only review
  offers expansion. Retina tiles and attribution layout are not cosmetic extras.

  MapWithSheet exposes map-only/half/most stopsheet positions on owner/driver
  run and route views. Stop search matches every query word across stop fields,
  ranks name-prefix then route order, and resolves to stable IDs. Review scrolls
  lazily toward the card; route opens stop details. Do not use a list index as
  identity after edits. StopItem.label is the product rendering source.

  Driving navigation is in-app; it does not launch Google Maps or url_launcher.
  RoutesClient requests computeRoutes for current stop from phone position with
  DRIVE, TRAFFIC_UNAWARE, navigation fields and 12-second timeout, using existing
  Android headers/key. TurnByTurn is pure/tested. Reroute after two off-route
  fixes, threshold 50 m plus capped accuracy allowance, at least 10 s apart.
  Banner has arrow/distance/instruction and Retry on failure. Do not dismiss it
  as an optional directions panel or call paid APIs as routine unit testing.

  Navigation starts heading-up: rotate by negative heading when moving >1.5 m/s,
  zoom 17.5, low-screen van and counter-rotated markers. Near-stop navigation ends
  to reveal full Arrived panel; next stop resumes it. Compact stop bar shows
  distance/time/arrival and expands on tap. Top bar toggles with map taps and
  SafeArea preserves credits. Voice mute lives on the map, not the hidden topbar.
  Copied_from_date is preserved for owner provenance, not a driver banner.

Driving, photos and lifecycle:

  DriverRunScreen is read-only plan/history; Drive/Start opens DrivingScreen.
  DriverRouteScreen derives planned stops from circuit summaries + addresses so
  a booking can open before a run sheet exists. showStopDetails gives items,
  instructions, phone and delivered time/photo without inventing history.

  RouteStarter requires DriverSchedule.scheduledToday, warns before copying a
  prior sheet and adds run_starts owner_uid/round_key/requested_by/requested_at.
  It waits up to 45 s for ready+run_id or refused+reason before navigation.
  start-route-run authorization/today-copy behavior is a backend contract.
  The request itself is not driver_started_at; the driver's Start writes that.

  DeliveryWriter centralizes narrow Firestore/Storage mutations:
    start -> driver_started_at server timestamp.
    end -> ensure start if needed, then driver_ended_at server timestamp.
    left/resumed -> driver_left_at / driver_resumed_at server timestamp.
    arrived -> stop.arrived_at server timestamp.
    delivered -> status='delivered', delivered_at server timestamp;
      optional pod_photo_url and delivered_lat/lng/delivered_accuracy_m.

  DrivingLogic offers Arrived within 60 m plus nonnegative GPS allowance capped
  at 40 m; when no location exists it preserves a manual fallback. Do not make
  users stuck on refused permissions or claim any raw accuracy is accepted.
  Start, delivery and End buttons must preserve duplicate/error/remaining-stop
  handling and return truthful failures; End with stops left asks first.

  PhotoStamp runs in a background isolate, bounds long side to 1280 px and JPEG
  quality 70, burns timestamp/run/stop/customer into an ASCII bitmap-font bar.
  Output size depends on input; 150-300 KB is an old observation, not a bound.
  Store {ownerUid}/{runId}/{stopId}.jpg under podPhotosBucket with run_id/stop_id
  metadata. pod_photo_url is a gs:// reference resolved by PodPhoto through
  getDownloadURL, not an automatically public HTTP URL. If photosAvailable is
  false, delivery can continue without photo. Upload finishes before delivery
  update; failed Firestore update after upload is not a cross-service transaction.
  Test/inspect orphan/retry paths rather than claiming atomic photo+delivery.

  VoiceGuide queues speech through flutter_tts; urgent turns replace pending
  cues. DrivingLogic owns start/next/150 m approach text; TurnByTurn owns turn
  guidance. Muting follows user_settings.voice_prompts; enabling says next stop.
  Location and voice are foreground/screen-scoped. Wakelock is not background
  tracking permission or a dedicated foreground location service.

  PopScope asks Stay/Leave/End for a run underway, based on latest run state.
  Leave writes driver_left_at, returning writes driver_resumed_at; backend
  notify-run handles owner notifications. Not-started/finished runs just close.
  RunHeartbeat writes run_live every minute while a started screen is active:
  owner_uid/rider_id, server last_seen_at, optional fix/accuracy/heading/speed.
  Closing app, lost signal or flat battery leads to silence, not proof of offline
  shift presence. Heartbeat location is not the owner's rendered live van.

Notifications, crash reports and platform contracts:

  PushNotifications registers after sign-in, asks Android 13+ permission, writes
  user_devices/{uid}/tokens/{token}, tracks rotation, unregisters before sign-out.
  Android renders background notification payloads; the app draws foreground
  messages with flutter_local_notifications. Background data handler initializes
  its plugin/isolate before drawing. No background-location permission is required
  for Android push delivery; plugin presence does not prove iOS/web equivalence.

  NotificationChannels identifiers: assignments, runs, live_runs, drivers,
  status, reminders. Backend ports/user_push.py and adapters/fcm_user_push.py
  mirror channel/payload contracts. Keep ic_stat_bluedot, bluedot_large,
  @color/bluedot_brand and FCM manifest defaults consistent across systems.
  New kinds get feature files/channels, not scattered one-off plugin calls.

  DriverPresence writes owner_uid/online/server changed_at at driver_presence/{uid}.
  The driver's status notification shows online/offline; notify-presence alerts
  owners according to personal preferences. Sign-out goes offline first.
  Presence is two declared states; neither a third mocked state nor live GPS.

  LiveRunNotification uses run_id tag, progress bar and start chronometer, remains
  ongoing/silent and times out after 30 minutes without updates. run_live_end
  cancels it; sign-out clears notifications. Do not leave a permanent stale row.
  Android desugaring supports local notification APIs; Dart analysis omits it.
  FlutterFire packages must remain a compatible set; native build catches plugin
  mismatches. Clean only when an identified stale plugin cache warrants it, not
  as an automatic prerequisite for every test.

  CrashReporting is enabled when non-web and non-debug, including profile, not
  literally 'release only'. Uncaught errors are fatal; AppLog area errors record
  caught nonfatal reports. Identify by UID/role, clear on sign-out; do not attach
  email or secret values. CRASH_TEST exposes test UI in profile/release; sending
  a real test crash affects a live service and requires explicit scope/approval.

UI reuse and unreachable code:

  Theme: lib/theme/app_colors.dart and app_theme.dart. Shared primitives include
  PrimaryButton, PillBadge, SectionLabel, StatTile, SurfaceCard, StageProgressBar,
  StopCard, RoutePreviewMap, StopInstructionsSheet and WeeklyBarChart. Reuse these
  rather than growing a parallel visual system. Inter variable font is registered
  for several weights from one asset; select fontWeight, not renamed families.

  prototypeAssets contains inherited mock references, not current owner spec.
  Owner HTML prototypes named in comments were never committed here. Historical
  .claude/plan.md plus current Dart explain rationale; source wins on actual UI.
  lib/screens/customer/* and customer AppState are unreachable prototype paths.
  run_sheet_diff_screen.dart is superseded by RunSheetReviewScreen. Do not extend
  dead mock tabs or revive RiderBoardApi to solve live owner/driver behavior.

Contract-to-test map:

  Address hash/depot lookup: test/depot_locator_test.dart;
    test/run_sheet_review_test.dart; lib/services/depot_locator.dart.
  Order-independent load totals/maps/widgets: test/run_sheet_review_test.dart.
  Route naming/diff: test/route_naming_test.dart.
  Estimate/parsing: test/delivery_estimate_test.dart; test/road_legs_test.dart.
  Invitations/bounds/time: test/driver_invitation_test.dart.
  Profiles: test/owner_profile_test.dart.
  Assignment/day-window: test/route_assignment_test.dart; test/run_time_test.dart.
  Run phase/history/timing: test/run_listing_test.dart; test/run_timing_test.dart.
  Driver schedule/stats: test/driver_schedule_test.dart; test/driver_stats_test.dart.
  Driving/turn geometry/API-response parsing: test/driving_logic_test.dart;
    test/turn_by_turn_test.dart. Parser fixtures do not establish HTTP behavior.
  Photo bytes/stamp: test/photo_stamp_test.dart.
  Map configuration/header safety: test/map_config_test.dart; test/basemap_test.dart.
  Stop search/auth error text: test/stop_search_test.dart;
    test/auth_error_message_test.dart.

  These files do not certify production rules, triggers, tenant isolation,
  Firebase sign-in, server event ordering, GPS/camera/TTS or notifications.
  Select an approved environment/accounts and read back authorized changes
  for integration checks. If backend code/access is absent, state BLOCKED or
  NOT RUN instead of inventing a passing server check. Keep preservation and
  exact-shape invariants here; record changing versions in architecture.md.
