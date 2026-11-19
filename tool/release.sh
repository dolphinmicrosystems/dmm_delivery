#!/usr/bin/env bash
# One command from code to Google Play:
#
#   tool/release.sh patch                 # 1.0.3 (5) -> 1.0.4 (6), to internal testing
#   tool/release.sh minor --track closed  # 1.0.4 (6) -> 1.1.0 (7), to the closed beta
#   tool/release.sh major --notes "New run summary"  # -> 2.0.0, with "What's new"
#   tool/release.sh patch --no-upload     # bump, check and build only
#
# Steps: bump `version:` in pubspec.yaml (semantic version + a build number
# that only ever goes up - Play's versionCode), flutter analyze, flutter test,
# build the signed App Bundle, upload it to the chosen Play track, then commit
# pubspec.yaml and tag the commit v<version>+<build> (not pushed).
#
# Which part to bump:
#   patch - fixes only            1.0.3 -> 1.0.4
#   minor - new features          1.0.4 -> 1.1.0
#   major - big, breaking change  1.1.0 -> 2.0.0
#   build - same version, rebuilt 1.1.0 (7) -> 1.1.0 (8), e.g. a failed upload
#
# Tracks: internal (default; testers get it in minutes), closed (the beta),
# open, production.
#
# Needs: android/key.properties (the upload key), dart_defines.json, and for
# the upload, access to the Play publishing service account (see
# tool/play_upload.py). Nothing is uploaded or committed if a check fails.
set -euo pipefail

cd "$(dirname "$0")/.."

part="${1:-}"
shift || true
track="internal"
notes=""
upload=1
git_tag=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --track) track="$2"; shift 2 ;;
    --notes) notes="$2"; shift 2 ;;
    --no-upload) upload=0; shift ;;
    --no-git) git_tag=0; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$part" in
  patch|minor|major|build) ;;
  *) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
case "$track" in
  internal|closed|open|production) ;;
  *) echo "Track must be internal, closed, open or production." >&2; exit 2 ;;
esac

if [[ ! -f android/key.properties ]]; then
  echo "android/key.properties is missing: Play only accepts a bundle signed with your upload key." >&2
  exit 1
fi
if [[ ! -f dart_defines.json ]]; then
  echo "dart_defines.json is missing (copy dart_defines.example.json and fill it in)." >&2
  exit 1
fi

current=$(sed -n 's/^version: *//p' pubspec.yaml)
if [[ ! "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]]; then
  echo "pubspec.yaml version '$current' isn't MAJOR.MINOR.PATCH+BUILD." >&2
  exit 1
fi
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]} build=${BASH_REMATCH[4]}
case "$part" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  build) ;;
esac
build=$((build + 1))
next="$major.$minor.$patch+$build"
label="$major.$minor.$patch ($build)"

echo "==> $current -> $next, for the $track track"
sed -i "s/^version: .*/version: $next/" pubspec.yaml
# Put the old version back if anything below fails, so a failed release
# never leaves a half-bumped pubspec behind.
restore() { sed -i "s/^version: .*/version: $current/" pubspec.yaml; echo "Release stopped; version left at $current." >&2; }
trap restore ERR

echo "==> flutter analyze"
flutter analyze
echo "==> flutter test"
flutter test
echo "==> building the App Bundle"
flutter build appbundle --release --dart-define-from-file=dart_defines.json
bundle=build/app/outputs/bundle/release/app-release.aab

if [[ $upload -eq 1 ]]; then
  echo "==> uploading $label to Play ($track)"
  tool/play_upload.sh --bundle "$bundle" --track "$track" --name "$label" --notes "$notes"
fi
trap - ERR

if [[ $git_tag -eq 1 ]]; then
  git commit -q -m "Release $label" pubspec.yaml
  git tag "v$next"
  echo "==> committed and tagged v$next (push with: git push && git push --tags)"
fi

echo "Done: Blue Dot $label$([[ $upload -eq 1 ]] && echo " is on the $track track")."
