# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter app "Blue Dot" (package `dmm_delivery`) — a Dunedin milk-delivery app backed by a real
Firebase/GCP project. Two roles, decided server-side, not by a UI toggle:

- **Owner** — uploads run-sheet PDFs, reviews/reorders the parsed route, watches a driver board. This is
  where essentially all real work has happened.
- **Driver** — still the original prototype's mock Rider tabs; the real driver-facing route view isn't built.

The backend lives in a **separate repo, `dmm-delivery-app`** (Cloud Functions + Terraform + Firestore
rules), checked out alongside this one at `../dmm-delivery-app`. Dart doc comments reference its files by
name (`process_run_sheet_upload.py`, `before_sign_in_fn.py`, `handle_sign_in.py`, `firestore_paths.py`,
`build_rider_board.py`) — those names are the contract. Its tests run with
`cd ../dmm-delivery-app && ./.venv/bin/python -m pytest` (106 tests). Several features span both repos —
route naming and the stop-order merge below are the current examples — and a client change that writes a
new Firestore field is inert until that repo's `firestore.rules` is deployed.

`plan.md` is the working design record: completed screens, the **"What is real vs mock"** table, the Board
API shape, and decisions marked "worth not re-litigating". Read it before changing Owner behaviour —
several things that look like bugs (two presence states, no map panel on the board, "Scheduling not built
yet") are deliberate and explained there.

## Commands

- Install deps: `flutter pub get`
- Run app: `flutter run`
- Analyze/lint: `flutter analyze`
- Run all tests: `flutter test` (51 tests, all passing)
- Run a single test file: `flutter test test/run_sheet_review_test.dart`
- Run one test by name: `flutter test --plain-name 'is independent of stop order'`
- Format: `dart format .`
- Release build (what `cloudbuild.yaml` runs): `flutter build appbundle --release` — signing is not wired
  up yet, so this produces an unsigned/debug-keyed bundle
- Regenerate environment config: `GCP_PROJECT_ID=i-destiny-428904-s2 ./tool/generate_infra_config.sh`

Lints come from `package:flutter_lints/flutter.yaml`; the analyzer excludes `build/**` and every
platform directory (`android/**`, `ios/**`, `web/**`, …).

**`BUILD.md` is the authority on builds that touch infra** — its decision table covers the four cases
(plain local build, routine config sync, environment move, Cloud Build pipeline). The short version: a
normal build needs no GCP credentials at all; only a bucket/client rotation or an environment change
needs the script.

## Tests

`test/` is three files of pure model + widget tests with **no Firebase, network or Firestore fakes** —
models are constructed directly (`RunStop(...)`, `StopItem(...)`), and widget tests pump `StopCard` /
`RoutePreviewMap` / the reorderable list and drive real gestures. Nothing exercises `RunStop.fromDoc`,
`RiderBoardApi` or any `StreamBuilder`, so **logic worth testing has to live in a model or widget the test
can construct by hand** — put aggregation and parsing there rather than inside a screen's `build`. Test
fixtures use numbers from a real "South Runsheet" export; keep it that way over inventing quantities.

## Environment config

`lib/config/infra_config.dart` is **generated — never hand-edit it.** `tool/generate_infra_config.sh`
rewrites it from *live* GCP state, not from Terraform or the backend repo's filesystem:

| Constant | Read from |
| --- | --- |
| `runSheetsBucket` | the `process-run-sheet-upload` function's own Storage trigger (name-matching buckets is unsafe — a stale `run-sheets-*` bucket exists) |
| `googleSignInServerClientId` | Firebase Auth's Google IdP config (not Terraform-managed) |
| `riderBoardUrl` | the `rider-board` function's URL; **empty when undeployed**, so callers must check rather than parse it |

If `GCP_PROJECT_ID` disagrees with the committed `lib/firebase_options.dart`, the script runs
`flutterfire configure` itself. That branch must stay local and human-committed — in CI those writes die
with the ephemeral workspace.

## Architecture

**Auth decides everything.** `main.dart` initializes Firebase and hands one long-lived `AuthState` to
`AuthGate`. `AuthState` (`lib/state/auth_state.dart`) wraps Firebase Auth + Google Sign-In and listens to
`idTokenChanges`, reading the `role` **custom claim** the backend's `beforeSignIn` blocking function sets.
`AuthGate` maps `AuthStatus` → screen; `RootShell` maps role → shell. Notes that bite:

- `AuthRole.driver` is this app's word for what the backend, Firestore rules and the API all call
  **`rider`**. Both spellings are load-bearing; don't unify them.
- Sign-in forces `getIdTokenResult(true)` — the role claim is set server-side *during* this sign-in, so a
  cached token reads back as "no role".
- `AuthStatus.needsRole` is a defensive dead-end, not an expected state.

**Two shells, two different worlds.** `RootShell` (`lib/screens/root_shell.dart`) sends drivers to
`_DriverShell` (the old 3-tab mock: Orders/Active/Earnings, driven by `AppState`) and *everyone else,
including a null role*, to `_OwnerShell` (2 tabs: Home/Maps). Owner screens are **bodies, not
`Scaffold`s** — the app bar, end drawer and bottom bar are hosted once in `_OwnerShell` and shared across
tabs via `IndexedStack`.

**Owner data flow is real Firestore + Cloud Functions, no state package.** Screens read live data
directly with `StreamBuilder`/`FutureBuilder`; there is no repository layer and no `AppState` involvement.

```
UploadRunSheetScreen   → PDF to InfraConfig.runSheetsBucket at {roundKey}/{uploadId}.pdf
RunSheetProgressScreen → streams run_sheet_upload/{uploadId}.status
RunSheetReviewScreen   → reads delivery_run/{runId}/delivery_stop (seq_order), map + drag-reorder
                         + per-product load-out totals + editable route name;
                         writes status (+ manual_order, route_name/route_name_source) back
OwnerRoutesScreen      → circuits/{roundKey}, most recently updated first → RouteMapScreen;
                         long-press a card to rename (round/round_source) or delete
OwnerMapsScreen        → RiderBoardApi → rider-board function → RiderBoardEntry cards
OwnerRiderScreen       → RiderBoardApi.fetchRiderMap → encoded polyline + position
OwnerSettingsScreen    → driver_invitations (invite / accepted roster)
```

Collections touched from the client: `circuits` (read, delete, and a rename limited to
`round`/`round_source`), `delivery_run/{id}/delivery_stop`, `run_sheet_upload`, `driver_invitations`,
`addresses` (read-only geocode cache), `stop_instructions` (owner override field only — Firestore rules
allow that one field directly, no function needed).

**The rider-board endpoint is IAM-open by necessity.** Cloud Run IAM cannot evaluate a Firebase token, so
`allUsers` opens the gate and the function's own `_require_owner()` is the actual authorization.
`RiderBoardApi` therefore sends a **freshly fetched** ID token per request (`getIdToken()` — tokens expire
hourly), times out at 60s, and converts every failure into a `RiderBoardException` whose message is
already fit to show a person.

**Map data is data, never an image.** The server returns an encoded polyline (with `shape_format` — a
precision-6 shape decoded as 5 lands ten degrees away, silently); the client owns the viewport and renders
tiles/overlay/marker itself via `flutter_map` + CARTO basemap tiles.

**Much of the board is mock, and labelled as such in the payload** (`demo_mode`, `route.source`,
`position.source`). The UI's "Mock route & position" badge is driven by those fields, so it disappears on
its own when the backend goes real. See plan.md's table before assuming a number is production data.

## Conventions and traps

- **Never upload to the default Firebase Storage bucket.** Only `InfraConfig.runSheetsBucket` has the
  Storage trigger and the owner-only write rule bound to it; the default bucket silently never processes.
- **`DepotLocator.addressKey` mirrors the backend's `firestore_paths.address_key`** (sha256 of the
  trimmed, lowercased address). The two are a contract — change one and you must change the other.
