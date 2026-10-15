Blue Dot functional architecture:

Purpose and evidence boundary:
  Blue Dot is the Flutter package dmm_delivery: owners prepare and supervise
  delivery routes; drivers receive assignments and record actual deliveries.
  This document describes the reachable client, its data ownership and its
  integration contracts, not a second low-level implementation guide.

  CLIENT means behavior observed in source in this checkout, not a completed
  live Firebase integration test. CONTRACT means backend behavior described by
  client comments or the existing detailed guide, NOT LOCALLY VERIFIED. The
  expected sibling ../dmm-delivery-app does not exist in this workspace. No
  functions, rules, Terraform, cloud configuration or backend tests were read
  from that repository, and no cloud requests were issued for this document.

  Local citations use repository-relative paths, sometimes with line ranges or
  method names. Code and pubspec.lock outrank historical documentation. In
  particular, .claude/plan.md and parts of the prior .claude/CLAUDE.md describe
  earlier mock screens and obsolete scheduling assumptions.

Reading routes:
  Shared agent rules: AGENTS.md.
  Detailed implementation contracts and traps: .claude/technical-lld.md,
    the coordinated migration destination of the detailed .claude/CLAUDE.md.
  TDD workflow: .claude/tdd/README.md.
  Review workflow: .claude/review/README.md.
  Build/environment operations: BUILD.md; cloudbuild.yaml;
    tool/generate_infra_config.sh. Do not run config sync for ordinary builds.
  The low-level guide is owned by the coordinated documentation migration;
  its destination above is not a backend implementation path.

Functional model and current feature boundaries:
  A route is a persistent circuit, keyed by round_key, with a current name,
  latest_run_id and stops_summary. A run is a route's deliveries for one date,
  with ordered delivery_stop children and progress/history on the parent run.
  A booking is an effective-dated assignment; it can exist before that date's
  run sheet. A driver is AuthRole.driver in the UI but rider in token claims
  and backend field names. owner_uid is the business boundary, not a label.
  Sources: lib/models/run_listing.dart:23-31,111-153;
    lib/models/route_assignment.dart:5-22; lib/driver/driver_schedule.dart:4-50;
    lib/state/auth_state.dart:15-19,79-105.

  Owner features:
    Home: greeting, live runs and overdue starts, sorted problems first, with
      driver, vehicle, delivered count, next stop and timing; quick access to
      invitation and route update. This is real Firestore-backed supervision,
      not the removed mock rider-board or a live GPS van map.
    Routes: create/update a route from a PDF; review the proposed map, product
      lines, load-out totals, changes and estimated time; rename, reorder,
      remove/undo stops, confirm or discard. Confirmed routes remain editable;
      stop instructions can be overridden for future processing.
    Runs: Upcoming/Today/Past views of confirmed runs; delivered pins, per-stop
      delivery times, run start/finish/total time and a delivery-photo gallery.
      Deleted-route runs and superseded drafts are excluded from run lists.
    Drivers: invite drivers by email, display pending/expired/accepted/removed
      states, rename/renew invitations and request removal/restoration. The
      actual invite dialog invites drivers only. Backend-controlled owner
      enrollment is not an owner-creation feature of this roster.
    Driver detail: backend-written driving record/recent runs, regular routes,
      one-day cover and future handovers, schedule/time changes/cancellations,
      plus add/assign/change/remove a vehicle from a driver.
    Settings: personal notification choices and account profile; business-wide
      invitation deadline and default stop time. Profile information is
      client-owned descriptive data, not delivery-pipeline identity.
  Sources: lib/screens/root_shell.dart:63-84;
    lib/screens/owner/owner_home_screen.dart:32-77;
    lib/screens/owner/live_runs_section.dart:29-99;
    lib/screens/owner/owner_routes_screen.dart;
    lib/screens/owner/run_sheet_review_screen.dart:_load,_respond;
    lib/screens/owner/route_map_screen.dart:86-134,287-348;
    lib/screens/owner/runs_screen.dart:16-64;
    lib/screens/owner/owner_run_data.dart:69-123;
    lib/screens/owner/run_detail_screen.dart:86-128;
    lib/screens/owner/run_photos_screen.dart;
    lib/screens/owner/owner_drivers_screen.dart:48-62,92-111;
    lib/screens/owner/driver_detail_screen.dart:127-267;
    lib/settings/settings_screen.dart; lib/state/auth_state.dart:180-207.

  Scheduling IS implemented through Routes and Driver detail, using the shared
  scheduling sheet. Home still has a disabled Delivery roster card with the
  literal subtitle 'Scheduling not built yet'. That stale placeholder is not
  evidence that route assignments, one-day cover or run scheduling are absent.
  Sources: lib/widgets/schedule_run_sheet.dart:44-90,205-215;
    lib/services/route_assigner.dart; lib/screens/owner/owner_routes_screen.dart;
    lib/screens/owner/driver_detail_screen.dart:248-263;
    lib/screens/owner/owner_home_screen.dart:50-59.

  Driver features:
    Home/Runs/Routes share live run, circuit, assignment and vehicle queries.
      Home selects a live run or next job; Runs includes bookings before a
      sheet exists; Routes shows current and future regular routes. The
      business's whole schedule is read so a colleague's cover is visible.
    Online/Offline writes explicit driver presence and draws the driver's own
      status notification. Presence is a declared shift state, not a GPS feed
      and not proof of delivery activity.
    Route/run preview: route plans can open before a day's sheet, using circuit
      summaries and address-cache pins. Runs show actual delivery history.
    Start today's route: request today's sheet or a copy of the last sheet from
      the backend, then open driving. The copy warning is shown first.
    Driving: GPS-following map, in-app turn instructions/voice, Start, Arrived,
      camera photo or delivery without photo, Delivered, End, and guarded
      Leave/Resume. The next stop is the first undelivered ID in route order.
      Arrived is offered near the pin (60 m plus accuracy allowance capped at
      40 m); manual arrival remains possible when location is unavailable.
    Evidence: photos are shrunk/stamped off the UI isolate and uploaded before
      the stop is marked delivered. Delivery includes server time and optional
      phone coordinates/accuracy. No photo is offered if its bucket is absent.
    Settings: before-run reminders and voice prompts. Notification denial is
      nonblocking. Location/voice are screen-scoped; there is no implemented
      dedicated background-location foreground service to promise closed-app
      tracking. Wakelock keeps an open driving screen awake.
  Sources: lib/driver/driver_shell.dart:49-75; lib/driver/driver_data.dart:41-96;
    lib/driver/driver_schedule.dart:54-134; lib/driver/driver_home_screen.dart:32-59;
    lib/driver/driver_presence.dart; lib/driver/driver_route_screen.dart:61-116;
    lib/driver/driver_run_screen.dart:22-26,90-117; lib/driver/route_starter.dart;
    lib/driver/driving/driving_screen.dart:205-247,289-355,398-469,595-623;
    lib/driver/driving/driving_logic.dart:15-36;
    lib/driver/driving/delivery_writer.dart; lib/driver/driving/photo_stamp.dart;
    lib/settings/driver_settings_screen.dart; android/app/src/main/AndroidManifest.xml.

  Not the live product:
    lib/screens/customer/ and lib/state/app_state.dart remain prototype paths
    unreachable from the actual AuthGate/RootShell. The old diff-only screen
    lib/screens/owner/run_sheet_diff_screen.dart is not the upload review path.
    riderBoardUrl is generated but has no runtime caller in lib/. The old board's
    fabricated route/position must not be presented as current live tracking.
  Sources: lib/main.dart; lib/screens/root_shell.dart;
    lib/screens/owner/run_sheet_progress_screen.dart:137-147;
    lib/screens/owner/runs_screen.dart:16-24; lib/config/infra_config.dart;
    source-reference search for AppState, riderBoardUrl and run_sheet_diff_screen.

