# Blue Dot — plan

Working notes for both roles. Screens are ports of the prototypes in
`/Users/dolphin/Downloads/bluedot-prototype`.

Roles come from the `role` custom claim set server-side by
`before_sign_in_fn.py`: `owner` and `rider` (the app calls the latter
*driver*). `RootShell` picks the shell from that claim.

---

# Owner

RBAC `role: owner`. This is where the work has been.

## Completed screens

| Screen | File | Prototype | State |
| --- | --- | --- | --- |
| Home | `owner_home_screen.dart` | `owner-home.html` | Greeting + three quick actions |
| Routes | `owner_routes_screen.dart` | — | The old home list, one tap in behind "Upload sheet" |
| Maps board | `owner_maps_screen.dart` | `owner-maps.html` | One card per driver, pull-to-refresh |
| Rider detail | `owner_rider_screen.dart` | `owner-rider.html` | Route polyline + pulsing position marker |
| Menu drawer | `owner_menu_drawer.dart` | `owner-menu.html` | Right-hand drawer: Settings, About |
| Settings | `owner_settings_screen.dart` | — | Account card → profile, driver roster (invite/rename/resend/remove), invitation validity, sign out |
| Profile | `owner_profile_screen.dart` | — | Name, age, gender, phone — placeholder data, nothing reads it |
| Upload → review | `upload_run_sheet_screen.dart`, `run_sheet_progress_screen.dart`, `run_sheet_diff_screen.dart` | — | PDF upload, parse progress, diff confirm |
| Route map | `route_map_screen.dart` | — | Per-route stop sequence on a full-screen map |

Navigation: bottom bar is **Home / Maps**; the header carries the Blue Dot
mark and a right-hand hamburger. Both tabs are bodies inside one `Scaffold` in
`RootShell`, so header, drawer and bottom bar are hosted once and each tab
keeps its scroll position.

**Home quick actions**

| Action | State |
| --- | --- |
| Calendar · Delivery roster | Deferred — card disabled, reads "Coming soon" |
| Invites · Invite riders | Live; counts pending and expired separately |
| Run sheets · Update routes | Live → `OwnerRoutesScreen` → `UploadRunSheetScreen` |

**Design decisions worth not re-litigating**

- **"Update", not "Upload sheet".** The old label named the file and left the outcome to be guessed at,
  and owners read "upload" as "replace" — which is exactly what a re-upload must not do. The card action,
  the home quick action and the upload screen all now describe the outcome: this route, brought up to
  date, keeping what you have already decided about it.
- **A route is named by a person, not by a filing code.** The PDF's `Round: Run 2` gives the default,
  because something has to, but "Run 2" is a code and not a name. It is editable in three places —
  on upload, on the review screen next to the drag-reorder, and by long-pressing a card in the route
  list — and `round_source: 'owner'` is what keeps next week's sheet from taking the name back. The
  review screen is the important one of the three: naming a route and sequencing it are the same
  decision, so they are made on the same screen.
- **A re-upload keeps the owner's stop order even when the stop set changes.** It used to keep it only
  when the addresses were identical; one new customer re-optimized the whole run and silently discarded
  a sequence someone had dragged into place. Now the confirmed order is kept for every surviving stop
  and new ones are slotted in by cheapest insertion, with no routing call. The review screen states
  which of the three strategies ran, because a sequence that quietly reverted to the optimizer's looks
  identical to one that didn't until a driver is halfway through the run.

- The routes list moved *behind* "Upload sheet" rather than being deleted:
  choosing which route a PDF belongs to is the first step of an upload, and
  removing the list would have taken `RouteMapScreen` and route-delete with it.
- The Maps board drops the prototype's map panel. The list is the whole canvas
  — a fixed map would eat the top third of the screen showing pins the owner
  cannot act on, and per-route geography already has `RouteMapScreen`.
- **Presence is two states, not the prototype's three.** "On route" is real and
  observable; "Picking up" and "Idle" were placeholder flavour. Anything not
  actively running a route reads as **Offline**, whose ETA renders as an em
  dash — "0 min" would read as "arriving now".
- Nothing invents numbers the backend cannot supply. The roster card says
  "Scheduling not built yet" rather than the prototype's "12 riders scheduled
  this week". A made-up figure on a real screen is indistinguishable from a
  broken one.

