---
layout: page
title: Release Checklist
---

# Release Checklist

Use this checklist before publishing a package release.

## Versioning

- Update `pubspec.yaml`.
- Update `ios/firebase_messaging_handler.podspec` to the same version.
- Update `example/pubspec.lock` after dependency resolution or path-package version changes.
- Add a concise, user-facing `CHANGELOG.md` entry.

## Local Checks

Run from the package root:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
(cd server && npm test)
(cd example && flutter build web --release)
(cd example && flutter build apk --debug)
```

On a macOS release host, also build the example for the iOS simulator and run
the podspec/SPM checks appropriate to the release.

## Publish Dry Run

Run a normal dry run:

```bash
flutter pub publish --dry-run
```

If the only warning is about uncommitted files while preparing a release, verify package contents from a temporary copy without `.git`:

```bash
rm -rf /tmp/fmh_publish_check
mkdir -p /tmp/fmh_publish_check
rsync -a --exclude='.git' --exclude='.dart_tool' --exclude='build' ./ /tmp/fmh_publish_check/
cd /tmp/fmh_publish_check
flutter pub publish --dry-run
```

The temporary-copy dry run should report `Package has 0 warnings`.

## Pub Score Check

Run `pana` with an explicit Flutter SDK path so Flutter package docs and platform scoring are evaluated correctly:

```bash
dart pub global activate pana
dart pub global run pana --flutter-sdk /path/to/flutter .
```

Expected release target: `160/160`.

## Android Integration Tests

Run these from `example/` with a connected Android device:

```bash
BASE64=$(base64 -i ../test/firebase_config/service_account.json | tr -d '\n')

flutter test integration_test/comprehensive_test.dart \
  --dart-define=FCM_TEST_SENDER_ID=<your-project-number> \
  --dart-define=FCM_SERVICE_ACCOUNT_B64=$BASE64 \
  --device-id <device-id>

flutter test integration_test/real_push_test.dart \
  --dart-define=FCM_TEST_SENDER_ID=<your-project-number> \
  --dart-define=FCM_SERVICE_ACCOUNT_B64=$BASE64 \
  --device-id <device-id>
```

The package-root handler integration test is synthetic and runs on the test VM:

```bash
flutter test test/handlers_integration_test.dart
```

## Final Review

- Confirm `CHANGELOG.md` is user-facing and does not include raw validation logs.
- Confirm README links resolve to existing files.
- Confirm `doc/index.md` reflects current platform support and setup flow.
- Validate the JSON Schema and reference server tests.
- Run physical-device scenarios for foreground, background, terminated launch,
  actions, inline reply, exact/inexact scheduling, token rotation, duplicate
  delivery, remote cancel/mark-read, rich media, and permission denial.
- Commit release changes before publishing to avoid dirty-worktree publish warnings.