Component diagram:
  Solid arrows describe client wiring. Dotted arrows cross an external backend
  CONTRACT boundary; trigger execution and server behavior were not verified.

  +----------------------- dmm_delivery checkout --------------------------+
  | main -> Firebase init -> AuthState -> AuthGate -> RootShell            |
  |                                   |                 |                 |
  |                             role/owner_uid     +-----+------+          |
  |                                               |            |          |
  | Owner Home/Routes/Runs/Drivers             DriverShell                |
  | Upload -> Progress -> Review              Home/Runs/Routes             |
  | RouteMap / RunDetail / Photos             Preview -> DrivingScreen    |
  |            |                                  |                      |
  | RouteEditor / Renamer / Assigner          DeliveryWriter / Heartbeat   |
  | DriverInviter / AccessApi / Vehicle       GPS / Camera / TTS / Wakelock|
  |            +-------------+--------------------+                      |
  | SettingsStore + models + shared maps + notifications + CrashReporting |
  +--------------------------+-------------------------------------------+
                             |
            +----------------+----------------------+------------------+
            |                |                      |                  |
        Firebase Auth    Firestore              Storage          Crashlytics
        Google sign-in   subscriptions          PDF / POD         errors
            |            and bounded writes         |
            :                :                      :
  +---------:----------------:----------------------:--------------------+
  | External dmm-delivery-app CONTRACT:                                  |
  | beforeSignIn; process/confirm upload; refresh-run; assignment stamping|
  | start-route-run; check-deviation/progress; driver-access; notify-*     |
  | Firestore/Storage rules; Terraform/IAM/API restrictions               |
  +--------------------------:------------------------------------------+
                             :
                  FCM -> push/background handler -> local notifications

  Shared maps -> CARTO raster tiles OR Google Map Tiles sessions/tiles/viewport
  Driving     -> Google Routes computeRoutes -> TurnByTurn -> UI + VoiceGuide
  Backend     ..> geocoding / Route Optimization / road-leg Routes (CONTRACT)

