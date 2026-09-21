---
layout: page
title: Android Setup
---

# Android Setup

## Requirements

- Android API 24 or later
- Android `compileSdk` 36 or later
- Java 17

## Manifest permissions

For basic notification delivery, add:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.VIBRATE" />
```

For Android 13+, request notification permission from an explanatory user flow:

```dart
await FirebaseMessagingHandler.instance.requestNotificationPermission();
```

Inexact scheduling is the v2 default and does not need exact-alarm access. For
an exact mode, add `SCHEDULE_EXACT_ALARM`, query `getCapabilities()`, and call
`requestExactAlarmPermission()` when needed. Declare `USE_EXACT_ALARM` instead
only if the app qualifies under Google Play policy. Add
`RECEIVE_BOOT_COMPLETED` when schedules must survive reboot.

## Notification icon

Provide a monochrome notification icon and pass it into package initialization:

```dart
await FirebaseMessagingHandler.instance.initialize(
  const FCMConfiguration(
    androidNotificationIconPath: '@drawable/ic_notification',
  ),
);
```

## Gradle note

If your app uses scheduling or APIs that require Java 8+ backports, include core library desugaring as documented in the package README.
