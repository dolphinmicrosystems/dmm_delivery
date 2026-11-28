# Releasing Dunedin Milk & More on Google Play

How the app gets from this repo onto phones through the Play Store. Part A is
done once. After that, every new version is Part B: one command.

- App name on Play: **Dunedin Milk & More** (home screen: "Milk & More", `lib/config/app_brand.dart`)
- Package name: **`com.delivery.dmm_delivery`** (permanent, can never change)
- Backend project: `i-destiny-428904-s2` (the `dmm-delivery-app` repo, checked out next to this one)

---

## How versions work

`version:` in `pubspec.yaml` reads `MAJOR.MINOR.PATCH+BUILD`, for example
`1.4.2+27`. The app shows it as **"Version 1.4.2 (27)"** in both menus and both
Settings screens, the way most apps do. Developer builds add "· debug".

| Part | Shown to people | Goes up when | Example |
|---|---|---|---|
| MAJOR | yes | a big or breaking change | 1.4.2 → 2.0.0 |
| MINOR | yes | new features | 1.4.2 → 1.5.0 |
| PATCH | yes | fixes only | 1.4.2 → 1.4.3 |
| BUILD | in brackets | **every upload**, always | (27) → (28) |

The build number is Play's `versionCode`. Play rejects any upload whose number
it has seen before, so it only ever goes up. `tool/release.sh` sets both parts,
so don't edit them by hand.

## Testing tracks

| `--track` | Play Console name | Who gets it | Review |
|---|---|---|---|
| `internal` (default) | Internal testing | up to 100 people you list | almost none, minutes |
| `closed` | Closed testing (the **beta**) | people or Google Groups you list | usually hours to a few days |
| `open` | Open testing | anyone who finds the beta on Play | as closed |
| `production` | Production | everyone | as closed |

Testers only see a testing track after opening its **opt-in link** once and
accepting. The app never shows in public search until it's in production.

A **personal** developer account (created after Nov 2023) must run a closed
test with **at least 12 testers for 14 days in a row** before Play allows
production. Run the driver beta on `closed` and it counts.

---

## Part A - one-time setup

### A1. Tools on this machine

- Flutter (already used for this repo), Java's `keytool` (comes with Android Studio/JDK), `python3`, `gcloud`.
- `dart_defines.json` filled in (see `BUILD.md`).
- Your gcloud login for scripts (Terraform uses the same one):
  ```
  gcloud auth application-default login
  ```

### A2. Create the upload key

Play needs every bundle signed with **your** key. Run this and choose a strong password:

```
mkdir -p ~/keys
keytool -genkey -v -keystore ~/keys/bluedot-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties`, which is gitignored and never committed:

```
storeFile=/home/<you>/keys/bluedot-upload.jks
storePassword=<your password>
keyAlias=upload
keyPassword=<your password>
```

**Back up `bluedot-upload.jks` and the password** (password manager or an
encrypted drive). Losing them means a slow key reset through Google support.

### A3. Create the app in Play Console

1. play.google.com/console → **Create app**.
2. App name `Dunedin Milk & More`, default language English, **App**, **Free**, accept the declarations.
   If asked for a package name, it's `com.delivery.dmm_delivery`.

### A4. Fill in "Set up your app" (Dashboard)

Play won't let testers install until these are done:

- **Privacy policy**: a public URL, required because the app uses location, the camera and
  Google sign-in. A page on the business website is fine.
- **App access**: sign-in is by invitation only, so reviewers need a way in. Invite a spare
  Gmail as a driver from the owner's Drivers tab, then enter that login here with a note:
  "Invite-only business app for a milk delivery company. Sign in with Google using the
  account below and choose Driver."
- **Ads**: No ads.
- **Content rating**: fill in the questionnaire (a business utility, no user-generated content).
- **Target audience**: 18 and over.
- **Data safety**: the app collects precise location, photos, name and email address,
  customers' names, addresses and phone numbers (from run sheets), and crash logs. All
  encrypted in transit, none sold or shared for advertising, used only to run deliveries.
- **Location permission** (if Play asks): foreground only, used while a driver is driving a
  run, to show the van on the map and confirm arrivals.

### A5. Build the first version

The very first bundle has to go through Play Console by hand (a Google rule):

```
tool/release.sh build --no-upload
```

That raises the build number, checks and builds:
`build/app/outputs/bundle/release/app-release.aab`.

### A6. Upload it to Internal testing