Module responsibilities and state flow:
  lib/main.dart and lib/screens/auth/: initialize Firebase/observability and
    gate identity. RoleSelect changes sign-in copy only; the server claim
    determines access. SignInScreen removes its own pushed route on success.
  lib/state/auth_state.dart: long-lived ChangeNotifier for token state,
    owner_uid, role, Google sign-in, sign-out and profile/invitation/schedule
    streams. Missing role and missing owner_uid have different recovery states.
  lib/screens/root_shell.dart and lib/driver/driver_shell.dart: role-specific
    navigation; IndexedStack preserves tab widgets. No AppState mock data is
    injected into these shells.
  lib/screens/owner/: document-stream orchestration and owner interactions.
    OwnerRunDataBuilder combines confirmed runs, circuits, assignments,
    invitations and vehicles; RunLiveBuilder reads heartbeat times for up to
    30 run IDs. Run detail streams stops independently of run aggregates.
  lib/driver/: shared live data, pure schedule selection and preview/navigation
    entry points. Route previews read summaries/cache instead of trying to
    open another driver's or an old day's run as today's plan.
  lib/driver/driving/: screen orchestrates run/stop streams and phone plugins;
    DeliveryWriter isolates write shapes; DrivingLogic/TurnByTurn make pure
    decisions; RoutesClient fetches one-stop directions; PhotoStamp produces
    evidence; RunHeartbeat writes liveness; VoiceGuide queues local speech.
  lib/services/: small responsibility-specific adapters, not a general
    repository layer. Owner access removal is HTTP; ordinary route/invitation/
    assignment/fleet edits use Firestore SDK writes.
  lib/models/: parsing, date/status/schedule/estimate/timing calculations. Run
    progress aggregates are read, not recalculated by the client on every list
    card. DeliveryEstimate re-estimates a dragged route locally using learned
    leg times first, then road seconds times speed factor, then a straight-line
    fallback; dwell uses learned address time or the business default.
  lib/widgets/: map/stop primitives, shared scheduling sheet and reusable
    presentation. RoutePreviewMap renders structured geometry, never a server
    map image. Missing road legs are straight segments, not fabricated roads.
  lib/settings/: merged business/personal settings writes and setting cards.
  lib/notifications/: token lifecycle, foreground display, background data
    handler, Android channels, live-run and driver-presence notifications.
  lib/observability/crash_reporting.dart: fatal and caught-error reporting.
    Actual enablement is non-web and non-debug, including profile builds; debug
    reporting is disabled. Reports identify uid/role, not intended email/name.
  Sources: the module files above; lib/models/delivery_estimate.dart:67-120;
    lib/models/road_legs.dart:25-41; lib/widgets/route_preview_map.dart:36-48;
    lib/observability/crash_reporting.dart:26-57.

