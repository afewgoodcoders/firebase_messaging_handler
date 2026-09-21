---
layout: page
title: Desktop Setup
---

# Desktop Setup

Windows and Linux run in desktop local mode.

## What works

- local notifications
- one-time scheduling on Windows where the upstream plugin supports it
- notification inbox
- quiet hours and delivery policy logic
- in-app templates
- diagnostics

## What does not work

- Firebase Cloud Messaging token retrieval
- topic subscribe/unsubscribe
- FCM background delivery
- remote push receipt through `firebase_messaging`

## Expected diagnostics

`runDiagnostics()` should report:

- `metadata['fcmSupported'] == false`
- a non-empty `metadata['fcmUnsupportedReason']`
- recommendations explaining desktop local mode

`requestPermissionsWizard()` should return:

- `overallStatus == 'desktop_local_mode'`

## Manual validation checklist

1. Launch the example app on Windows or Linux.
2. Open Notification Doctor and confirm desktop local mode is reported.
3. Trigger a local test notification from the showcase screen.
4. On Windows, query `getCapabilities()` and schedule only when supported.
5. Open the inbox screen and verify local entries render correctly.
6. Trigger an in-app template and verify presentation works.

## Recommendation

If your desktop app needs remote delivery, send events through your own backend and map them into local desktop presentation inside the app.