1. Play Console → **Test and release → Testing → Internal testing → Create new release**.
2. Accept **Play App Signing** when offered (Google keeps the app's final signing key).
3. Upload `app-release.aab`, give release notes, **Next → Save and publish** (or **Roll out**).
4. **Testers** tab → create an email list (you and the owner) → Save. Copy the
   **opt-in link** and open it on your phone.

### A7. Register Play's signing key (sign-in and maps need this)

Play re-signs the app with its own key, so Google sign-in and the Detailed and
Satellite maps fail on a Play install until that key is registered. You'll see
a sign-in error. The Simple map style still works.

1. Play Console → **Test and release → App integrity → App signing**. Copy the **SHA-1** of the
   **App signing key certificate** and of the **Upload key certificate**.
   Double-check the app signing one against a real Play build: **App bundle explorer** → the
   version → **Downloads** → **Signed, universal APK**, then
   `apksigner verify --print-certs universal.apk`. A wrong one shows on phones as
   "canceled: [16] Account reauth failed".
2. In the backend repo (`dmm-delivery-app/infrastructure/terraform`), write each SHA-1 in
   lowercase with no colons:
   - `firebase_apps.tf`: add both to `sha1_hashes` (Google sign-in).
   - `maps.tf`: add an `allowed_applications` block with the **app signing** SHA-1
     (Map Tiles and Routes).
3. In this repo's `dart_defines.json`, add the **app signing** SHA-1 (uppercase, no colons),
   so the app identifies itself to Google Maps as the Play build:
   ```
   "GOOGLE_MAP_TILES_ANDROID_CERT": "AB12...EF"
   ```
   Debug builds then send it too, which is fine: the Maps key allows both the debug and the
   Play certificate.

### A8. Deploy the backend

From `dmm-delivery-app`:

```
./tool/deploy_backend.sh
```

This registers the SHA-1s and creates the **`play-publisher`** service account
that releases upload as (`infrastructure/terraform/play_publisher.tf`). Who may
use it is `release_managers` in the gitignored `terraform.tfvars`, for example
`["user:you@gmail.com"]`. Nobody holds a key file for it: the release script
borrows it through your own gcloud login.

### A9. Let the publisher account release

Play Console → **Users and permissions → Invite new users**:

- Email: `play-publisher@i-destiny-428904-s2.iam.gserviceaccount.com`
- **App permissions** → add Blue Dot → tick **Release to testing tracks**
  (add **Release to production** later, when going public).
- **Invite user**. A service account needs no acceptance.

### A10. Second release, fully automatic

```
tool/release.sh build --notes "Google sign-in for Play installs"
```

This is the first release through the API, and it's built with the A7 settings.
Install it from Play on a phone, then check sign-in and a Detailed map.

---

## Part B - every new version

```
tool/release.sh patch --notes "Fixes the run summary"
tool/release.sh minor --notes "Business logo in the app bar"
tool/release.sh minor --track closed --notes "..."   # straight to beta testers
```

What it does, in order (it stops at the first failure, uploads nothing and puts
the old version back):

1. bumps `version:` in `pubspec.yaml`;
2. `flutter analyze` and `flutter test`;
3. `flutter build appbundle --release` with `dart_defines.json`, signed with the upload key;
4. uploads to the chosen track with "What's new" from `--notes` (`tool/play_upload.sh`);
5. commits `pubspec.yaml` as "Release 1.4.3 (28)" and tags `v1.4.3+28`. Push it with
   `git push && git push --tags`.

Options: `--no-upload` (build only), `--no-git` (no commit or tag),
`--track internal|closed|open|production`.

**Testers and users don't need to do anything to update.** The app checks Google Play when it opens. If
there's a newer version on their track, Play asks "Update available?", downloads it in the background,
and the app then shows "A new version is ready" with **Restart** (`lib/services/app_updater.dart`).
Play can take a few hours after a release is approved before it offers it.

**Moving a tested version up** (internal → closed → production): in Play Console,
open the track with the release → **Promote release**. This needs no new build.

**If the backend changed too**, deploy it (`dmm-delivery-app/tool/deploy_backend.sh`)
**before** releasing an app that depends on it. Rules and fields the new app writes
must be live first.

---

## When something goes wrong

| What you see | Why | Fix |
|---|---|---|
| `android/key.properties is missing` | No upload key set up | A2 |
| `No key with alias 'upload' found` | The key was made without `-alias upload` (keytool then calls it `mykey`) | Set `keyAlias=mykey` in `key.properties` |
| `Gradle build daemon disappeared unexpectedly` | Out of memory: Linux stopped the build | Close the emulator and browser tabs and retry; Gradle's memory is in `android/gradle.properties` |
| Play: "signed in debug mode" | Built without `key.properties` | A2, then release again |
| Play: "Version code N has already been used" | That build number was uploaded before | `tool/release.sh build` (raises only the build number) |
| "Only releases with status draft may be created on draft app" | The app has never been published | The script saves it as a draft; roll it out in Play Console once (A6) |
| `Play refused to open an edit (403)` | Publisher account not invited, or no permission for this app | A9 |
| `Permission 'iam.serviceAccounts.getAccessToken' denied` | Your account isn't in `release_managers`, or the backend isn't deployed | A8 |
| `Reauthentication is needed` / `default credentials` errors | gcloud login missing or expired | `gcloud auth application-default login` |
| Sign-in fails on the Play install, works on debug builds | Play's signing SHA-1 isn't registered | A7, A8 |
| Detailed/Satellite map blank or falls back to Simple on Play | Same, for the Maps key and `GOOGLE_MAP_TILES_ANDROID_CERT` | A7, A8 |

## Files involved

- `tool/release.sh`: bump, check, build, upload, tag.
- `tool/play_upload.sh` / `tool/play_upload.py`: the upload (Google Play Developer API). Creates
  `tool/.venv-release/` on first use.
- `android/app/build.gradle.kts`: signs release builds with `android/key.properties`
  (falls back to the debug key without it, which Play refuses).
- `lib/util/app_version.dart`: the "Version 1.4.2 (27)" label.
- `tool/make_launcher_icons.py`: draws the app icon (the navigation map's truck on brand blue) into
  `android/app/src/main/res/mipmap-*` and the Play Console icon `docs/store/play-icon-512.png`.
- Backend: `infrastructure/terraform/play_publisher.tf` (publisher account),
  `firebase_apps.tf` and `maps.tf` (signing SHA-1s).