Firebase/data responsibilities and integration boundaries:
  Firebase Auth:
    GoogleSignIn supplies an ID token to signInWithCredential; the app forces
    getIdTokenResult(true) and listens to idTokenChanges. role=owner or rider
    plus owner_uid gates tenant-scoped views. Server beforeSignIn enrollment,
    invitation validation and claim minting are CONTRACT, not client logic.
    The roster comments describe owner enrollment via backend OWNER_EMAILS;
    sign-in screen copy alone does not prove automatic owner authorization.
    Sources: lib/state/auth_state.dart:79-143;
      lib/screens/auth/auth_gate.dart:34-94;
      lib/screens/owner/owner_drivers_screen.dart:48-62.

  Firestore:
    circuits/{roundKey}: current route projection/name/latest run. Client reads,
      renames round+round_source through RouteRenamer, and deletes a circuit;
      backend projection and deletion side effects remain CONTRACT.
    delivery_run/{runId}/delivery_stop/{stopId}: draft/confirmed run and ordered
      stops. Owners edit seq_order/excluded with a parent order_revision bump.
      Drivers write start/end/leave/resume on the run and arrival/delivery on
      assigned stops. Backend owns road_legs, estimates and progress aggregates.
    run_sheet_upload/{uploadId}: processing/status/diff/draft_run_id contract;
      owner responds confirmed or discarded with optional manual_order/name.
    route_assignments: append-only dated schedule rows; no client update/delete.
      one_day overrides that day; absent one-day times borrow regular times.
      A correction/cancellation/unassignment is another row, retaining history.
    run_starts/{requestId}: client request; backend answer ready+run_id or
      refused+reason. Request timeout is 45 seconds, not a backend cancellation.
    driver_invitations/{normalizedEmail}: driver enrollment and roster state;
      invite/resend merges preserve server counters; rename is a narrow update.
      Removal/restoration goes through driver-access, not document deletion.
    addresses/{sha256(trim(lowercase(address)))}: read-only geocode cache used
      by depot and driver route previews; no second client geocoding request.
    stop_instructions/{ownerUid}__{addressKey}: merged owner override and
      provenance fields. Backend instruction-resolution propagation is CONTRACT.
    vehicles: client fleet writes/assignments, batched to take back an existing
      vehicle when assigning another; driver queries its assigned vehicle.
    driver_stats: read-only backend summary on Driver detail.
    driver_presence/{uid}: explicit online state and server changed_at.
    run_live/{runId}: separate heartbeat document with server last_seen_at and
      optional coordinates; avoids waking run triggers every minute.
    app_settings/{ownerUid}: default_stop_seconds and invitation_ttl_days.
    user_settings/{uid}: driver_presence_alerts, late_start_alerts,
      run_reminders, reminder_lead_minutes, voice_prompts.
    user_profiles/{uid}: own descriptive profile, replaced rather than merged
      so clearing an optional field actually removes it.
    user_devices/{uid}/tokens/{token}: registration metadata for per-user FCM.
  Sources: lib/screens/owner/owner_run_data.dart; lib/driver/driver_data.dart;
    lib/screens/owner/route_map_screen.dart; lib/services/route_editor.dart;
    lib/services/route_renamer.dart; lib/services/route_assigner.dart;
    lib/models/route_assignment.dart:96-113; lib/driver/route_starter.dart;
    lib/services/driver_inviter.dart; lib/services/driver_access_api.dart;
    lib/services/depot_locator.dart; lib/widgets/stop_instructions_sheet.dart;
    lib/services/vehicle_service.dart; lib/screens/owner/driver_detail_screen.dart;
    lib/driver/driver_presence.dart; lib/driver/driving/run_heartbeat.dart;
    lib/settings/settings_store.dart; lib/state/auth_state.dart:186-206;
    lib/notifications/push_notifications.dart:102-114.

  Storage:
    PDFs go to InfraConfig.runSheetsBucket at {roundKey}/{uploadId}.pdf with
    uploadId, roundKey, ownerUid and optional routeName metadata. They do NOT
    go to the default Firebase bucket. Photo bytes go to
    InfraConfig.podPhotosBucket at {ownerUid}/{runId}/{stopId}.jpg with
    run_id/stop_id metadata. pod_photo_url stores a gs:// reference, not an
    immediately public HTTP URL; PodPhoto resolves it through getDownloadURL.
    A Storage upload and a subsequent Firestore delivery write are separate
    operations, not a cross-service transaction.
    Sources: lib/screens/owner/upload_run_sheet_screen.dart:163-205;
      lib/driver/driving/delivery_writer.dart:75-100; lib/widgets/pod_photo.dart.

  FCM/local notifications:
    AuthGate registers a phone after sign-in; token rotation writes the new
    token and deletes the old. Sign-out removes the device token and clears
    local notifications before Firebase signOut. Android notification payloads
    display in the background; foreground notifications are drawn by the app.
    Data types run_live/run_live_end update/cancel a progress notification using
    run_id as tag; its 30-minute timeout avoids indefinitely stale displays.
    Channels are assignments, runs, live_runs, drivers, status and reminders.
    Payload/channel/server fan-out are CONTRACT; client rendering is inspected.
    Push registration skips web; the local initialization shown is Android
    specific. Do not assume equivalent iOS/web delivery from package presence.
    Sources: lib/notifications/push_notifications.dart:54-150;
      lib/notifications/live_run_notification.dart:26-70;
      lib/notifications/notification_channels.dart;
      android/app/src/main/AndroidManifest.xml:40-52.

External mapping and phone capabilities:
  flutter_map renders the viewport, road overlays, stops and van; latlong2
  supplies coordinates/distances. Simple uses CARTO Positron raster tiles via
  MapConfig.basemapUrlFor and the CARTO_API_KEY compile-time define. Detailed
  and Satellite use Google Map Tiles createSession, 2dtiles and viewport
  copyright requests. Sessions are reused per style until one hour before the
  returned expiry. The Google tile provider disables disk caching; credits use
  the Google logo/viewport text or CARTO/OpenStreetMap credit. A Google session
  failure falls back to Simple; a missing Google key removes Google choices.
  Missing/unkeyed CARTO watermark behavior is a source-comment observation,
  not an independently tested provider policy or service guarantee here.

  Driver navigation directly POSTs to routes.googleapis.com,
  /directions/v2:computeRoutes, with DRIVE, TRAFFIC_UNAWARE, a field mask for
  geometry/duration/distance/step instructions, and a 12-second timeout. It
  shares GOOGLE_MAP_TILES_KEY and X-Android-Package/X-Android-Cert headers with
  tiles. It is not a launch of the external Google Maps application, despite
  stale introductory comments in driving_screen.dart. Backend whole-route
  optimization/road-leg generation is separate from client next-stop guidance.
  Re-route after two off-route fixes uses 50 m plus capped accuracy allowance;
  requests are throttled to at least 10 seconds apart. Failed directions expose
  a retry state rather than issuing a request on every GPS fix.

  Phone integrations: geolocator high-accuracy location (5 m distance filter),
  image_picker camera, image isolate processing, flutter_tts local speech and
  wakelock_plus. None is a separate cloud orchestration layer.
  Sources: lib/config/map_config.dart; lib/services/google_map_tiles.dart;
    lib/models/map_style.dart; lib/widgets/basemap.dart;
    lib/widgets/basemap_attribution.dart; lib/driver/driving/routes_client.dart;
    lib/driver/driving/driving_screen.dart:227-355;
    lib/driver/driving/turn_by_turn.dart:85-91,141-142;
    lib/driver/driving/photo_stamp.dart; lib/driver/driving/voice_guide.dart.

