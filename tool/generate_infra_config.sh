#!/usr/bin/env bash
# Regenerates lib/config/infra_config.dart from live GCP/Firebase state -
# never from the dmm-delivery-app (backend/Terraform) repo's filesystem.
# That repo can be deployed standalone to any GCP project and isn't
# guaranteed to be checked out anywhere near wherever this runs (a
# developer's machine, this app's own CI); the only thing both sides
# actually share is the deployed GCP project itself, so that's the only
# thing this script reads.
#
#   - runSheetsBucket            <- read straight off the
#                                    process-run-sheet-upload Cloud
#                                    Function's own Storage trigger config.
#                                    This is the authoritative source: it's
#                                    the actual bucket processing is wired
#                                    to, not just a name/label guess. (A
#                                    plain `gcloud storage buckets list`
#                                    filtered by name is NOT safe here - as
#                                    of writing this project has a second,
#                                    stale run-sheets-* bucket left over
#                                    from a prior deploy, so name-matching
#                                    alone can silently pick the wrong one.)
#   - googleSignInServerClientId <- Firebase Auth's Google IdP config
#                                    (not Terraform-managed - auto-created
#                                    when the Google sign-in provider was
#                                    enabled)
#
# GCP_PROJECT_ID is REQUIRED (deliberately - two scripts run in the right
# order relies on nobody ever forgetting the first one; one script that
# can't run without stating a target can't be half-forgotten). If it
# disagrees with what's currently committed in lib/firebase_options.dart,
# this script runs `flutterfire configure` itself rather than just telling
# you to - that's only safe because reaching this branch already required
# an explicit, deliberate GCP_PROJECT_ID, not an accidental default.
#
# Caveat this does NOT solve: flutterfire configure only rewrites files in
# this local working directory. Run this on your own machine and it's a
# normal `git status` away from a commit. Run it inside CI and those
# changes die with the ephemeral checkout unless that pipeline also commits
# and pushes them - which cloudbuild.yaml's sync-infra-config step does
# not currently do. Treat an environment move as a local, human-run,
# human-committed operation for now.
#
# Usage:
#   GCP_PROJECT_ID=i-destiny-428904-s2 ./tool/generate_infra_config.sh          # routine refresh, same project
#   GCP_PROJECT_ID=new-project-id   ./tool/generate_infra_config.sh          # environment move - runs flutterfire configure first
#
# Uses whatever account `gcloud` is currently active as; override with
# GCLOUD_ACCOUNT. Override FUNCTION_REGION if the backend ever moves
# process-run-sheet-upload out of us-west1.
set -euo pipefail

if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
  echo "error: GCP_PROJECT_ID is required - which project should this target?" >&2
  echo "       (this repo's committed value: see lib/firebase_options.dart's" >&2
  echo "       projectId if you're just refreshing the current environment)" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FUNCTION_REGION="${FUNCTION_REGION:-us-west1}"

ACCOUNT_FLAG=()
if [[ -n "${GCLOUD_ACCOUNT:-}" ]]; then
  ACCOUNT_FLAG=(--account="$GCLOUD_ACCOUNT")
fi

