# Blue Dot — Owner plan

Working notes for the Owner (RBAC `role: owner`) side of the app. Rider is
out of scope for now beyond what already exists.

Screens are ports of the prototypes in `/Users/dolphin/Downloads/bluedot-prototype`
(`owner-home.html`, `owner-maps.html`, `owner-menu.html`, `owner-rider.html`).

## Shipped

**Owner home** (`owner-home.html`) — greeting plus three quick actions, no
data list. Bottom bar is Home / Maps; the header carries the Blue Dot mark
and a right-hand hamburger opening the menu drawer (`owner-menu.html`:
Settings, About).

| Quick action | State |
| --- | --- |
| Calendar · Delivery roster | Deferred — card disabled, reads "Coming soon" |
| Invites · Invite riders | Live, with a real pending-invite count; email + Google sign-in interim (see below) |
| Bulk import · Upload sheet | Live → `OwnerRoutesScreen` → `UploadRunSheetScreen` |

**Owner maps** (`owner-maps.html`) — the invited-driver board. One card per
driver: name, presence, the next drop's company and address in grey, and its
ETA in bold on the right. The prototype's map panel is deliberately dropped:
the list is the whole canvas between header and nav bar, because a fixed map
would consume the top third of the screen showing pins the owner cannot act
on. Per-route geography already has a full-screen map in `RouteMapScreen`.

**Presence** is two states, not the prototype's three. "On route" is real and
observable; "Picking up" and "Idle" were placeholder flavour. Everything that
isn't actively running a route reads as **Offline**, whose ETA renders as an
em dash — "0 min" would read as "arriving now".

## Rider board data shape

The board is fed one **summary document per driver**, not the driver's stop
list and not a flat list of all drops:

```
rider_board/{riderUid}
  driver_name   : string
  presence      : "on_route" | "offline"
  eta_minutes   : int | null      # to the next drop
  drops_left    : int
  next_stop     : { customer_name, address }
  updated_at    : timestamp
```

Why per-driver rather than a flat `List<driver, seq, eta, drops>`:

1. **`driver_name` is a label, not an identity.** Grouping cards on a display
   string breaks on duplicates and renames, and `firestore.rules` cannot gate
   on it. The rules already join on `rider_id == request.auth.uid`.
2. **Fan-out.** The board draws one card per driver, so one document per
   driver means a driver moving repaints one card. A flat list pushes every
   drop of every driver to every owner device on every stop update.
3. **ETA and drops-left are server-derived** — they can't be computed on the
   client without the full stop list plus traffic, which is the payload being
   avoided.

The ordered detail stays where it already lives:
`delivery_run/{runId}/delivery_stop/{stopId}` ordered by `seq_order`, read
only when drilling into a single rider (`owner-rider.html`, not yet built).

### Not yet deployed

No Cloud Function writes `rider_board`, and `firestore.rules` has no match
block for it. Until both exist the board is built from
`driver_invitations` (accepted) and every driver reads as offline with no
ETA. `RiderBoardEntry.fromBoardDoc` is the swap-in point.

Rules needed, mirroring the read-only pattern the other owner-facing
collections use:

```
match /rider_board/{riderUid} {
  allow read: if isOwner() || (isSignedIn() && riderUid == request.auth.uid);
  allow write: if false;   // Cloud Function (Admin SDK) only
}
```

## Deferred

**Delivery roster / calendar** — the first home quick action. No schedule
data exists. Card is visibly disabled rather than hidden, so the screen
doesn't look finished.

**Rider invitations by phone + OTP** — the prototype's intended flow. Today
`showInviteDriverDialog` takes a Gmail address and writes
`driver_invitations/{lowercased-email}`; acceptance is a Google sign-in, with
`before_sign_in_fn.py` setting `accepted_at` and the `role` claim. Moving to
phone + OTP changes the document key (email → E.164 number), the identity
provider (Google → Firebase phone auth), and the `isValidInvite()` rule that
currently asserts `driver_email == email`. To be specified.

**Owner rider detail** (`owner-rider.html`) — the drill-down from a board
card. Needs the per-run stop list, so it depends on `rider_board` carrying a
`current_run_id`.

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