External backend function contracts, NOT LOCALLY VERIFIED:
  The named functions/files below belong to external dmm-delivery-app, not to
  lib/ or a backend/ directory in this checkout. Names are integration clues
  from source comments, not a verified inventory of deployed infrastructure.

  beforeSignIn / before_sign_in_fn.py / application/handle_sign_in.py:
    resolve allowed owner/driver identity, invitations and business claims.
  process-run-sheet-upload / process_run_sheet_upload_fn.py /
    process_run_sheet_upload.py: Storage-triggered PDF processing, diff/draft,
    geocoding, sequencing and ready_for_review/no_changes/error status.
    CONTRACT: re-uploads preserve owner decisions; order_strategy reports
    optimized/reused/merged/learned rather than always doing fresh optimization.
    Google Geocoding and Route Optimization are backend-only contracts here.
  confirm-run-sheet / confirm_run_sheet_upload.py:
    consume confirmed/discarded, optional retained-stop manual_order and naming,
    publish circuit/latest run and assign rider_id for the run's date.
  refresh-run and application/road_legs.py:
    react to order_revision, redraw road_legs, re-estimate and update circuit
    summary using backend routing/travel-time logic.
  assign_route_runs.py / notify-assignment:
    stamp assignments onto open runs and notify affected drivers. Old run
    history must not be erased by append-only schedule corrections.
  start-route-run:
    authorize the current day's scheduled driver, return today's confirmed run
    or create a copy of the latest sheet; write ready/refused to run_starts.
  check-deviation / domain/run_progress.py:
    delivered-stop progress aggregation and learning; client reads the resulting
    run fields. driver_stats generation is also server-owned.
  notify-run / notify-presence / run-alerts:
    run start/finish/leave/resume/live progress, explicit presence, reminders,
    late starts/running-late/stopped-reporting alerts via per-user FCM tokens.
  driver-access / application/manage_driver_access.py:
    HTTP POST {email, action: remove|restore}, Firebase Bearer ID token, JSON
    {removed, account_changed}; client handles 401/403/404 and a 30 s timeout.
    CONTRACT: verify owner/business, preserve roster history and disable/enable
    Auth account as well as update removal state. Client holds no Admin SDK.
  firestore.rules / storage.rules / storage_pod_photos.rules:
    enforce tenant/role access and exact allowed write shapes. Client queries
    and error messages reflect these contracts, not proof of deployed rules.
  maps.tf / firebase_apps.tf / Terraform:
    backend-described API restrictions and Firebase registrations. IAM,
    identities, resource limits, actual API enablement and runtime versions
    cannot be certified without the absent backend and deployment inspection.
  Sources: comments in lib/state/auth_state.dart, lib/services/depot_locator.dart,
    lib/screens/owner/upload_run_sheet_screen.dart,
    lib/screens/owner/run_sheet_review_screen.dart, lib/services/route_editor.dart,
    lib/driver/driver_data.dart, lib/driver/route_starter.dart,
    lib/driver/driving/delivery_writer.dart, lib/models/run_listing.dart,
    lib/driver/driving/run_heartbeat.dart, lib/services/driver_access_api.dart,
    lib/settings/settings_store.dart, lib/config/map_config.dart;
    prior detailed .claude/CLAUDE.md contract sections (migration target above).

Infrastructure and repository separation:
  Client checkout: Flutter source/tests, Android/platform wrappers, assets,
    pubspec/lock, generated endpoint/bucket config and client build pipeline.
  External backend: Python application/domain contracts, triggers, rules,
    Terraform and Google service integrations. Do not treat references to
    external Python filenames as local editable code paths.
  InfraConfig describes committed bindings for project i-destiny-428904-s2 and
    generator default region us-west1; those values do not prove the currently
    deployed project's condition. firebase_options.dart is selected by main,
    but no Firebase API-key values are reproduced here.
  Config sync discovers the actual PDF trigger bucket, Google sign-in client,
    optional driver-access/rider-board URLs and one photo bucket from live
    GCP/Firebase state. The script is not part of routine local startup. It can
    reconfigure Firebase on an explicit environment move; that operation was
    not run. BUILD.md governs its scope and human review.
  cloudbuild.yaml describes require-target-project -> sync-infra-config ->
    flutter-analyze -> release appbundle. It uses a floating stable Flutter
    image, not the verified local SDK pin, and does not run flutter test.
    Pipeline existence is not evidence of a registered trigger or passing CI.
  Android release currently uses the project's debug signing configuration,
    not a production release key. Map key/package/certificate restrictions
    are a backend contract that must match the signing identity.
  Sources: lib/config/infra_config.dart; lib/main.dart:17-18;
    tool/generate_infra_config.sh:60,91-142,189-199; BUILD.md;
    cloudbuild.yaml:43-84; android/app/build.gradle.kts:43-64.

