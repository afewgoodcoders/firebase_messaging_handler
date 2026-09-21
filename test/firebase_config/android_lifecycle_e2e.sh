#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
EXAMPLE_DIR="$REPO_ROOT/example"
KEY_FILE="$SCRIPT_DIR/service_account.json"
DEVICE_ID=""
PROJECT_ID=""
APP_ID="qoder.flutter.fmhexample"
MAIN_ACTIVITY="com.afewgoodcoders.fmhexample.MainActivity"
REMOTE_XML="/sdcard/fmh-lifecycle-window.xml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE_ID="$2"; shift 2 ;;
    --project) PROJECT_ID="$2"; shift 2 ;;
    --key-file) KEY_FILE="$2"; shift 2 ;;
    --application-id) APP_ID="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

for command in adb curl flutter jq openssl python3; do
  command -v "$command" >/dev/null || {
    echo "Required command not found: $command" >&2
    exit 2
  }
done

[[ -n "$DEVICE_ID" ]] || {
  echo "Usage: $0 --device <adb-device-id> [--project <id>] [--key-file <path>]" >&2
  exit 2
}
[[ -f "$KEY_FILE" ]] || {
  echo "Service account file not found: $KEY_FILE" >&2
  exit 2
}

if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["project_id"])' "$KEY_FILE")
fi

ADB=(adb -s "$DEVICE_ID")
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fmh-lifecycle.XXXXXX")
trap 'rm -rf -- "$TEMP_DIR"' EXIT

dump_ui() {
  "${ADB[@]}" shell uiautomator dump "$REMOTE_XML" >/dev/null 2>&1
  "${ADB[@]}" exec-out cat "$REMOTE_XML"
}

read_probe_value() {
  local prefix="$1"
  dump_ui | python3 -c '
import sys, xml.etree.ElementTree as ET
prefix = sys.argv[1]
try:
    root = ET.fromstring(sys.stdin.read())
except Exception:
    raise SystemExit(1)
for node in root.iter("node"):
    value = node.attrib.get("content-desc", "")
    if value.startswith(prefix):
        print(value[len(prefix):].splitlines()[0], end="")
        raise SystemExit(0)
raise SystemExit(1)
' "$prefix"
}

wait_for_probe() {
  local prefix="$1"
  local expected="$2"
  local attempts="${3:-60}"
  local value=""
  for ((i = 0; i < attempts; i++)); do
    value=$(read_probe_value "$prefix" 2>/dev/null || true)
    if [[ "$value" == *"$expected"* ]]; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for ${prefix}${expected}; last value: ${value:-unavailable}" >&2
  return 1
}

