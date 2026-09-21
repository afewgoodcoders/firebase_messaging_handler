#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# terminated_state_manual.sh
#
# Manual fallback for the "terminated state / cold start" FCM scenario.
# Prefer android_lifecycle_e2e.sh when ADB notification-shade automation is
# available; this helper supports devices that still need a human tap.
#
# Usage:
#   bash test/firebase_config/terminated_state_manual.sh \
#     --token   <fcm-token> \
#     --project <firebase-project-id> \
#     --key-file test/firebase_config/service_account.json
#
# Before running, move the app to the background and kill its process without
# force-stopping the package. Android blocks FCM delivery to a force-stopped app
# until the user launches it again.
#
# Steps performed:
#   1. Obtains an OAuth2 bearer token from the service account.
#   2. POSTs an FCM notification to the already-terminated app.
#   3. Prints the remaining tap-verification instructions.
# ---------------------------------------------------------------------------

set -euo pipefail

# ── Argument parsing ────────────────────────────────────────────────────────
FCM_TOKEN=""
PROJECT_ID=""
KEY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)   FCM_TOKEN="$2";   shift 2 ;;
    --project) PROJECT_ID="$2";  shift 2 ;;
    --key-file) KEY_FILE="$2";   shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$FCM_TOKEN" || -z "$PROJECT_ID" || -z "$KEY_FILE" ]]; then
  echo "Usage: $0 --token <fcm-token> --project <project-id> --key-file <path>"
  exit 1
fi

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Service account file not found: $KEY_FILE" >&2
  exit 1
fi

# ── Dependency check ────────────────────────────────────────────────────────
for cmd in python3 curl jq openssl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Required tool not found: $cmd" >&2
    exit 1
  fi
done

# ── Step 1: Obtain OAuth2 bearer token ─────────────────────────────────────
echo "[1/3] Obtaining OAuth2 bearer token from service account…"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fmh-manual.XXXXXX")
trap 'rm -rf -- "$TEMP_DIR"' EXIT
JWT_PARTS=$(python3 - "$KEY_FILE" <<'PYEOF'
import base64, json, sys, time

with open(sys.argv[1], encoding="utf-8") as source:
    account = json.load(source)
encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=").decode()
now = int(time.time())
print(encode(json.dumps({"alg":"RS256","typ":"JWT"}, separators=(",", ":")).encode()))
print(encode(json.dumps({
    "iss": account["client_email"],
    "scope": "https://www.googleapis.com/auth/firebase.messaging",
    "aud": "https://oauth2.googleapis.com/token",
    "exp": now + 3600,
    "iat": now,
}, separators=(",", ":")).encode()))
PYEOF
)
JWT_HEADER=$(printf '%s\n' "$JWT_PARTS" | sed -n '1p')
JWT_PAYLOAD=$(printf '%s\n' "$JWT_PARTS" | sed -n '2p')
PRIVATE_KEY="$TEMP_DIR/private-key.pem"
jq -r '.private_key' "$KEY_FILE" >"$PRIVATE_KEY"
chmod 600 "$PRIVATE_KEY"
JWT_SIGNATURE=$(printf '%s' "$JWT_HEADER.$JWT_PAYLOAD" \
  | openssl dgst -sha256 -sign "$PRIVATE_KEY" -binary \
  | openssl base64 -A \
  | tr '+/' '-_' \
  | tr -d '=')
JWT_ASSERTION="$JWT_HEADER.$JWT_PAYLOAD.$JWT_SIGNATURE"
TOKEN_RESPONSE=$(curl -sS \
  -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
  --data-urlencode "assertion=$JWT_ASSERTION" \
  'https://oauth2.googleapis.com/token')
BEARER=$(printf '%s' "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [[ -z "$BEARER" ]]; then
  echo "OAuth token exchange failed: $(printf '%s' "$TOKEN_RESPONSE" | jq -c .)" >&2
  exit 1
fi

echo "   ✓ Bearer token obtained."

# ── Step 2: Send FCM notification ──────────────────────────────────────────
echo "[2/3] Sending terminated-state FCM notification…"

TS=$(date +%s)
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $BEARER" \
  -H "Content-Type: application/json" \
  "https://fcm.googleapis.com/v1/projects/$PROJECT_ID/messages:send" \
  -d "{
    \"message\": {
      \"token\": \"$FCM_TOKEN\",
      \"notification\": {
        \"title\": \"Terminated State Test\",
        \"body\": \"Cold-start integration test — ts=$TS\"
      },
      \"data\": {
        \"fcmh_test_ts\": \"$TS\",
        \"fcmh_test_type\": \"terminated_state\"
      }
    }
  }")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "FCM send failed (HTTP $HTTP_CODE):" >&2
  echo "$BODY" | jq . >&2
  exit 1
fi

echo "   ✓ Message sent. FCM name: $(echo "$BODY" | jq -r .name)"

# ── Step 3: Developer instructions ─────────────────────────────────────────
cat <<INSTRUCTIONS

[3/3] Manual verification steps:
─────────────────────────────────────────────────────────────────────────────
A notification titled "Terminated State Test" has been sent to your device.

This helper assumes the app process was killed before the command was run and
the package was not force-stopped. To finish verifying cold-start behaviour:

  1. Wait for the notification to appear on the device lock screen or
     notification shade (usually within a few seconds).
  2. Tap the notification to launch the app.
  3. Inspect the app's initial notification handling:
       FirebaseMessagingHandler.checkInitial()
     should return a non-null NotificationData with:
       - title: "Terminated State Test"
       - payload.fcmh_test_ts: "$TS"
  4. Alternatively, check your unified handler or analytics callback for
     the lifecycle value NotificationLifecycle.terminated.

Expected: The app opens directly to whatever screen your notification router
          targets, and checkInitial() returns the notification data.

─────────────────────────────────────────────────────────────────────────────
INSTRUCTIONS