Sequence diagrams:
  Each numbered diagram proceeds top to bottom. C arrows are inspected CLIENT
  calls/subscriptions; B dotted arrows are external backend CONTRACT effects.
  They show implemented client paths, not end-to-end execution evidence.

Sequence 1: authentication and role routing:
  Person       SignIn/AuthState        Google/Firebase       Gate/Shell
    |                 |                      |                  |
    |-- C Continue -->|-- C authenticate ---->|                  |
    |                 |<- C Google ID token -|                  |
    |                 |-- C credential ------>|                  |
    |                 |                      |.. B beforeSignIn
    |                 |                      |   allow/invite checks
    |                 |                      |   role + owner_uid
    |                 |-- C forced refresh ->|                  |
    |                 |<- C idTokenChanges --|                  |
    |                 |-- C signedIn --------------------------->|
    |                 |                      |         owner -> Owner shell
    |                 |                      |         rider -> DriverShell
    |                 |-- C dismiss pushed SignInScreen          |
    |                 |                      |                  |
  No role -> needsRole recovery; role without owner_uid -> staleSession.
  Gate also starts push registration and uid/role crash identity. The role
  selection card never mints the role. Sources: lib/state/auth_state.dart:64-143;
  lib/screens/auth/auth_gate.dart:34-94; lib/screens/auth/sign_in_screen.dart:138-146;
  lib/screens/root_shell.dart:23-29.

Sequence 2: upload, review and confirmation:
  Owner/Upload        Storage         Backend(B)       Firestore       Review
    |                    |                |               |              |
    |-- C PDF+metadata ->|                |               |              |
    |                    |.. B finalize ..>|.. B draft --->|              |
    |-- C watch run_sheet_upload ------------------------>|              |
    |<-- C status ready_for_review/no_changes -------------|              |
    |-- C open review -------------------------------------------------->|
    |                    |                |               |<-- C run/stops
    |                    |                |               |-- C draft --->|
    |-- C reorder/remove/name locally ---------------------------------->|
    |                    |                |               |<-- C confirmed
    |                    |                |               |    + optional
    |                    |                |               |    manual_order
    |                    |                |               |    + owner name
    |                    |                |<.. B change ...|              |
    |                    |                |.. B publish -->|              |
    |<-- C return to root after status write --------------|              |
  The client does not await a separate successful backend publication before
  returning. Discard writes discarded instead. Edits are held locally until
  Confirm; unlocated stop IDs are retained in a submitted manual_order, while
  removed IDs are omitted. A missing upload document, stream error or 90-second
  stall gets a visible recovery state; the stall does not cancel processing.
  Sources: lib/screens/owner/upload_run_sheet_screen.dart:137-229;
  lib/screens/owner/run_sheet_progress_screen.dart:45-149;
  lib/screens/owner/run_sheet_review_screen.dart:193-235,348-391.

Sequence 3: confirmed route edit and refresh:
  Owner/RouteMap        RouteEditor       Firestore          Backend(B)
    |                        |               |                  |
    |-- C drag/remove/undo ->|               |                  |
    |-- C local estimate/pending order       |                  |
    |                        |-- C batch --->|                  |
    |                        |  seq_order/excluded              |
    |                        |  order_revision +1               |
    |                        |  order_source=owner              |
    |<-- C stop snapshots -------------------|                  |
    |                        |               |.. B refresh-run >|
    |                        |               |<.. B road_legs ..|
    |                        |               |    estimate/summary
    |<-- C run/circuit snapshots ------------|                  |
    |-- C redraw retained/new road legs     |                  |
  Removal is excluded, not deletion. Missing geometry remains a straight
  segment until refresh succeeds. The inspected code batches changes but does
  not supply a general multi-owner edit conflict-resolution transaction.
  Sources: lib/screens/owner/route_map_screen.dart:86-134,191-204,287-348;
  lib/services/route_editor.dart:28-84; lib/models/road_legs.dart:3-11.

Sequence 4: scheduling and assignment propagation:
  Owner/ScheduleSheet    RouteAssigner     Firestore        Backend(B)    Driver
    |                         |               |                |           |
    |-- C choose date/window/driver           |                |           |
    |   recurring-from-date or one_day       |                |           |
    |-- C ScheduleChoice ---->|-- C new row ->|                |           |
    |                         |               |.. B assignment >|           |
    |                         |               |<.. B rider_id ..|           |
    |                         |               |                |.. B FCM ..>|
    |                         |               |<-- C streams --------------|
    |                         |               |-- C rows/runs ------------>|
    |                         |               |                |   resolve tabs
  Times are HH:MM; the sheet suggests finish from the latest run estimate.
  Changing times/removing driver/cancelling cover appends another row. One-day
  cover beats a regular row on that local day; past history remains readable.
  Sources: lib/widgets/schedule_run_sheet.dart:75-90,144-152,205-215;
  lib/services/route_assigner.dart:30-118;
  lib/models/route_assignment.dart:96-113,183-200;
  lib/driver/driver_data.dart:20-22,45-63.

