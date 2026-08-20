# Build & environment-config guide

This covers the four ways this app actually gets built, and specifically how
`lib/config/infra_config.dart` and `lib/firebase_options.dart` (the two
files that point this app at a real GCP/Firebase project) get kept in sync.
For everyday Flutter commands (`flutter test`, `dart format`, architecture)
see `CLAUDE.md`. This file is about *which environment* a build talks to and
*how that gets there*.

## Decision table

| I want to... | Use |
|---|---|
| Build/run against whatever's already committed, no infra changed | [1. Local, no script](#1-local-build---no-script) |
| Refresh config after a bucket/key rotation, *same* GCP project | [2. Local, routine sync](#2-local-build---routine-sync-same-project) |
| Point this checkout at a *different* GCP project (QA, a new deploy) | [3. Local, environment move](#3-local-build---environment-move) |
| Run this in CI (Cloud Build) | [4. Pipeline](#4-pipeline-cloud-build) |

## Prerequisites

- Flutter SDK (`flutter --version` should work)
- For cases 2-4: [`gcloud`](https://cloud.google.com/sdk/docs/install), authenticated (`gcloud auth login`) as an account with at least read access on the target GCP project
- For case 3 only: FlutterFire CLI + Firebase CLI:
  ```
  npm install -g firebase-tools
  firebase login
  dart pub global activate flutterfire_cli
  ```
  (`tool/generate_infra_config.sh` checks for `flutterfire` and fails with
  this exact instruction if it's missing, rather than failing confusingly
  later.)

---

## 1. Local build - no script

The common case: you're working on the app, nothing about GCP/Firebase
infra changed, and `lib/config/infra_config.dart` /
`lib/firebase_options.dart` as currently committed are already correct.

```
flutter pub get
flutter run
```

No GCP credentials needed, no network calls to Google Cloud, fully
offline-capable. This is deliberately *not* wired into any build hook (see
`CLAUDE.md`/prior design discussion for why) - it's the fast iteration loop
and should stay that way.

---

## 2. Local build - routine sync (same project)

Something in the *same* GCP project changed - the run-sheets bucket was
recreated, the Google sign-in client got rotated - and you want
`infra_config.dart` to reflect it, without switching environments.

```
GCP_PROJECT_ID=i-destiny-428904-s2 ./tool/generate_infra_config.sh
```

What it does: reads the target project (mandatory - the script refuses to
run without it), confirms it matches what's already committed in
`lib/firebase_options.dart`, then regenerates `lib/config/infra_config.dart`
from two live sources - never from the backend repo's filesystem or from
Terraform state:

- `runSheetsBucket` - read off the `process-run-sheet-upload` Cloud
  Function's own Storage trigger config (the authoritative source; a
  name-based bucket search is not safe - this project has a stale
  `run-sheets-*` bucket left over from a prior deploy).
- `googleSignInServerClientId` - read from Firebase Auth's Google IdP config
  directly (this value isn't Terraform-managed at all).

Then:

```
flutter run
```

Commit the result if `infra_config.dart` actually changed:

```
git add lib/config/infra_config.dart
git commit -m "Refresh infra_config.dart"
```

---

## 3. Local build - environment move

You're pointing this checkout at a **different** GCP project entirely (a
new QA environment, a redeploy elsewhere). Run the same script with the
*new* project id:

```
GCP_PROJECT_ID=new-qa-project-id ./tool/generate_infra_config.sh
```

Because `new-qa-project-id` won't match what's currently committed in
`lib/firebase_options.dart`, the script:

1. Prints that it detected the mismatch.
2. Runs `flutterfire configure --project=new-qa-project-id --platforms=android,ios,web --yes` itself - this registers the app with the new Firebase project if needed, and rewrites `lib/firebase_options.dart`, `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist`.
3. Continues into the same live-state discovery as case 2, now against the new project.
4. Prints `git status` for all four files at the end so the final step - review and commit - is impossible to miss.

```
git status --short lib/config/infra_config.dart lib/firebase_options.dart \
  android/app/google-services.json ios/Runner/GoogleService-Info.plist
git add lib/config/infra_config.dart lib/firebase_options.dart \
  android/app/google-services.json ios/Runner/GoogleService-Info.plist
git commit -m "Point app at new-qa-project-id"
```

**This step is local and human-run on purpose.** `flutterfire configure`
only writes files to whatever working directory it runs in - if this ran
inside CI's ephemeral checkout instead, those writes would be deleted with
the workspace at the end of the build and never reach the actual git
repository. See [4. Pipeline](#4-pipeline-cloud-build) for what that means
in practice.

---

## 4. Pipeline (Cloud Build)

Defined in `cloudbuild.yaml`, manually triggered (deliberately not on every
push - an environment-affecting step warrants a human explicitly choosing
the target each time).

**One-time setup**, registering the trigger:

```
gcloud builds triggers create manual \
  --name=sync-and-build \
  --repo=<your-repo-url> --branch-pattern="^main$" \
  --build-config=cloudbuild.yaml
```

**Running it:**

```
gcloud builds triggers run sync-and-build --branch=main \
  --substitutions=_GCP_PROJECT_ID=i-destiny-428904-s2
```

(or "Run trigger" in the Cloud Build console, filling in `_GCP_PROJECT_ID`)

What it does, step by step:

1. `require-target-project` - fails immediately if `_GCP_PROJECT_ID` is blank.
2. `sync-infra-config` - runs `tool/generate_infra_config.sh` inside a `gcloud`-only container (no `flutterfire`/`firebase` CLI installed there). This means:
   - If `_GCP_PROJECT_ID` **matches** the committed `firebase_options.dart` → proceeds normally, regenerates `infra_config.dart` from live state, build continues.
   - If it **doesn't match** → the script tries to self-heal via `flutterfire configure`, hits the "not installed" check, and **fails the build**.
3. `flutter-analyze` - `flutter analyze`.
4. `flutter-build` - `flutter build appbundle --release`.

**Important scope limit:** this pipeline is a verify-and-build pipeline for
an *already-configured* environment, not an environment-mover. It cannot
perform an environment move itself (case 3) - if `_GCP_PROJECT_ID` disagrees
with what's committed, the correct response is "go run case 3 locally,
commit the result, then re-run this pipeline," not "let the pipeline fix
it," because anything the pipeline's `flutterfire configure` wrote would be
discarded with the ephemeral build workspace and never reach git - the next
build would hit the identical mismatch again, having fixed nothing durably.

**Prerequisite for cross-project pipelines:** if this trigger's own GCP
project differs from `_GCP_PROJECT_ID`'s project, the trigger's service
account (`<project-number>@cloudbuild.gserviceaccount.com`) needs
`roles/cloudfunctions.viewer` and Identity Toolkit admin read access
(e.g. `roles/firebaseauth.viewer`) granted **on the target project**.

**Not yet wired up:** release signing (Android keystore, iOS
certs/provisioning) - the `flutter-build` step is a placeholder pending
that setup.

**Cost:** Cloud Build gives 2,500 free build-minutes/month per billing
account, then $0.006/minute beyond that. A manually-triggered, occasional
pipeline like this should comfortably stay within the free tier. See
[cloud.google.com/build/pricing](https://cloud.google.com/build/pricing).
