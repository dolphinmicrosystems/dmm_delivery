"""Uploads an App Bundle to a Google Play track (tool/release.sh calls this).

Signs in as the Play publishing service account
(play-publisher@<project>.iam.gserviceaccount.com, made by the backend's
Terraform, play_publisher.tf) by *impersonating* it with your own gcloud
login, so no key file exists to leak. You need, once:

  gcloud auth application-default login      # the login Terraform also uses
  and that account invited in Play Console -> Users and permissions, with
  "Release to testing tracks" (and production, when you get there).

PLAY_KEY_FILE=/path/key.json uses a service-account key instead, for CI.
"""

from __future__ import annotations

import argparse
import os
import sys

import google.auth
from google.auth import impersonated_credentials
from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PACKAGE = "com.delivery.dmm_delivery"
PROJECT = "i-destiny-428904-s2"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}"

# Our names -> the Play API's. "alpha" is Play's default closed testing track.
TRACKS = {"internal": "internal", "closed": "alpha", "open": "beta", "production": "production"}


def credentials():
    key_file = os.environ.get("PLAY_KEY_FILE")
    if key_file:
        return service_account.Credentials.from_service_account_file(key_file, scopes=[SCOPE])
    account = os.environ.get("PLAY_SERVICE_ACCOUNT", f"play-publisher@{PROJECT}.iam.gserviceaccount.com")
    source, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    return impersonated_credentials.Credentials(
        source_credentials=source, target_principal=account, target_scopes=[SCOPE], lifetime=3600
    )


def check(response, what: str):
    if response.ok:
        return response.json() if response.content else {}
    sys.exit(f"Play refused to {what} ({response.status_code}): {response.text}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--track", choices=TRACKS, default="internal")
    parser.add_argument("--name", required=True, help='release name, e.g. "1.0.4 (6)"')
    parser.add_argument("--notes", default="", help="What's new (en-US); empty for none")
    args = parser.parse_args()

    session = AuthorizedSession(credentials())
    edit = check(session.post(f"{API}/edits"), "open an edit")["id"]

    print(f"Uploading {os.path.getsize(args.bundle) / 1e6:.1f} MB...")
    with open(args.bundle, "rb") as bundle:
        uploaded = check(
            session.post(
                f"{UPLOAD}/edits/{edit}/bundles",
                params={"uploadType": "media"},
                data=bundle,
                headers={"Content-Type": "application/octet-stream"},
                timeout=900,
            ),
            "take the bundle",
        )
    version_code = str(uploaded["versionCode"])

    def release(status: str) -> dict:
        body = {"name": args.name, "versionCodes": [version_code], "status": status}
        if args.notes:
            body["releaseNotes"] = [{"language": "en-US", "text": args.notes[:500]}]
        return body

    track = TRACKS[args.track]
    status = "completed"
    check(
        session.put(f"{API}/edits/{edit}/tracks/{track}", json={"track": track, "releases": [release(status)]}),
        "set the track",
    )
    committed = session.post(f"{API}/edits/{edit}:commit")
    if not committed.ok and "draft app" in committed.text:
        # An app that has never been published only takes draft releases:
        # it is uploaded, and rolled out with one click in Play Console.
        status = "draft"
        edit = check(session.post(f"{API}/edits"), "open an edit")["id"]
        check(
            session.put(
                f"{API}/edits/{edit}/tracks/{track}", json={"track": track, "releases": [release(status)]}
            ),
            "set the track",
        )
        committed = session.post(f"{API}/edits/{edit}:commit")
    check(committed, "publish the release")

    if status == "draft":
        print(
            f"Uploaded {args.name} as a draft on {args.track}: Play Console -> Test and release -> "
            f"{args.track} -> Edit release -> Roll out. (Needed until the app's first release is out.)"
        )
    else:
        print(f"Released {args.name} to {args.track}. Testers get it from the Play Store shortly.")


if __name__ == "__main__":
    main()
