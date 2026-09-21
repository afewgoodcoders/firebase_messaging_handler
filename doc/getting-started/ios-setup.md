---
layout: page
title: iOS Setup
---

# iOS Setup

## Firebase

Add `GoogleService-Info.plist` to `ios/Runner/` and ensure Firebase is configured in the host app.

Firebase Messaging relies on AppDelegate method swizzling for APNs token
mapping and notification callbacks. Leave `FirebaseAppDelegateProxyEnabled`
enabled (the default). If the host application disables it, it must implement
Firebase's complete manual APNs-token and callback forwarding instead.

## APNs

Push delivery on physical iOS devices requires:

- Push Notifications capability
- Background Modes with remote notifications
- Valid APNs setup in Apple Developer and Firebase

## Permissions

Initialize first, explain the value to the user, then request permission with
`requestNotificationPermission()`. Configure provisional, announcement,
CarPlay, or critical-alert options only when the application is entitled to use
them.

Register `NotificationActionCategory` values during initialization so actions
and inline replies are available before the first notification arrives.

## Rich media

Images delivered by remote notification require an app-owned Notification
Service Extension and `mutable-content: 1`. Start from
`ios/NotificationServiceExtension.template.swift`; update its bundle ID,
signing, entitlements, file-type validation, size limits, and network policy for
the host application.

## Validation

Use the example app or `runDiagnostics()` to confirm permission state, token
availability, and background wiring. Validate rich media, inline reply,
background delivery, and terminated launch on a physical device.