## What is real vs mock

The single most useful thing in this document. **Real** means it came from the
customer's actual data:

| Real | Source |
| --- | --- |
| Customer names, addresses, phones, emails, `seq_order` | Parsed from the actual run sheet PDFs in the run_sheets bucket |
| Stop coordinates | Firestore `addresses` geocode cache, written by the Phase 1 pipeline — no Maps API calls to read them |
| Auth, role claims, driver invitations | Firebase Auth + `driver_invitations`, real end to end |
| `circuits`, `delivery_run`, `run_sheet_upload` | Real pipeline documents |

**Mock**, all of it labelled in the API response so nothing downstream can
mistake it for production data:

| Mock | Where | Marker |
| --- | --- | --- |
| 6 drivers (Pawan Arora, Tama R., Mele F., Ari H., Nikau P., Sina T.) | `demo_board_enrichment.py` | `demo_mode: true` |
| Driver → stop assignment (contiguous chunks) | same | same |
| `presence` (on_route / offline, ~65% live) | same | same |
| `eta_minutes` (3–25 min, re-rolled per request) | same | same |
| Route shape | `dunedin_mock_route.json` | `route.source: "static-mock"` |
| Rider position on the route | `rider_map.py` | `position.source: "randomised-mock"` |
| Driver name when demo mode is off | `build_rider_board.py` | hardcoded `"Pawan Arora"` |

The rider detail screen shows a **"Mock route & position"** badge driven by
those `source` fields, not by a hardcoded flag — it disappears by itself once
the backend sends real routes and positions.

Turn all of it off with `board_demo_drivers = 0` in `terraform.tfvars`. The
board then describes only what the bucket actually contains: one driver,
real stops, no presence, no ETA.

Notes on the mock choices, so they aren't misread as bugs:

- The route uses **real geocoded coordinates** walked in naive
  nearest-neighbour order. It is **not** computed by Valhalla, which is why
  it cuts across blocks in places.
- Drivers get **contiguous** chunks of the run, not round-robin, so each works
  a zone and their `next_stop` address is coherent.
- The roster (who, presence, which stops) is **seeded from the bucket
  contents**, so pull-to-refresh doesn't reshuffle everyone — that would read
  as a bug. Only the ETA re-rolls, because that is the value which genuinely
  changes minute to minute.
- Marker progress is clamped to 0.08–0.92 so it never parks exactly on an end
  pin, which reads as "stopped" rather than "in transit".

## Board API

Two read-only endpoints on the `rider-board` gen2 function, called directly
from the app with the owner's Firebase ID token:

```
GET /              board — every stop in the bucket, grouped by driver
GET /rider/<key>   one rider's route shape and position
```

`allUsers` opens the Cloud Run IAM gate only — IAM cannot evaluate a Firebase
token, so the choice is every request or none. Authorization lives inside the
function: `_require_owner()` rejects anything without a valid ID token
carrying `role: owner` **before a single object is read**. That check is the
only thing between the internet and the bucket's customer PII. Verified
against the deployed endpoint: no token and a garbage token both return 401.

The client fetches a fresh token per request via `getIdToken()`. Firebase ID
tokens expire after an hour; a token cached at sign-in starts returning 401s
mid-session.

**Board shape** — one summary object per driver, not the driver's stop list
and not a flat list of all drops:

```
{ rider_key, driver_name, presence, eta_minutes, drops_left,
  next_stop: { customer_name, address }, stops: [...] }
```

Why per-driver rather than a flat `List<driver, seq, eta, drops>`:

1. **`driver_name` is a label, not an identity.** Grouping on a display string
   breaks on duplicates and renames, and `firestore.rules` cannot gate on it —
   the rules already join on `rider_id == request.auth.uid`.
2. **Fan-out.** One card per driver means one document per driver repaints one
   card. A flat list pushes every drop of every driver to every owner device on
   every stop update.
3. **ETA and drops-left are server-derived** — not computable client-side
   without the full stop list plus traffic, which is the payload being avoided.

**Map data is data, never an image.** The endpoint returns an encoded polyline
and a position; the client renders tiles, overlay and marker, because it owns
the viewport — a server-rendered map is wrong the moment the owner pans. This
is the split production tracking uses. `shape_format` travels with the payload
rather than being assumed: decoding a precision-6 shape as 5 doesn't fail, it
silently lands the route ten degrees away.