tap_notification_text() {
  local text="$1"
  local notification_title="${2:-}"
  local coordinates=""
  local title_coordinates=""
  "${ADB[@]}" shell input keyevent WAKEUP >/dev/null 2>&1 || true
  "${ADB[@]}" shell wm dismiss-keyguard >/dev/null 2>&1 || true
  "${ADB[@]}" shell cmd statusbar expand-notifications >/dev/null
  sleep 2
  for ((i = 0; i < 20; i++)); do
    coordinates=$(dump_ui | python3 -c '
import re, sys, xml.etree.ElementTree as ET
target = sys.argv[1]
try:
    root = ET.fromstring(sys.stdin.read())
except Exception:
    raise SystemExit(1)
for node in root.iter("node"):
    if target not in (node.attrib.get("text", ""), node.attrib.get("content-desc", "")):
        continue
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib.get("bounds", ""))
    if match:
        x1, y1, x2, y2 = map(int, match.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        raise SystemExit(0)
raise SystemExit(1)
' "$text" 2>/dev/null || true)
    if [[ -n "$coordinates" ]]; then
      read -r x y <<<"$coordinates"
      "${ADB[@]}" shell input tap "$x" "$y"
      return 0
    fi

    if [[ -n "$notification_title" ]]; then
      title_coordinates=$(dump_ui | python3 -c '
import re, sys, xml.etree.ElementTree as ET
target = sys.argv[1]
try:
    root = ET.fromstring(sys.stdin.read())
except Exception:
    raise SystemExit(1)
for node in root.iter("node"):
    if target not in (node.attrib.get("text", ""), node.attrib.get("content-desc", "")):
        continue
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib.get("bounds", ""))
    if match:
        x1, y1, x2, y2 = map(int, match.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        raise SystemExit(0)
raise SystemExit(1)
' "$notification_title" 2>/dev/null || true)
      if [[ -n "$title_coordinates" ]]; then
        read -r title_x title_y <<<"$title_coordinates"
        expanded_y=$((title_y + 450))
        ((expanded_y > 1950)) && expanded_y=1950
        "${ADB[@]}" shell input swipe "$title_x" "$title_y" "$title_x" "$expanded_y" 700
        sleep 1
        continue
      fi
    fi

    # Scroll at the edge so the gesture does not accidentally select a card.
    "${ADB[@]}" shell input swipe 1030 1900 1030 750 900 >/dev/null 2>&1 || true
    sleep 1
  done
  echo "Notification UI text not found: $text" >&2
  return 1
}

launch_probe() {
  "${ADB[@]}" shell am start -W -n "$APP_ID/$MAIN_ACTIVITY" >/dev/null
  wait_for_probe 'probe_status=' 'ready' 60
}

send_fcm() {
  local mode="$1"
  local title="$2"
  local body="$3"
  local marker="$4"
  local payload="$TEMP_DIR/payload.json"
  local response="$TEMP_DIR/response.json"

  if [[ "$mode" == "notification" ]]; then
    jq -n \
      --arg token "$FCM_TOKEN" \
      --arg title "$title" \
      --arg body "$body" \
      --arg marker "$marker" \
      '{message:{token:$token,notification:{title:$title,body:$body},data:{marker:$marker,lifecycle:"terminated"},android:{priority:"high"}}}' \
      >"$payload"
  else
    jq -n \
      --arg token "$FCM_TOKEN" \
      --arg title "$title" \
      --arg body "$body" \
      --arg marker "$marker" \
      '{message:{token:$token,data:{schemaVersion:"2",id:$marker,idempotencyKey:$marker,command:"display",title:$title,body:$body,marker:$marker,lifecycle:"background"},android:{priority:"high"}}}' \
      >"$payload"
  fi

  local status
  status=$(curl -sS -o "$response" -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer $BEARER" \
    -H 'Content-Type: application/json' \
    --data-binary "@$payload" \
    "https://fcm.googleapis.com/v1/projects/$PROJECT_ID/messages:send")
  if [[ "$status" != "200" ]]; then
    echo "FCM send failed with HTTP $status: $(jq -c . "$response")" >&2
    return 1
  fi
}

echo '[1/5] Building and installing the lifecycle probe…'
(
  cd "$EXAMPLE_DIR"
  ORG_GRADLE_PROJECT_fmhApplicationId="$APP_ID" \
    flutter build apk --debug --target integration_test/lifecycle_probe_app.dart
)
"${ADB[@]}" install -r "$EXAMPLE_DIR/build/app/outputs/flutter-apk/app-debug.apk" >/dev/null
"${ADB[@]}" shell pm clear "$APP_ID" >/dev/null
"${ADB[@]}" shell input keyevent WAKEUP >/dev/null 2>&1 || true
"${ADB[@]}" shell wm dismiss-keyguard >/dev/null 2>&1 || true
launch_probe
FCM_TOKEN=$(read_probe_value 'probe_token=')
[[ -n "$FCM_TOKEN" && "$FCM_TOKEN" != 'pending' ]] || {
  echo 'Lifecycle probe did not expose a usable FCM token.' >&2
  exit 1
}

echo '[2/5] Authenticating the test sender…'
JWT_PARTS=$(python3 - "$KEY_FILE" <<'PY'
import base64, json, sys, time

with open(sys.argv[1], encoding="utf-8") as source:
    account = json.load(source)
encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=").decode()
now = int(time.time())
print(encode(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode()))
print(encode(json.dumps({
    "iss": account["client_email"],
    "scope": "https://www.googleapis.com/auth/firebase.messaging",
    "aud": "https://oauth2.googleapis.com/token",
    "iat": now,
    "exp": now + 3600,
}, separators=(",", ":")).encode()))
PY
)
JWT_HEADER=$(printf '%s\n' "$JWT_PARTS" | sed -n '1p')
JWT_CLAIMS=$(printf '%s\n' "$JWT_PARTS" | sed -n '2p')
PRIVATE_KEY="$TEMP_DIR/private-key.pem"
jq -r '.private_key' "$KEY_FILE" >"$PRIVATE_KEY"
chmod 600 "$PRIVATE_KEY"
JWT_SIGNATURE=$(printf '%s' "$JWT_HEADER.$JWT_CLAIMS" \
  | openssl dgst -sha256 -sign "$PRIVATE_KEY" -binary \
  | openssl base64 -A \
  | tr '+/' '-_' \
  | tr -d '=')
JWT_ASSERTION="$JWT_HEADER.$JWT_CLAIMS.$JWT_SIGNATURE"
TOKEN_RESPONSE=$(curl -sS \
  -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
  --data-urlencode "assertion=$JWT_ASSERTION" \
  'https://oauth2.googleapis.com/token')
BEARER=$(printf '%s' "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
[[ -n "$BEARER" ]] || {
  echo "OAuth token exchange failed: $(printf '%s' "$TOKEN_RESPONSE" | jq -c .)" >&2
  exit 1
}

echo '[3/5] Verifying a background notification action…'
ACTION_MARKER=$(read_probe_value 'probe_action=')
"${ADB[@]}" shell input keyevent HOME >/dev/null
tap_notification_text 'ACK' 'FMH Action Probe'
sleep 2
"${ADB[@]}" shell am force-stop "$APP_ID"
launch_probe
wait_for_probe 'probe_event=' "$ACTION_MARKER|background|ack" 30

echo '[4/5] Verifying high-priority data-only background delivery and bridge…'
BACKGROUND_MARKER="background-$(date +%s)"
"${ADB[@]}" shell input keyevent HOME >/dev/null
send_fcm data 'FMH Background Data' 'Background bridge and tap test' "$BACKGROUND_MARKER"
tap_notification_text 'FMH Background Data'
wait_for_probe 'probe_background=' "$BACKGROUND_MARKER" 30
wait_for_probe 'probe_event=' "$BACKGROUND_MARKER|background|none" 30

echo '[5/5] Verifying notification-driven cold start from a killed process…'
TERMINATED_MARKER="terminated-$(date +%s)"
"${ADB[@]}" shell input keyevent HOME >/dev/null
"${ADB[@]}" shell am kill "$APP_ID"
for ((i = 0; i < 20; i++)); do
  [[ -z "$("${ADB[@]}" shell pidof "$APP_ID" 2>/dev/null | tr -d '\r')" ]] && break
  sleep 1
done
if [[ -n "$("${ADB[@]}" shell pidof "$APP_ID" 2>/dev/null | tr -d '\r')" ]]; then
  echo 'Could not kill the background app without marking it force-stopped.' >&2
  exit 1
fi
send_fcm notification 'FMH Terminated State' 'Tap to validate cold-start routing' "$TERMINATED_MARKER"
tap_notification_text 'FMH Terminated State'
wait_for_probe 'probe_status=' 'ready' 60
wait_for_probe 'probe_initial=' "$TERMINATED_MARKER|terminated|none" 30

echo 'PASS: action routing, background data bridge, and terminated cold start all succeeded.'