COMMITTED_PROJECT_ID=$(python3 -c "
import re
text = open('$REPO_DIR/lib/firebase_options.dart').read()
print(re.search(r\"projectId: '([^']+)'\", text).group(1))
")

if [[ "$GCP_PROJECT_ID" != "$COMMITTED_PROJECT_ID" ]]; then
  echo "lib/firebase_options.dart targets $COMMITTED_PROJECT_ID, not" >&2
  echo "$GCP_PROJECT_ID - running flutterfire configure to fix that first." >&2
  command -v flutterfire >/dev/null || {
    echo "error: flutterfire CLI not installed. Run:" >&2
    echo "       dart pub global activate flutterfire_cli" >&2
    echo "       (also needs the Firebase CLI: npm install -g firebase-tools," >&2
    echo "       then 'firebase login')" >&2
    exit 1
  }
  (cd "$REPO_DIR" && flutterfire configure --project="$GCP_PROJECT_ID" --platforms=android,ios,web --yes)
  echo "flutterfire configure done - firebase_options.dart, google-services.json," >&2
  echo "and GoogleService-Info.plist were just rewritten. Review + commit them" >&2
  echo "once this script finishes (see git status below)." >&2
fi
PROJECT_ID="$GCP_PROJECT_ID"
echo "targeting project: $PROJECT_ID" >&2

RUN_SHEETS_BUCKET=$(gcloud functions describe process-run-sheet-upload \
  --region="$FUNCTION_REGION" --project="$PROJECT_ID" --gen2 --format=json "${ACCOUNT_FLAG[@]}" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
filters = {f['attribute']: f['value'] for f in d['eventTrigger']['eventFilters']}
print(filters['bucket'])
")

# The Owner Maps screen's endpoint. Not fatal when absent: the function is a
# later addition than the rest of this config, and an older project that
# hasn't deployed it yet should still be able to regenerate everything else.
# The app checks for the empty string rather than parsing a blank URL.
RIDER_BOARD_URL=$(gcloud functions describe rider-board \
  --region="$FUNCTION_REGION" --project="$PROJECT_ID" --gen2 \
  --format="value(serviceConfig.uri)" "${ACCOUNT_FLAG[@]}" 2>/dev/null || true)
if [ -z "$RIDER_BOARD_URL" ]; then
  echo "warning: rider-board function not found in $PROJECT_ID/$FUNCTION_REGION -" >&2
  echo "         riderBoardUrl will be empty and the Owner Maps screen will" >&2
  echo "         report that it isn't configured. Deploy it, then re-run." >&2
fi

TOKEN=$(gcloud auth print-access-token "${ACCOUNT_FLAG[@]}")
SIGNIN_CLIENT_ID=$(curl -sf -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT_ID" \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/$PROJECT_ID/defaultSupportedIdpConfigs/google.com" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['clientId'])")
# clientSecret also comes back in that response - deliberately never read or
# stored here. It's a real secret and has no business in client app code.

OUT="$REPO_DIR/lib/config/infra_config.dart"
cat > "$OUT" <<EOF
// GENERATED by tool/generate_infra_config.sh - do not hand-edit.
// Re-run it after infra changes (bucket recreated, sign-in client rotated)
// instead of updating these values by hand. Sourced from live GCP/Firebase
// state, not from the backend repo's filesystem - see the script for why.
//
// Sources:
//   runSheetsBucket              <- process-run-sheet-upload Cloud
//                                    Function's Storage trigger config
//                                    (project $PROJECT_ID, region $FUNCTION_REGION)
//   googleSignInServerClientId   <- Firebase Auth's Google IdP config
//                                    (projects/$PROJECT_ID/defaultSupportedIdpConfigs/google.com)
//   riderBoardUrl                <- rider-board Cloud Function's URL
//                                    (project $PROJECT_ID, region $FUNCTION_REGION)
class InfraConfig {
  InfraConfig._();

  /// The rider-board endpoint backing the Owner Maps screen. Called with the
  /// signed-in owner's Firebase ID token; the function verifies the token and
  /// the \`role: owner\` claim itself, since Cloud Run IAM can't.
  ///
  /// Empty when the function isn't deployed in the target project - callers
  /// must check rather than parsing it blindly.
  static const riderBoardUrl = '$RIDER_BOARD_URL';

  /// The OAuth web client ID backing Firebase's Google sign-in provider.
  /// Not a secret (it's a public identifier apps embed directly), but
  /// Android's GoogleSignIn needs it explicitly as \`serverClientId\` to
  /// request an ID token Firebase can verify - without it,
  /// GoogleSignIn.instance.initialize() throws on Android.
  static const googleSignInServerClientId = '$SIGNIN_CLIENT_ID';

  /// The dedicated Storage bucket run sheet PDFs must land in - not the
  /// default firebase_options.dart bucket. process_run_sheet_upload_fn.py's
  /// Cloud Storage trigger and storage.rules' owner-only write rule are
  /// only bound to this bucket; uploading to the default bucket instead
  /// silently never triggers processing.
  static const runSheetsBucket = 'gs://$RUN_SHEETS_BUCKET';
}
EOF

echo "wrote $OUT"

CHANGED=$(cd "$REPO_DIR" && git status --short lib/config/infra_config.dart lib/firebase_options.dart \
  android/app/google-services.json ios/Runner/GoogleService-Info.plist 2>/dev/null || true)
if [[ -n "$CHANGED" ]]; then
  echo "" >&2
  echo "uncommitted changes from this run - review and commit:" >&2
  echo "$CHANGED" >&2
fi
