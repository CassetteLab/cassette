#!/usr/bin/env bash
# Submits one artifact to the Apple notary service and fails loudly when it is rejected.
#
# `notarytool submit --wait` exits 0 even when the submission comes back Invalid, so the workflow
# used to sail past a rejection and fail later at `stapler staple` with "Could not find base64
# encoded ticket" — which says nothing about what Apple actually objected to. The rejection reasons
# live only in `notarytool log`, so fetch it here: without it a notarisation failure is unreadable.
#
# Usage: notarize.sh <path-to-zip-or-dmg>
# Requires: AC_API_KEY_ID, AC_API_ISSUER_ID, RUNNER_TEMP/AuthKey.p8
set -euo pipefail

ARTIFACT="$1"
KEY_ARGS=(--key "$RUNNER_TEMP/AuthKey.p8" --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER_ID")

echo "Submitting $(basename "$ARTIFACT") for notarisation…"
RESULT="$(xcrun notarytool submit "$ARTIFACT" "${KEY_ARGS[@]}" --wait --output-format json)"
echo "$RESULT"

read -r STATUS SUBMISSION_ID <<<"$(printf '%s' "$RESULT" | /usr/bin/python3 -c \
  'import json,sys; d=json.load(sys.stdin); print(d.get("status",""), d.get("id",""))')"

if [ "$STATUS" = "Accepted" ]; then
  echo "Notarisation accepted ($SUBMISSION_ID)."
  exit 0
fi

echo "::group::notarytool log for $SUBMISSION_ID"
xcrun notarytool log "$SUBMISSION_ID" "${KEY_ARGS[@]}" || echo "(could not fetch the log)"
echo "::endgroup::"
echo "::error::Notarisation came back '$STATUS' for $(basename "$ARTIFACT") — see the log above."
exit 1