- **A re-upload is an amendment, not a redo**, and the client's copy promises that. Re-uploading a sheet
  for an existing route keeps its name, the stop order the owner dragged, and their per-stop
  instructions; the backend only pays for what changed. `process_run_sheet_upload.py` picks one of three
  `order_strategy` values — `optimized` (first upload, Routes API), `reused` (same addresses, confirmed
  order stands), `merged` (stops added/removed, confirmed order kept and new ones slotted in by
  `domain/run_order.py`) — and only the first costs a routing call. `RunSheetDiff.orderNote` is what says
  so on screen; treat an unknown strategy as `optimized`, i.e. **never** claim the order survived.
- **A route's name has the same precedence rule as a stop's instructions**: what the owner typed beats the
  name they gave it before, which beats the PDF's `Round:` heading. `circuits.round_source == 'owner'` is
  what stops next week's parsed "Run 2" reclaiming a renamed route, so a write that sets `round` without
  it silently reverts on the next upload. `circuits.pdf_round` is kept separately and is the *only* thing
  `round_mismatch` may compare against — comparing the display name flags every upload of a renamed route.
- **Leaving a screen with unapplied edits is guarded, and only then.** `UploadRunSheetScreen` and
  `RunSheetReviewScreen` wrap their `Scaffold` in `PopScope` inside a `ValueListenableBuilder` on the name
  controller — `canPop` is a constructor argument, so it is only as fresh as the last build, and typing
  does not otherwise call `setState`. The dirty test is `RouteName.isRenameOf` (plus `_reordered` on the
  review screen), **never** raw `text != original`: a dialog that fires when nothing changed is what
  teaches people to dismiss it unread. Re-issue the pop with `Navigator.pop`, not `maybePop`, or PopScope
  re-asks the question it just answered. `popUntil` in `_respond` is unaffected — `PopScope` gates
  `maybePop` only.
