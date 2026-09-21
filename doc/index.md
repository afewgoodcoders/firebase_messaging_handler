---
layout: home
title: Firebase Messaging Handler
---

# Firebase Messaging Handler

Production-ready Firebase Cloud Messaging for Flutter with a unified click stream, notification inbox, in-app messaging, diagnostics, badges, and scheduling.

## Start Here

Follow the guide for the platforms you ship:

- [Installation](./getting-started/installation)
- [Android setup](./getting-started/android-setup)
- [iOS setup](./getting-started/ios-setup)
- [macOS setup](./getting-started/macos-setup)
- [Desktop setup](./getting-started/desktop-setup)
- [Web setup](./getting-started/web-setup)
- [2.0 migration](./v2-migration)
- [Platform capability matrix](./platform-capabilities)

For releases and local validation, use the [release checklist](./release-checklist).

## Platform Support

| Platform | Push / FCM | Local display | Scheduling | Inbox / in-app | Notes |
| --- | --- | --- | --- | --- | --- |
| Android | Yes | Yes | Yes | Yes | Best-supported path for full end-to-end validation, including real FCM device tests. |
| iOS | Yes | Yes | Yes | Yes | Requires APNs configuration in Apple Developer and Firebase. Swift Package Manager and CocoaPods are both supported. |
| Web | Yes | Browser notification only | No | Yes | Requires Firebase web config, a messaging service worker, secure context, notification permission, and `webVapidKey` when your Firebase project requires one. WASM analysis is supported. |
| macOS | Firebase-dependent | Yes | Yes | Yes | Validate token retrieval and foreground/background delivery on target hardware before shipping. |
| Windows | No FCM delivery | Local-notification surface where dependencies support it | Local-notification surface where dependencies support it | Yes | FCM is disabled gracefully; diagnostics explain the unsupported FCM path. |
| Linux | No FCM delivery | Local-notification surface where dependencies support it | Local-notification surface where dependencies support it | Yes | FCM is disabled gracefully; diagnostics explain the unsupported FCM path. |

## Recommended Setup Path

1. Install the package and initialize Firebase for your app.
2. Complete the platform setup guide for every target you ship.
3. Call `FirebaseMessagingHandler.instance.initialize(FCMConfiguration(...))`
   once during app startup.
4. Request permission from your own explanatory UI, then synchronize the token.
5. Subscribe to the returned click stream and wire your navigation handler.
6. Run `runDiagnostics()` on real devices before debugging backend payloads.
7. For release validation, run unit tests, publish dry-run, `pana`, and the
   example device integration tests from the release checklist.

## Core Features

- [Push notifications](./features/push-notifications)
- [In-app messaging](./features/in-app-messaging)
- [Notification inbox](./features/notification-inbox)
- [Scheduling](./features/scheduling)
- [Badges](./features/badges)
- [Quiet hours](./features/quiet-hours)
- [Diagnostics](./features/diagnostics)
- [Server recipes](./features/server-recipes)
- [Envelope v2](./features/envelope-v2)

## Package Positioning

This package focuses on the practical gaps teams hit with raw `firebase_messaging`:

- foreground, background, and terminated click handling in one flow
- data-only payload promotion into local notifications
- in-app presentation and inbox storage
- diagnostics that surface real setup failures
- incremental adoption instead of all-or-nothing migration
