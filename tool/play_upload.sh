#!/usr/bin/env bash
# Runs tool/play_upload.py in its own small virtualenv (made on first use), so
# releasing needs nothing installed beyond python3.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
venv="$here/.venv-release"
if [[ ! -x "$venv/bin/python" ]]; then
  python3 -m venv "$venv"
  "$venv/bin/pip" install -q "google-auth>=2.30" "requests>=2.32"
fi
exec "$venv/bin/python" -I "$here/play_upload.py" "$@"