Sequence 5: request today's run and start driving:
  Driver/Preview       RouteStarter       Firestore        Backend(B)   Driving
    |                      |                 |                |           |
    |-- C Start today ---->|                 |                |           |
    |<-- C last-sheet-copy warning ----------|                |           |
    |-- C confirm -------->|-- C run_starts ->|                |           |
    |                      |                 |.. B request --->|           |
    |                      |                 |                | check schedule
    |                      |                 |                | today/copy run
    |                      |                 |<.. B ready .....|           |
    |                      |<- C ready/run_id|                |           |
    |                      |-- C open ----------------------------------->|
    |                      |                 |<-- C driver_started_at ----|
    |                      |                 |<-- C heartbeat while active |
  ready opens the driving screen; driver Start records driver_started_at.
  refused+reason or 45-second wait expiry shows a message. Starting a route
  request is not itself proof that driver_started_at has been written.
  Sources: lib/driver/route_starter.dart:25-99;
  lib/driver/driving/driving_screen.dart:205-214,398-402;
  lib/driver/driving/delivery_writer.dart:39-49;
  lib/driver/driving/run_heartbeat.dart:40-71.

Sequence 6: delivered photo, progress and push:
  Driver/Driving     Camera/Stamp     Storage     Firestore    Backend(B)   Owner
    |                    |              |            |            |         |
    |-- C Arrived ---------------------------------->|            |         |
    |-- C photo -------->|              |            |            |         |
    |<- C stamped JPEG --|              |            |            |         |
    |-- C upload JPEG ----------------->|            |            |         |
    |<- C upload complete / gs reference|            |            |         |
    |-- C delivered + server time + optional GPS ---->|            |         |
    |<-- C stop stream / next undelivered ------------|            |         |
    |                    |              |            |.. B check >|         |
    |                    |              |            |<.. B progress         |
    |                    |              |            |            |.. B FCM >|
    |                    |              |            |-- C run/stop stream ->|
    |                    |              |<-- C getDownloadURL + photo -------|
    |                    |              |            |     local live-run UI |
  Photo cancel leaves the stop undelivered; delivery without photo skips
  camera/storage. Upload failure prevents the awaited delivery update. A
  successful upload followed by failed Firestore update is not atomic success.
  Server progress includes delivered_count/next_stop/start/last/completion;
  notify-run data is rendered by foreground or background client handlers.
  run_live_end cancels the tagged live notification. Sources:
  lib/driver/driving/driving_screen.dart:404-445;
  lib/driver/driving/photo_stamp.dart:29-73;
  lib/driver/driving/delivery_writer.dart:64-100;
  lib/models/run_listing.dart:23-31,111-130;
  lib/notifications/push_notifications.dart:118-150;
  lib/notifications/live_run_notification.dart:26-70;
  lib/screens/owner/run_detail_screen.dart:86-128; lib/widgets/pod_photo.dart.

Sequence 7: in-app turn guidance and re-route:
  GPS/Phone            DrivingScreen       RoutesClient/Google     Voice/Map
    |                       |                     |                  |
    |-- C position fix ---->|                     |                  |
    |                       |-- C current stop -->|                  |
    |                       |    computeRoutes    |                  |
    |                       |<- C geometry/steps -|                  |
    |                       |-- C TurnByTurn.progress/cue ---------->|
    |-- C next fixes ------>|                     |                  |
    |                       | two off-route fixes |                  |
    |                       |-- C re-route ------>|                  |
    |                       |  >=10 s throttle    |                  |
    |                       |<- C revised route --|                  |
    |                       |-- C urgent recalculating/turn -------->|
  Near the stop, navigation gives way to the delivery panel. Network failures
  leave a retry banner; local stop/voice decisions are not proof of a road API
  response. Sources: lib/driver/driving/driving_screen.dart:281-355;
  lib/driver/driving/routes_client.dart:36-81;
  lib/driver/driving/turn_by_turn.dart:93-179; lib/driver/driving/voice_guide.dart.