An earlier draft cached a Google Static Maps image in a bucket. Dropped, along
with the Static Maps API enablement, the API-key restriction widening and the
cache bucket it needed.

## Owner — next

**Driver location (next up).** Replace `randomised-mock` with real positions:
GPS pings from the driver app, map-matched server-side, with routing from
Valhalla plus the Maps API. "Live" then means *this driver's GPS is
reporting*, which is what the presence dot should have meant all along.

**Push to DB with owner → driver tenancy.** The current bucket-pull is
scaffolding. Stops belong in the database scoped to an owner's driver list,
not re-parsed from PDFs on every request.

**Firestore instead of HTTP polling.** Once the backend writes
`rider_board/{riderUid}`, the board becomes a snapshot listener with live
updates and pull-to-refresh stops mattering. The response shape already
matches, so it's a transport swap, not a rewrite. Needs a rules block:

```
match /rider_board/{riderUid} {
  allow read: if isOwner() || (isSignedIn() && riderUid == request.auth.uid);
  allow write: if false;   // Cloud Function (Admin SDK) only
}
```

**Delivery roster / calendar** — the disabled home quick action. No schedule
data exists yet.

## Driver invitations — decided, worth not re-litigating

**There is no invitation link, and adding one would not help.** The
`driver_invitations/{lowercased-email}` document is the credential:
`before_sign_in_fn.py` authorises the invited address on its next Google
sign-in whether or not the email ever arrived. So an owner can invite someone
and tell them in person and acceptance works identically, the email is a
courtesy rather than a gate, and there is no second secret to mint, expire or
leak. Expiry is `expires_at` on that document, compared against the clock by
`handle_sign_in.py` — that *is* the whole mechanism, and "resend" means
"renew".

**Three states, not two.** `pending` / `expired` / `accepted`. The roster used
to be two queries partitioning on `accepted_at`, which reported an invitation
past its deadline as still waiting — hiding the only row that needed the owner
to do anything. Firestore cannot express "expired" as a query that stays true
as time passes, so `AuthState.invitations()` streams the collection whole and
`DriverInvitation` derives the state from an injected `now`. One row per
driver; reading it whole costs nothing worth optimising.

**Validity is configurable, in `app_settings/invitations`.** One document
rather than per-owner, because two owners disagreeing would make the date
quoted in the email a coin toss. It applies to invitations sent after it and
to nothing already out there — `expires_at` is stamped at write time, so
shortening the window cannot retroactively expire an invitation someone is
holding. The email quotes the document's own `expires_at` rather than
recomputing a TTL, so the date a driver is told is the date that gets enforced.

**Removing a driver withdraws the invitation; it does not revoke access.**
`resolve_role_for_sign_in` returns early for an account that already holds a
role and never re-reads this collection, so an accepted driver keeps
`role: rider` on their next token refresh. Revoking one needs a server-side
claim change — not built. The confirm dialog says so rather than implying
otherwise.

**Redis was considered and rejected.** Expiry is one timestamp comparison
against a document already being read at sign-in, a handful of times a day. A
cache would add a server to run, an invalidation path, and a second place the
truth lives.

**Rider invitations by phone + OTP** remains the eventual target. Moving there
changes the document key (email → E.164), the identity provider (Google →
Firebase phone auth), and the `isInvite()` rule that currently asserts
`driver_email == email`. To be specified.

## Leaving a screen mid-edit

Back from the update screen or the review screen asks before throwing work away — but **only when there
is work to throw away**. The name is compared with `RouteName.isRenameOf`, so re-spacing it or typing it
back character for character is not a change and raises nothing; the review screen adds "did you drag a
stop".

The two dialogs differ on purpose:

- **Update screen** offers *Save name* alongside Discard. The circuit already exists and renaming it needs
  no PDF, so an owner who opened the screen only to fix a name can finish there instead of backing out,
  losing it, and retyping it in the route list. A brand-new route has no `circuits/{roundKey}` to write
  to yet, so it gets Discard only.
- **Review screen** offers no third path. Confirm and Discard are already on screen and are the only two
  states a pending upload can resolve to; a "save" here would half-apply one of them.

## Route naming and re-upload cost