- **`RouteRenamer` owns the `circuits` rename write**, because two screens make it (the route list's
  dialog, and the update screen's "Save name" on back). The rules accept *exactly* `round` +
  `round_source` — adding `updated_at` or dropping the source earns a bare `permission-denied`.
- **`RouteName.maxLength` mirrors `firestore.rules`** (`size() <= 80`) the way `DepotLocator.addressKey`
  mirrors `firestore_paths.address_key`. Over-length names come back as a bare `permission-denied`, which
  reads as a sign-in failure, so they are caught client-side before the write.
- **Reordering uses `onReorderItem`, not the deprecated `onReorder`.** It already compensates for the
  lifted item, so the classic `if (newIndex > oldIndex) newIndex -= 1` fixup must **not** be repeated.
- A `RunStop` without coordinates is dropped at parse time (`RunStop.fromDoc` returns null) so no
  downstream consumer needs null checks; the review screen calls the omission out explicitly.
- `milkTotals()` must stay independent of stop order — reordering a route cannot change what's loaded on
  the van, and a test pins that.
- Product lines render through `StopItem.label` everywhere; a quantity formatted two ways is a support call.
- Debug tracing goes through `AppLog.auth` / `AppLog.owner` (`lib/util/app_log.dart`), which compiles away
  in release builds. Leave the calls in rather than adding and stripping them. Filter with
  `adb logcat | grep "BlueDot/"`.
- Fields are logged as `key=value` maps, and secrets are logged by *presence* (`hasIdToken: true`), never
  by value.

## UI

Design tokens live in `lib/theme/app_colors.dart` / `app_theme.dart`; shared primitives in `lib/widgets/`
(`PrimaryButton`, `PillBadge`, `SectionLabel`, `StatTile`, `SurfaceCard`, `StageProgressBar`, `StopCard`,
`RoutePreviewMap`, `StopInstructionsSheet`, `WeeklyBarChart`). Pull styling from the theme rather than
hardcoding colors.

`prototypeAssets/` holds the original static HTML mockups and is still the reference for the
customer/rider screens. **The Owner prototypes are not in this repo** — comments cite `owner-home.html`,
`owner-maps.html`, `owner-rider.html` and `owner-menu.html`, but those files were never committed here
(plan.md points at an external prototype directory). Treat plan.md plus the existing Dart as the spec for
Owner screens.

`RoutePreviewMap` is deliberately shared between the pre-confirm review screen and `RouteMapScreen`: the
sequence an owner approves and the one they look up later must be the same picture, depot legs included.

The `Inter` variable font is registered once in `pubspec.yaml` at several weights pointing at the same
file; select weights via `TextStyle(fontWeight: ...)`, not separate family names.

## Dead code worth knowing about

- `lib/screens/customer/*` (Home/Tracking/Receipt) and the customer half of `AppState` are **unreachable**
  — the Customer/Rider toggle was removed when the Owner shell landed.
- `lib/screens/owner/run_sheet_diff_screen.dart` is unreferenced; `RunSheetReviewScreen` replaced it.
- `AppState` (`lib/state/app_state.dart`) now serves only the driver mock tabs: a single `ChangeNotifier`
  of hardcoded sample data, instantiated in `_DriverShell` and passed down by constructor.

Don't extend these; if a task touches one, check whether the real Owner/driver path is what's actually wanted.