Version inventory:
  Application version: 1.0.0+2 (pubspec.yaml:19).
  Declared minimum/constraint: Dart ^3.12.0, Flutter >=3.44.0.
  Lock SDK requirements: Dart >=3.12.0 <4.0.0, Flutter >=3.44.0.
  Verified local executable:
    /Volumes/MacintoshHDEXT/Library/Android/flutter-3.47.7/bin/flutter
    flutter --version returned Flutter 3.47.7 and Dart 3.13.5.
    This is observed tooling, not the minimum and not a CI-image guarantee.
  Sources: pubspec.yaml:19-23; pubspec.lock:1120-1122; local version command.

  Every direct dependency (name: pubspec constraint -> pubspec.lock version):
    flutter: sdk: flutter -> 0.0.0 (SDK lock sentinel, NOT Flutter runtime 0.0.0)
    cupertino_icons: ^1.0.8 -> 1.0.9
    firebase_core: ^4.13.0 -> 4.15.0
    firebase_auth: ^6.5.7 -> 6.7.0
    cloud_firestore: ^6.8.0 -> 6.10.0
    google_sign_in: ^7.2.0 -> 7.2.0
    firebase_storage: ^13.4.6 -> 13.6.0
    file_picker: ^12.0.0 -> 12.0.0
    flutter_map: ^8.3.1 -> 8.3.1
    latlong2: ^0.10.1 -> 0.10.1
    uuid: ^4.6.0 -> 4.6.0
    http: ^1.6.0 -> 1.6.0
    crypto: ^3.0.6 -> 3.0.7
    firebase_messaging: ^16.7.0 -> 16.7.0
    flutter_local_notifications: ^22.3.1 -> 22.3.1
    firebase_crashlytics: ^5.4.0 -> 5.4.0
    geolocator: ^14.1.1 -> 14.1.1
    flutter_tts: ^4.2.5 -> 4.2.5
    image_picker: ^1.2.4 -> 1.2.4
    wakelock_plus: ^1.8.0 -> 1.8.0
    image: ^4.10.1 -> 4.10.1
  Every direct dev dependency:
    flutter_test: sdk: flutter -> 0.0.0 (SDK lock sentinel)
    flutter_lints: ^6.0.0 -> 6.0.0
  Coverage: 21 direct main dependencies and 2 direct dev dependencies, 23 total.
  Hosted version constraints are not exact installed versions; the right-hand
  side records the lock resolution. Transitively installed packages are not
  omitted direct dependencies; they are outside this direct inventory.
  Sources: pubspec.yaml:31-70; pubspec.lock direct main/direct dev entries.

  Android configuration versions:
    Gradle wrapper: 8.14 (gradle-8.14-all.zip).
    Android Gradle Plugin: 8.11.1.
    Kotlin Android plugin: 2.2.20.
    Flutter plugin loader: 1.0.0; Flutter Gradle plugin comes from the SDK.
    Google Services plugin: 4.4.4.
    Firebase Crashlytics Gradle plugin: 3.0.6.
    NDK explicitly pinned: 28.2.13676358.
    Core library desugaring: enabled; desugar_jdk_libs 2.1.4.
    Java source/target compatibility and Kotlin JVM target: 17.
    Application ID/namespace: com.delivery.dmm_delivery.
    compileSdk/minSdk/targetSdk delegate to flutter.*SdkVersion, not numeric
      constants in app/build.gradle.kts; no resolved Android build was run here.
    Release signing: debug configuration, not production signing.
  Sources: android/gradle/wrapper/gradle-wrapper.properties:5;
    android/settings.gradle.kts:20-28; android/app/build.gradle.kts:12-40,59-74.

Verification scope and operational limits:
  This document was grounded in the inspected Dart paths/manifests cited above,
  not the stale feature inventory in plan.md. Tests inspected include
  test/run_sheet_review_test.dart (load totals/map primitives),
  test/route_assignment_test.dart (effective-dated assignment rules) and
  test/turn_by_turn_test.dart (pure navigation/response parsing). Additional
  test files exist for schedules, timing, estimates, invitations and photos;
  their existence is not a claim that Firebase/plugin integration was tested.

  No Firebase writes, Google/CARTO API calls, cloud build, config regeneration,
  emulator driving session or production-crash test was performed. No external
  official documentation pages were fetched, so no official-policy/version
  citations are asserted. Provider details here are observed client requests
  or explicitly labeled source-comment/backend contracts.

  Live trigger wiring, rule deployments, index availability, tenant isolation,
  API-key restrictions/quotas, enrollment policy and server event ordering all
  need verification against the actual backend and target deployment. Client
  UI updates and asynchronous FCM do not imply atomic or ordered propagation.
  Photo and delivery writes are separate; heartbeat is screen-scoped; owner
  maps do not currently render heartbeat coordinates as a live van.

  Cross-repo invariants to review together: role/rider/owner_uid claims; allowed
  write fields; address hash and owner-scoped instruction IDs; retained-stop
  manual_order; revision increments; schedule day/time precedence; run progress
  fields; notification channel/payload IDs; photo bucket/reference shape;
  estimate and alert thresholds. RunTiming currently uses 10-minute late-start,
  20-minute silence and 5-minute late margin thresholds; backend parity is only
  a stated contract until the external implementation is inspected.
  Sources: lib/models/run_timing.dart:44-53;
    lib/services/depot_locator.dart:22-39;
    lib/services/route_editor.dart:74-84;
    lib/notifications/notification_channels.dart;
    lib/driver/driving/run_heartbeat.dart; lib/driver/driving/delivery_writer.dart.
