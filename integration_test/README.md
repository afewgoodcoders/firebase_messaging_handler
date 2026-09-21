# Integration Tests

This repository has three automated test surfaces:

| Location | Type | Device app available? | Firebase required? |
| --- | --- | --- | --- |
| `test/handlers_integration_test.dart` | Synthetic handler integration test | No | No |
| `example/integration_test/comprehensive_test.dart` | Example-app feature checklist | Yes | Optional for send-dependent cases |
| `example/integration_test/real_push_test.dart` | Real FCM end-to-end tests | Yes | Yes |

The package root is a Flutter plugin, not an app. Device-deployable Android and iOS integration tests must run from `example/`, because that directory contains the app runners and platform manifests.

---

## Synthetic Package-Root Tests

`test/handlers_integration_test.dart` exercises the handler pipeline with synthetic `RemoteMessage` objects. It is intentionally stored under `test/` so Flutter runs it on the test VM instead of trying to deploy the plugin package as an app.

```bash
flutter test test/handlers_integration_test.dart
```

Use this for fast local checks that do not require Firebase credentials, a physical device, or platform notification permissions.

---

## Android Example-App Tests

Run device tests from the `example/` directory.

### Prerequisites

1. A connected, unlocked Android device.
2. Firebase config in `example/lib/firebase_options.dart` and `example/android/app/google-services.json`.
3. For real FCM sends, a service account key at `test/firebase_config/service_account.json`.
4. The Firebase project number, also called the sender ID.

### Comprehensive Feature Checklist

This test covers initialization, token handling, permissions, diagnostics, analytics, unified handlers, data-only bridging, scheduling, badges, notification display, custom channels, in-app messaging, and inbox behavior.

```bash
BASE64=$(base64 -i ../test/firebase_config/service_account.json | tr -d '\n')

flutter test integration_test/comprehensive_test.dart \
  --dart-define=FCM_TEST_SENDER_ID=<your-project-number> \
  --dart-define=FCM_SERVICE_ACCOUNT_B64=$BASE64 \
  --device-id <device-id>
```

If `FCM_SERVICE_ACCOUNT_B64` is omitted, send-dependent cases are skipped instead of failing.

### Real FCM End-to-End Test

This test retrieves a real device token, sends FCM HTTP v1 messages to that token, verifies diagnostics, and verifies data-only processing.

```bash
BASE64=$(base64 -i ../test/firebase_config/service_account.json | tr -d '\n')

flutter test integration_test/real_push_test.dart \
  --dart-define=FCM_TEST_SENDER_ID=<your-project-number> \
  --dart-define=FCM_SERVICE_ACCOUNT_B64=$BASE64 \
  --device-id <device-id>
```

For a wirelessly connected iOS device, use the included host driver because
`flutter test` does not currently expose Flutter's required publish-port flag:

```bash
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/real_push_test.dart \
  --dart-define=FCM_TEST_SENDER_ID=<your-project-number> \
  --dart-define=FCM_SERVICE_ACCOUNT_B64=$BASE64 \
  --device-id <device-id>
```

Foreground delivery, data-only delivery, deduplication, and active-notification
inspection are asserted inside the Flutter tests. Android notification actions,
background data bridging, notification taps, and killed-process cold starts are
covered by the ADB lifecycle harness below.

### Notification Permission

On Android 13+, pre-grant notification permission when you want deterministic permission assertions:

```bash
adb shell pm grant com.afewgoodcoders.fmhexample android.permission.POST_NOTIFICATIONS || true
```

If the package is not installed yet, Android may print `package not found`; the test can still install and request permission during setup.

---

## Android Physical-Lifecycle Test

The lifecycle harness builds a dedicated probe entrypoint, installs it under
the Firebase test app ID, clears that probe app's test data, sends real FCM HTTP
v1 messages, and drives the Android notification shade with ADB. It verifies:

- a notification action routed through the background callback;
- high-priority data-only delivery promoted by the default local bridge;
- tapping the bridged notification and replaying its payload; and
- a notification-driven cold start after the app process is killed without
  putting the package into Android's force-stopped state.

```bash
bash test/firebase_config/android_lifecycle_e2e.sh \
  --device <adb-device-id> \
  --key-file test/firebase_config/service_account.json
```

The script defaults to the project ID in the service account and the Firebase
test application ID `qoder.flutter.fmhexample`.

## Manual Cold-Start Fallback

Use the manual helper when notification-shade UI automation is unavailable on a
particular Android image, or for human visual verification:

```bash
bash test/firebase_config/terminated_state_manual.sh \
  --token <fcm-token> \
  --project <firebase-project-id> \
  --key-file test/firebase_config/service_account.json
```

---

## CI Notes

The real-FCM tests are safe to run without credentials because send-dependent cases skip when credentials are absent. For full end-to-end CI, use a physical-device runner or device farm with Firebase config, service account injection, and notification permission handling.