Spans both repos. The name lives on `circuits/{roundKey}` as `round` + `round_source`, with the sheet's
own heading kept alongside as `pdf_round`:

| Field | Written by | Meaning |
| --- | --- | --- |
| `round` | confirm-run-sheet, or an owner rename from the route list | Display name |
| `round_source` | same | `owner` once a person has chosen it; `file` while it follows the sheet |
| `pdf_round` | confirm-run-sheet | The heading this circuit was built from — the *only* thing `round_mismatch` compares |

Precedence when a sheet is processed (`_resolve_route_name`): what the owner typed on this upload → the
name they gave it before → the PDF's heading. Identical in shape to the per-stop instructions rule one
layer down, deliberately.

Ordering strategy, reported to the client as `diff.order_strategy`:

| Strategy | When | Routing call |
| --- | --- | --- |
| `optimized` | No previous run for this circuit | Yes — Routes API |
| `reused` | Same set of addresses | No |
| `merged` | Stops added or removed | No — `domain/run_order.py` cheapest insertion |

Geocoding was already free for unchanged stops (`CachedGoogleGeocoder` reads the `addresses` collection
first), and owner instruction overrides already survived every upload. The merge case was the one thing
that didn't.

## Known gaps in the upload flow

Found while tracing a stalled upload (`run_sheet_upload` stuck at
`ready_for_review`, so `circuits` stayed empty and the route never appeared):

- `RunSheetProgressScreen` ignores `snapshot.hasError` and renders a spinner
  for null data — a rules rejection is indistinguishable from "still
  processing", forever.
- `RunSheetDiffScreen._respond` has no try/catch; a rejected status write
  leaves a dead button with no feedback.
- An upload left unconfirmed is unreachable: home lists only `circuits`, and
  `circuits/{roundKey}` is written by `confirm-run-sheet` on confirm, so a
  pending review has no route back to it.

---

# Rider

RBAC `role: rider`. **Not started.** Everything below is either inherited
prototype mock or backend groundwork that has no driver-facing UI yet.

## Current state

`RootShell._DriverShell` still renders the **original prototype's three mock
tabs** — Orders, Active, Earnings (`rider_orders_screen.dart`,
`rider_active_screen.dart`, `rider_earnings_screen.dart`). They are driven
entirely by hardcoded fields in `AppState`, touch no backend, and are
unchanged from before the Owner rework. A driver signing in today lands on
fabricated jobs and earnings.

What *does* work for a driver: invitation, Google sign-in, and the `role:
rider` claim. `before_sign_in_fn.py` gates acceptance on a valid, unexpired
invitation and stamps `accepted_at`.

Backend groundwork with no rider UI attached:

- `firestore.rules` already scopes a rider to their own run —
  `delivery_run` read requires `rider_id == request.auth.uid`, and
  `delivery_stop` update is limited to `status`, `delivered_at`,
  `pod_photo_url`, `rider_note`.
- A `pod_photos` bucket exists for proof-of-delivery.
- `check-deviation` and `send-invitation-email` functions are deployed.

## Rider — next

- **Replace the three mock tabs** with the driver-facing circuit view
  (DMM-11+): the assigned run, stops in `seq_order`, next drop first.
- **Mark delivered** — the one write riders are allowed, already permitted by
  the rules: status, timestamp, POD photo, note.
- **GPS reporting** — the other half of the owner's live board. This is the
  piece that makes "On route" mean something.
- **Assignment.** Nothing sets `delivery_run.rider_id` today; it is null on
  every document, which is precisely why the owner board has to fabricate
  driver → stop assignment.

---

# Cross-cutting

- **Tiles** come from CartoDB's free basemaps (inherited from
  `RouteMapScreen`). Fine for development; needs a paid or self-hosted tile
  source before real owners use this.
- **No widget tests.** `test/widget_test.dart` covered the deleted Customer
  role and could no longer boot once `MyApp` required Firebase
  initialisation. Model and decoder logic is unit-tested; widget-level
  coverage of the current screens needs a Firebase fake.
- **`get_addresses_credentials.json` is committed** in the backend repo — a
  live service-account private key. Wants rotating and purging from history.
- **`SignInScreen` carries a regression guard** at the top of the file. It is
  pushed on top of `AuthGate`, so it must dismiss itself; read the header
  before changing it.
