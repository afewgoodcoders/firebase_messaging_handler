# firebase_messaging_handler

[![pub package](https://img.shields.io/pub/v/firebase_messaging_handler.svg)](https://pub.dev/packages/firebase_messaging_handler)
[![package score](https://img.shields.io/pub/points/firebase_messaging_handler)](https://pub.dev/packages/firebase_messaging_handler/score)
[![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

A practical notification layer for Flutter apps that use Firebase Cloud
Messaging.

It brings remote messages, local notifications, actions, scheduling, in-app
messages, an inbox, user preferences, delivery policy, and diagnostics behind
one API. The package is designed for apps that need more than “show a push,”
while still leaving native notification details available when you need them.

Version 2.0.0 introduces a typed notification envelope, a shared delivery
policy, runtime capability reporting, a preference center, typed delivery
events, and a reference server implementation.

## What this package covers

| Need | Package support |
| --- | --- |
| Receive FCM messages | Foreground, background, and notification-open paths |
| Show notifications | Remote, local, data-only bridge, grouped, and threaded |
| Interact without opening a screen | Action buttons and inline reply where the OS supports them |
| Deliver later | One-time and recurring local schedules |
| Control delivery | Categories, quiet hours, frequency limits, and daily caps |
| Keep a history | Persistent notification inbox with a ready-made Flutter view |
| Message inside the app | Built-in in-app layouts plus custom templates |
| Observe what happened | Typed delivery events and analytics callbacks |
| Diagnose setup | Permission, token, platform, and capability checks |
| Send safely from a backend | Versioned schema and a tested TypeScript reference server |

The package cannot override operating-system rules. Permission state, Android
channels, Apple Focus modes, browser service workers, battery policy, and
Firebase/APNs configuration still determine what a device can receive and
display.

## Contents

- [Choose the delivery path first](#choose-the-delivery-path-first)
- [Install](#install)
- [Platform setup](#platform-setup)
- [Initialize the handler](#initialize-the-handler)
- [Handle notification opens](#handle-notification-opens)
- [Tokens and topics](#tokens-and-topics)
- [Local notifications](#local-notifications)
- [Actions and inline reply](#actions-and-inline-reply)
- [Scheduling](#scheduling)
- [Groups, threads, badges, and sounds](#groups-threads-badges-and-sounds)
- [Foreground presentation](#foreground-presentation)
- [In-app messages](#in-app-messages)
- [Preferences and delivery policy](#preferences-and-delivery-policy)
- [Inbox](#inbox)
- [Delivery events and analytics](#delivery-events-and-analytics)
- [Payloads and server sending](#payloads-and-server-sending)
- [Diagnostics and capabilities](#diagnostics-and-capabilities)
- [Testing](#testing)
- [Platform support](#platform-support)
- [Troubleshooting](#troubleshooting)
- [Further documentation](#further-documentation)

## Choose the delivery path first

The most important decision is who presents a remote notification.

### System-presented remote notifications

Send an FCM `notification` payload when the alert must be presented as
reliably as the operating system allows while the app is backgrounded or
terminated. FCM/APNs owns presentation in those states.

This is the usual choice for chat messages, account alerts, and other
user-visible transactional notifications.

There is a tradeoff: client-side preferences and quiet hours cannot stop an
alert that the operating system has already displayed.

### Client-presented remote notifications

Send a data-only message when the app must evaluate package-managed categories,
quiet hours, caps, deduplication, or custom presentation before showing
anything. The package can turn a valid data message into a local notification.

Data-only delivery is best-effort when the app is not active. Android power
management, Apple background execution limits, force-stop state, and message
priority can delay or prevent it.

### Local and in-app notifications

Use local notifications for reminders produced on the device. Use in-app
messages for content that should appear only while the user is in the app.
Both paths participate in package-managed preferences and delivery policy.

For mixed products, it is normal to use all three approaches:

- system-presented remote notifications for time-sensitive alerts;
- data-only messages for policy-controlled campaigns;
- local schedules for device-owned reminders;
- in-app messages for contextual education and promotion.

## Install

Add the package:

```yaml
dependencies:
  firebase_messaging_handler: ^2.0.0
```

Then fetch packages:

```bash
flutter pub get
```

Minimum versions:

- Dart 3.10 or later
- Flutter 3.38.1 or later
- Android API 24 or later
- Android `compileSdk` 36 or later

You still need to configure Firebase in the host application. This package
does not replace `firebase_core` setup or the platform configuration files
created by FlutterFire.

## Platform setup

### Firebase

The shortest route is the FlutterFire CLI:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Initialize Firebase before initializing the notification handler:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

Keep Firebase service-account credentials on a trusted server. Never include a
service-account JSON file in a Flutter app.

### Android

Place `google-services.json` in `android/app/` and apply the Google Services
Gradle plugin as required by FlutterFire.

For basic delivery, declare:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.VIBRATE" />
```

Android 13 and later requires a runtime notification permission. Ask after
showing UI that explains why your app needs it:

```dart
final settings = await FirebaseMessagingHandler.instance
    .requestNotificationPermission();
```

Use a white-on-transparent drawable for the small notification icon:

```text
android/app/src/main/res/drawable/ic_notification.png
```

Pass it as `@drawable/ic_notification` during initialization. A launcher icon
works as a development fallback, but usually renders poorly in the status bar.

Scheduling notes:

- inexact scheduling is the default and needs no exact-alarm permission;
- add `SCHEDULE_EXACT_ALARM` only if the product genuinely needs exact timing;
- add `RECEIVE_BOOT_COMPLETED` if schedules must survive a reboot;
- `USE_EXACT_ALARM` is subject to Google Play policy and is not a general
  replacement for `SCHEDULE_EXACT_ALARM`.

Query runtime support and request exact-alarm access only when needed:

```dart
final capabilities =
    await FirebaseMessagingHandler.instance.getCapabilities();

if (capabilities.supports(NotificationCapability.exactScheduling)) {
  await FirebaseMessagingHandler.instance.requestExactAlarmPermission();
}
```

See [Android setup](doc/getting-started/android-setup.md) for the complete host
configuration.

### iOS

Add `GoogleService-Info.plist` to the Runner target, then enable:

- Push Notifications
- Background Modes → Remote notifications

Upload or connect a valid APNs authentication key in Firebase. Real remote
delivery must be tested on a physical device.

Firebase Messaging normally uses AppDelegate method swizzling to map APNs
tokens and notification callbacks. Leave `FirebaseAppDelegateProxyEnabled`
enabled unless the host app implements Firebase’s complete manual forwarding.

Rich images in remote notifications require an app-owned Notification Service
Extension and `mutable-content: 1`. A starting template is included at
[ios/NotificationServiceExtension.template.swift](ios/NotificationServiceExtension.template.swift).

Register Apple action categories during package initialization so their actions
exist before a notification arrives.

See [iOS setup](doc/getting-started/ios-setup.md).

### macOS

Add the Firebase macOS configuration to the host target and enable the
appropriate signing, notification, and background capabilities. Local
notifications, schedules, actions, inbox, policy, and in-app presentation are
available. Remote delivery depends on the host’s Firebase/APNs configuration
and should be verified on the target you ship.

See [macOS setup](doc/getting-started/macos-setup.md).

### Web

Configure Firebase for the Flutter web app, then copy
[web/firebase-messaging-sw.template.js](web/firebase-messaging-sw.template.js)
to the deployed app as `firebase-messaging-sw.js`. Fill in the public Firebase
configuration and register the worker at the scope that controls the app.

Pass your public Web Push certificate as `webVapidKey`. Browser permission and
token creation should be started from a user gesture:

```dart
await FirebaseMessagingHandler.instance.requestNotificationPermission();
await FirebaseMessagingHandler.instance.synchronizeToken();
```

Web supports remote delivery and worker action messages. Durable local
scheduling and inline notification reply are not portable browser features.

See [web setup](doc/getting-started/web-setup.md).

### Windows and Linux

Windows and Linux operate in desktop local mode. You can use local
presentation, inbox, preferences, delivery policy, in-app templates, and the
local scheduling features reported at runtime. FlutterFire FCM token and topic
APIs are not available on these targets.

Windows local notifications require an application identity. Supply
`WindowsNotificationOptions` during initialization and follow the host setup
required by `flutter_local_notifications`.

See [desktop setup](doc/getting-started/desktop-setup.md).

## Initialize the handler

Use one shared handler instance. Initialization returns a broadcast stream of
notification-open data:

```dart
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

final navigatorKey = GlobalKey<NavigatorState>();
StreamSubscription<NotificationData?>? notificationOpenSubscription;

Future<void> configureNotifications() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final handler = FirebaseMessagingHandler.instance;

  final openStream = await handler.initialize(
    FCMConfiguration(
      webVapidKey: const String.fromEnvironment('WEB_VAPID_KEY'),
      androidNotificationIconPath: '@drawable/ic_notification',
      defaultChannelId: 'general',
      androidChannels: [
        NotificationChannelData(
          id: 'general',
          name: 'General',
          description: 'General app notifications',
          importance: NotificationImportanceEnum.high,
          priority: NotificationPriorityEnum.high,
        ),
      ],
      notificationCategories: const [
        NotificationCategory(
          id: 'messages',
          name: 'Messages',
          description: 'New messages and replies',
        ),
        NotificationCategory(
          id: 'product_updates',
          name: 'Product updates',
          defaultEnabled: true,
        ),
      ],
      deliveryPolicy: const NotificationDeliveryPolicy(
        quietHours: NotificationQuietHours(
          startHour: 22,
          endHour: 7,
        ),
        perCategoryInterval: Duration(minutes: 2),
        globalDailyCap: 20,
      ),
      updateTokenCallback: uploadTokenToYourBackend,
      enableDefaultDataOnlyBridge: true,
      dataOnlyBridgeChannelId: 'general',
      enableDebugLogging: false,
    ),
  );

  handler.setInAppNavigatorKey(navigatorKey);

  notificationOpenSubscription = openStream?.listen((data) {
    if (data != null) {
      routeFromNotification(data);
    }
  });
}

Future<bool> uploadTokenToYourBackend(String token) async {
  // Associate the token with the signed-in installation on your server.
  return true;
}

void routeFromNotification(NotificationData data) {
  final route = data.payload['route'] as String?;
  if (route != null) {
    navigatorKey.currentState?.pushNamed(route, arguments: data.payload);
  }
}
```

`FCMConfiguration` deliberately does not request permission or synchronize a
token by default. This lets the app choose the right moment for its permission
prompt—especially on the web, where the call needs a user gesture.

After the user opts in:

```dart
final settings = await FirebaseMessagingHandler.instance
    .requestNotificationPermission(
      options: const NotificationPermissionOptions(
        alert: true,
        badge: true,
        sound: true,
      ),
    );

await FirebaseMessagingHandler.instance.synchronizeToken();
```

If a simple app intentionally wants those side effects during startup, set
`requestPermissionOnInitialize` and `synchronizeTokenOnInitialize` to `true`.
For new code, prefer `initialize(FCMConfiguration)` over the older `init(...)`
convenience method.

Dispose long-lived listeners when their owner is disposed:

```dart
await notificationOpenSubscription?.cancel();
await FirebaseMessagingHandler.instance.dispose();
```

### Background processing

Register a top-level background entry point before `runApp`:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FirebaseMessagingHandler.instance.configureBackgroundMessageHandler(
    appNotificationBackgroundHandler,
  );

  runApp(const App());
}

@pragma('vm:entry-point')
Future<void> appNotificationBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  await FirebaseMessagingHandler.handleBackgroundMessage(message);

  // Do short, isolate-safe work here if your app needs it.
}
```

The callback must be top-level or static. On Android it can run in another
isolate, so it must not depend on widget state or closures created in the main
isolate.

If background work needs custom service setup, provide the same top-level
bootstrap function to `handleBackgroundMessage`:

```dart
@pragma('vm:entry-point')
Future<void> initializeBackgroundDependencies() async {
  // Initialize only the services needed by background processing.
}

@pragma('vm:entry-point')
Future<void> appNotificationBackgroundHandler(RemoteMessage message) async {
  await FirebaseMessagingHandler.handleBackgroundMessage(
    message,
    bootstrap: initializeBackgroundDependencies,
  );
}
```

You can also run application work after the package hydrates its background
queues:

```dart
await FirebaseMessagingHandler.instance
    .configureBackgroundProcessingCallback((message) async {
      await processBusinessEvent(message.data);
      return true; // false asks the package to queue the message for retry.
    });
```

Keep background handlers short. The operating system owns their execution
window.

## Handle notification opens

The stream returned by `initialize` is the main route for notification taps.
When `includeInitialNotificationInStream` is true (the default), it also
includes the notification that launched a terminated app.

If your architecture handles cold starts separately, turn that option off and
read the initial item explicitly:

```dart
final initial = await FirebaseMessagingHandler.checkInitial();
if (initial != null) {
  routeFromNotification(initial);
}
```

`NotificationData` includes the application payload, title, body, image,
category, actions, message ID, lifecycle-derived type, and whether it came from
a terminated launch.

For message processing that should be consistent across foreground,
background, resume, and initial delivery, register a unified handler:

```dart
await FirebaseMessagingHandler.instance.setUnifiedMessageHandler(
  (message, lifecycle) async {
    if (message.data['kind'] == 'sync_only') {
      await synchronizeRecord(message.data['recordId']);
      return true;
    }

    return false; // Continue through normal package presentation.
  },
);
```

Use the notification-open stream for navigation. Use the unified handler for
business processing. Keeping those jobs separate avoids trying to navigate from
a background isolate.

## Tokens and topics

Fetch and upload the current registration token:

```dart
final token = await FirebaseMessagingHandler.instance.getFcmToken();

if (token == null) {
  debugPrint(FirebaseMessagingHandler.instance.lastTokenError);
}

await FirebaseMessagingHandler.instance.synchronizeToken();
```

When `updateTokenCallback` is configured, the package also listens for token
refreshes. Your backend should treat tokens as rotating installation
identifiers, not permanent user IDs:

- associate a token with the authenticated installation;
- update the association when the token rotates;
- remove it on sign-out or when FCM reports the token is stale;
- never log full tokens in production analytics.

Topic subscriptions are tracked locally so they can be inspected and removed:

```dart
await FirebaseMessagingHandler.instance.subscribeToTopic('release_notes');

final topics =
    await FirebaseMessagingHandler.instance.getSubscribedTopics();

await FirebaseMessagingHandler.instance
    .unsubscribeFromTopic('release_notes');

await FirebaseMessagingHandler.instance.unsubscribeFromAllTopics();
```

Use topics for broad, non-sensitive segments. Enforce authorization on your
server for private or user-specific messages.

## Local notifications

For a simple local notification with action buttons, use
`showNotificationWithActions`. For native styles and full control, use the
typed `LocalNotificationRequest`:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final result = await FirebaseMessagingHandler.instance.showLocalNotification(
  const LocalNotificationRequest(
    id: 42,
    title: 'Upload complete',
    body: 'Your report is ready to review.',
    channelId: 'general',
    category: 'product_updates',
    payload: {
      'route': '/reports/42',
      'reportId': '42',
    },
    androidDetails: AndroidNotificationDetails(
      'general',
      'General',
      channelDescription: 'General app notifications',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(
        'The quarterly report finished uploading and is ready to review.',
      ),
    ),
    appleDetails: DarwinNotificationDetails(
      threadIdentifier: 'reports',
    ),
  ),
);

if (!result.isSuccess) {
  debugPrint('Notification failed: ${result.errorCode} ${result.message}');
}
```

The native detail fields are intentional escape hatches. They expose upstream
Android, Apple, Linux, and Windows options for big picture, inbox, messaging,
media, progress, call layouts, attachments, interruption levels, relevance,
full-screen intents, and other platform-specific presentation.

Before exposing a feature in UI, query `getCapabilities()`. Unsupported
operations return typed errors instead of pretending to succeed.

## Actions and inline reply

Define stable action IDs and route them from the package’s click and delivery
event streams:

```dart
final shown = await FirebaseMessagingHandler.instance
    .showNotificationWithActions(
      title: 'New message from Priya',
      body: 'Are we still meeting at 3?',
      channelId: 'general',
      actionCategoryId: 'message_actions',
      payload: const {
        'route': '/messages/123',
        'conversationId': '123',
      },
      actions: const [
        NotificationAction(
          id: 'reply',
          title: 'Reply',
          textInput: true,
          inputLabel: 'Write a reply',
          inputButtonTitle: 'Send',
          inputChoices: ['Yes', 'No', 'In 10 minutes'],
        ),
        NotificationAction(
          id: 'mark_read',
          title: 'Mark as read',
          foreground: false,
        ),
      ],
    );
```

Apple action categories must be registered during initialization:

```dart
const messageActions = NotificationActionCategory(
  id: 'message_actions',
  actions: [
    NotificationAction(
      id: 'reply',
      title: 'Reply',
      textInput: true,
      inputLabel: 'Write a reply',
      inputButtonTitle: 'Send',
    ),
    NotificationAction(
      id: 'mark_read',
      title: 'Mark as read',
      foreground: false,
    ),
  ],
);

await FirebaseMessagingHandler.instance.initialize(
  const FCMConfiguration(
    actionCategories: [messageActions],
  ),
);
```

Action behavior varies by platform. Inline reply is available on Android and
Apple platforms; it is not a portable web feature. Check
`NotificationCapability.inlineReply` before advertising it.

## Scheduling

Schedule a one-time reminder:

```dart
final scheduled = await FirebaseMessagingHandler.instance.scheduleNotification(
  id: 1001,
  title: 'Stand-up in 10 minutes',
  body: 'Open the agenda before the call.',
  scheduledDate: DateTime.now().add(const Duration(minutes: 10)),
  channelId: 'general',
  payload: const {'route': '/meetings/daily'},
);
```

Inexact delivery is the safest default for general reminders. Ask for exact
alarm access only when the product requirement justifies it:

```dart
final allowed = await FirebaseMessagingHandler.instance
    .requestExactAlarmPermission();

if (allowed) {
  await FirebaseMessagingHandler.instance.scheduleNotification(
    id: 1002,
    title: 'Medication',
    body: 'It is time for your scheduled dose.',
    scheduledDate: nextDose,
    scheduleMode: NotificationScheduleMode.exactAllowWhileIdle,
    fallbackToInexact: true,
  );
}
```

Recurring and weekly schedules are also available:

```dart
await FirebaseMessagingHandler.instance.scheduleRecurringNotification(
  id: 2001,
  title: 'Daily check-in',
  body: 'How are you feeling today?',
  repeatInterval: 'daily',
  hour: 9,
  minute: 0,
);

await FirebaseMessagingHandler.instance.scheduleWeeklyNotification(
  id: 2002,
  title: 'Weekly summary',
  body: 'Your summary is ready.',
  weekday: DateTime.monday,
  hour: 8,
  minute: 30,
);
```

Inspect and cancel pending work:

```dart
final pending =
    await FirebaseMessagingHandler.instance.getPendingNotifications();

await FirebaseMessagingHandler.instance.cancelScheduledNotification(1001);
await FirebaseMessagingHandler.instance.cancelAllScheduledNotifications();
```

Refresh the package timezone after the app resumes if users may travel or
change the system timezone:

```dart
await FirebaseMessagingHandler.instance.refreshLocalTimezone();
```

Local scheduling support is platform-dependent. Web does not provide durable
package scheduling, and desktop support follows the capabilities reported by
the underlying platform implementation.

## Groups, threads, badges, and sounds

### Android groups

```dart
await FirebaseMessagingHandler.instance.showGroupedNotification(
  title: 'Build finished',
  body: 'Android release build completed.',
  groupKey: 'builds',
  groupTitle: 'Build activity',
  channelId: 'general',
);

await FirebaseMessagingHandler.instance.showGroupedNotification(
  title: '2 build updates',
  body: 'Open to see recent build activity.',
  groupKey: 'builds',
  groupTitle: 'Build activity',
  channelId: 'general',
  isSummary: true,
);
```

`createNotificationGroup` can build a group from multiple
`NotificationData` values. Use `dismissNotificationGroup` to remove the
package-managed group where the platform supports it.

### Apple threads

```dart
await FirebaseMessagingHandler.instance.showThreadedNotification(
  title: 'Mina',
  body: 'I added the final screenshots.',
  threadIdentifier: 'conversation-123',
  payload: const {'route': '/messages/123'},
);
```

### Badges

Direct app-icon badge mutation is currently implemented by the package’s iOS
bridge:

```dart
await FirebaseMessagingHandler.instance.setIOSBadgeCount(5);
final count = await FirebaseMessagingHandler.instance.getIOSBadgeCount();
await FirebaseMessagingHandler.instance.clearBadgeCount();
```

Android launchers own badge behavior and do not expose one consistent direct
mutation API. The retained Android badge methods return no useful value unless
the runtime reports support. Query capabilities before showing a badge
control.

### Custom sounds

Create an Android channel with a raw resource sound:

```dart
await FirebaseMessagingHandler.instance.createCustomSoundChannel(
  channelId: 'urgent',
  channelName: 'Urgent alerts',
  channelDescription: 'Alerts that require prompt attention',
  soundFileName: 'urgent_alert',
  importance: NotificationImportanceEnum.max,
  priority: NotificationPriorityEnum.max,
);
```

Place Android audio under `android/app/src/main/res/raw/` and refer to it
without the extension. Add Apple sounds to the app target and use the complete
resource name. Sound choices are affected by user settings, Focus/Do Not
Disturb, and the immutable behavior of existing Android channels.

## Foreground presentation

When a remote message arrives while the app is active, the package can create a
local presentation. Override the defaults globally or per message:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

FirebaseMessagingHandler.instance.setForegroundNotificationOptions(
  ForegroundNotificationOptions(
    androidBuilder: (context) {
      final image = context.data['imageUrl'] as String?;

      return AndroidNotificationDetails(
        'general',
        'General',
        channelDescription: 'General app notifications',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: image == null
            ? null
            : BigTextStyleInformation(context.body ?? ''),
      );
    },
    iosDefaults: const DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    ),
  ),
);
```

Set `enabled: false` when the app should consume foreground messages without
automatic local presentation.

## In-app messages

An in-app message is carried in an FCM data value named `fcmh_inapp` (the
legacy `in_app_payload` name is also accepted). The value must be a JSON
string, because FCM HTTP v1 data values are strings.

Start by giving the presenter a navigator key and registering a template:

```dart
final navigatorKey = GlobalKey<NavigatorState>();

FirebaseMessagingHandler.instance.setInAppNavigatorKey(navigatorKey);

FirebaseMessagingHandler.instance.registerInAppNotificationTemplates({
  'builtin_generic': BuiltInInAppTemplates.generic(
    onAction: (actionId, data) {
      debugPrint('In-app action $actionId for message ${data.id}');
    },
  ),
});
```

Use the same key in your application:

```dart
MaterialApp(
  navigatorKey: navigatorKey,
  home: const HomeScreen(),
);
```

The built-in generic template reads its layout and content from the payload. It
supports dialog, full-screen, banner, bottom sheet, snackbar, and carousel
presentation, with configurable text, HTML, images, colors, buttons, and
auto-dismiss behavior.

You can observe every ready in-app message independently of rendering:

```dart
final subscription = FirebaseMessagingHandler.instance
    .getInAppNotificationStream()
    .listen((data) {
      debugPrint('Template: ${data.templateId}');
      debugPrint('Content: ${data.content}');
    });
```

For an app-owned layout, register a custom template:

```dart
FirebaseMessagingHandler.instance.registerInAppNotificationTemplates({
  'trial_ending': InAppNotificationTemplate(
    id: 'trial_ending',
    description: 'Shown shortly before a trial expires',
    barrierDismissible: true,
    onDisplay: (data) async {
      final daysLeft = data.content['daysLeft'];
      final planName = data.content['planName'];

      await InAppTemplatePresenter.instance.showBottomSheet<void>(
        builder: (context) {
          return TrialEndingSheet(
            planName: planName?.toString() ?? '',
            daysLeft: int.tryParse(daysLeft?.toString() ?? '') ?? 0,
            rawPayload: data.rawPayload,
          );
        },
      );
    },
  ),
});
```

`InAppNotificationData` exposes:

- `id` and `templateId`;
- `triggerType`;
- decoded `content`;
- analytics metadata;
- the original decoded payload in `rawPayload`;
- `receivedAt`.

Messages with `nextForeground` or `appLaunch` triggers are persisted until
they can be delivered. You can manage that queue explicitly:

```dart
await FirebaseMessagingHandler.instance.flushPendingInAppNotifications();
await FirebaseMessagingHandler.instance
    .clearPendingInAppNotifications(id: 'campaign-42');
```

Use `setInAppFallbackDisplayHandler` if the backend may send template IDs that
are not registered by this app version.

## Preferences and delivery policy

Categories give users understandable controls instead of one all-or-nothing
switch. Define them in `FCMConfiguration.notificationCategories`, then embed
the ready-made preference screen:

```dart
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: NotificationPreferenceCenter(
        controller:
            FirebaseMessagingHandler.instance.notificationPreferences,
      ),
    );
  }
}
```

The controller persists:

- a global package-managed notification switch;
- per-category delivery;
- per-category sound;
- per-category badge updates;
- user-selected quiet hours.

You can build your own UI against the same controller:

```dart
final preferences =
    FirebaseMessagingHandler.instance.notificationPreferences;

await preferences.setCategoryEnabled('product_updates', false);
await preferences.setCategorySoundEnabled('messages', true);
await preferences.setQuietHours(
  const NotificationQuietHours(startHour: 23, endHour: 7),
);
```

The shared `NotificationDeliveryPolicy` adds app defaults and frequency
limits:

```dart
const policy = NotificationDeliveryPolicy(
  quietHours: NotificationQuietHours(
    startHour: 22,
    startMinute: 30,
    endHour: 7,
  ),
  globalInterval: Duration(seconds: 30),
  perCategoryInterval: Duration(minutes: 5),
  globalDailyCap: 30,
  perCategoryDailyCap: 8,
);
```

The policy is applied to package-managed push, local, in-app, and inbox
surfaces. A user’s saved quiet hours override the app default. Delivery
decisions are restored from durable state so deduplication and caps are not
reset every time the process restarts.

There is one important boundary: a system-presented FCM/APNs notification is
already visible before Dart can apply client policy. Use client presentation
when pre-display suppression is a hard requirement, and accept the
background-delivery tradeoff described earlier.

For different persistence or encrypted storage, implement
`NotificationPreferencesRepository` and/or `NotificationStateStore` and pass
them in `FCMConfiguration`.

## Inbox

When `saveNotificationsToStorage` is enabled (the default), package-managed
notifications can be retained in a local inbox. The default store uses
`SharedPreferences` and keeps up to `maxStoredNotifications` entries.

Add the ready-made view:

```dart
class InboxScreen extends StatelessWidget {
  InboxScreen({super.key});

  final InboxStorageService storage = InboxStorageService(maxItems: 100);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: NotificationInboxView(
        storage: storage,
        pageSize: 20,
        onItemTap: (item) {
          final route = item.data['route'];
          if (route is String) {
            Navigator.of(context).pushNamed(route);
          }
        },
        onActionTap: (actionId, item) {
          debugPrint('Inbox action $actionId for ${item.id}');
        },
      ),
    );
  }
}
```

`NotificationInboxView` includes paging, pull-to-refresh, mark-as-read, action
chips, optional swipe-to-delete, and theming hooks. For a database or synced
inbox, implement `NotificationInboxStorageInterface`.

The built-in storage API can also be used directly:

```dart
final storage = InboxStorageService();
final unread = await storage.count(unreadOnly: true);
final firstPage = await storage.fetch(page: 0, pageSize: 20);
await storage.markRead(['message-123']);
```

## Delivery events and analytics

`deliveryEvents` is the operational stream. It reports when a message is:

- received, delivered, or scheduled;
- suppressed or deferred;
- opened, dismissed, or acted on;
- expired or deduplicated;
- cancelled or processed as a non-display command;
- failed.

```dart
final eventSubscription =
    FirebaseMessagingHandler.instance.deliveryEvents.listen((event) {
      debugPrint(
        '${event.type.name} ${event.surface.name} '
        'message=${event.messageId} reason=${event.reason}',
      );

      if (event.type == NotificationDeliveryEventType.actionSelected) {
        handleAction(
          event.actionId,
          input: event.actionInput,
          data: event.data,
        );
      }
    });
```

The older analytics callback remains useful when integrating a generic
analytics provider:

```dart
await FirebaseMessagingHandler.instance.initialize(
  FCMConfiguration(
    analyticsOptions: const NotificationAnalyticsOptions(
      privacy: NotificationAnalyticsPrivacy.metadataOnly,
    ),
    analyticsCallback: (event, data) {
      analytics.track(event, properties: data);
    },
  ),
);
```

`metadataOnly` is the default and avoids exporting notification content.
Choose `fullPayload` only when you have a clear consent and data-governance
reason. Choose `disabled` to suppress package analytics callbacks.

Delivery events describe what the client pipeline observed. They are not a
guarantee that a person saw or read a notification.

## Payloads and server sending

### The string-only FCM rule

Every value in FCM HTTP v1 `message.data` must be a string. Encode lists,
objects, booleans, and numbers as JSON strings. The v2 envelope helpers do this
for you and reject data payloads larger than 4096 bytes.

```dart
final envelope = NotificationEnvelope(
  id: 'order-7821-shipped',
  idempotencyKey: 'order-7821-shipped-v1',
  title: 'Order shipped',
  body: 'Order #7821 is on the way.',
  category: 'orders',
  route: '/orders/7821',
  channelId: 'general',
  timeToLive: const Duration(days: 2),
  sentAt: DateTime.now().toUtc(),
  data: const {
    'orderId': '7821',
    'carrier': 'Example Express',
  },
);

final Map<String, String> fcmData = envelope.toFcmData();
```

The same envelope contract is implemented in:

- [schema/notification-envelope-v2.schema.json](schema/notification-envelope-v2.schema.json)
- [server/src/envelope.ts](server/src/envelope.ts)
- the Flutter runtime
- the web service-worker template

Its commands are:

| Command | Client behavior |
| --- | --- |
| `display` | Present and optionally store a notification |
| `replace` | Update a stable notification ID/tag |
| `cancel` | Remove matching package-managed presentation |
| `markRead` | Mark a matching inbox record as read |
| `silent` | Process data without system presentation |

Reliability fields include an idempotency key, dedupe key, TTL, absolute
expiry, collapse key, priority, and explicit client-vs-system remote
presentation.

### System-presented HTTP v1 example

Use this shape when FCM/APNs should display the alert in background and
terminated states:

```json
{
  "message": {
    "token": "DEVICE_FCM_TOKEN",
    "notification": {
      "title": "Payment received",
      "body": "Your receipt is ready."
    },
    "data": {
      "schemaVersion": "2",
      "id": "receipt-90210",
      "idempotencyKey": "receipt-90210-v1",
      "command": "display",
      "remotePresentation": "system",
      "category": "billing",
      "route": "/receipts/90210",
      "storeInInbox": "true",
      "data": "{\"receiptId\":\"90210\"}"
    },
    "android": {
      "priority": "high",
      "notification": {
        "channel_id": "general"
      }
    },
    "apns": {
      "payload": {
        "aps": {
          "sound": "default"
        }
      }
    }
  }
}
```

### Client-presented data-only example

Use this shape when the package should evaluate preferences and policy before
showing a local notification:

```json
{
  "message": {
    "token": "DEVICE_FCM_TOKEN",
    "data": {
      "schemaVersion": "2",
      "id": "campaign-2026-09-21-a",
      "idempotencyKey": "campaign-2026-09-21-a",
      "command": "display",
      "title": "A quieter way to catch up",
      "body": "Your weekly summary is ready.",
      "remotePresentation": "client",
      "category": "product_updates",
      "channelId": "general",
      "route": "/weekly-summary",
      "ttlSeconds": "86400",
      "storeInInbox": "true",
      "presentInApp": "false",
      "data": "{\"summaryId\":\"week-38\"}"
    },
    "android": {
      "priority": "high",
      "ttl": "86400s"
    },
    "apns": {
      "headers": {
        "apns-push-type": "background",
        "apns-priority": "5"
      },
      "payload": {
        "aps": {
          "content-available": 1
        }
      }
    }
  }
}
```

The APNs `aps` object is not inside `message.data`, so its numeric value is
valid there. Data-only Apple delivery is still best-effort and should not be
used for an alert that must always be presented promptly.

### In-app message example

`fcmh_inapp` is a JSON-encoded string:

```json
{
  "message": {
    "token": "DEVICE_FCM_TOKEN",
    "data": {
      "fcmh_inapp": "{\"id\":\"welcome-2\",\"templateId\":\"builtin_generic\",\"trigger\":\"immediate\",\"category\":\"product_updates\",\"content\":{\"layout\":\"bottom_sheet\",\"title\":\"Welcome\",\"body\":\"Here are the two things worth knowing.\",\"buttons\":[{\"id\":\"continue\",\"label\":\"Continue\",\"style\":\"filled\"}]},\"analytics\":{\"campaign_id\":\"onboarding-2026\"}}"
    }
  }
}
```

Supported in-app trigger values are `immediate`, `next_foreground`,
`app_launch`, and `custom`.

### Reference server

The [server package](server/README.md) is a tested TypeScript reference for
Node 22.6 and the FCM HTTP v1 API. It includes:

- envelope validation and payload preview;
- installation, user, topic, and condition targeting;
- batches, bounded concurrency, retry/backoff, and `Retry-After` handling;
- token metadata and stale-token cleanup;
- idempotency claims, scheduled jobs, cancellation, and dead letters;
- authorization and optional App Check boundaries;
- structured audit events.

Its stores are in-memory reference implementations. Replace token,
idempotency, job, and event stores with durable production adapters. Use
Application Default Credentials or workload identity rather than distributing
service-account key files.

## Diagnostics and capabilities

Use diagnostics when setting up a device or responding to a support report:

```dart
final result =
    await FirebaseMessagingHandler.instance.runDiagnostics();

debugPrint('Platform: ${result.platform}');
debugPrint('Permission: ${result.authorizationStatus}');
debugPrint('Token available: ${result.fcmTokenAvailable}');
debugPrint('Pending schedules: ${result.pendingNotificationCount}');

for (final recommendation in result.recommendations) {
  debugPrint(recommendation);
}
```

The permission wizard returns a structured summary for Android, Apple, web, or
desktop-local mode:

```dart
final permissionResult =
    await FirebaseMessagingHandler.instance.requestPermissionsWizard();
debugPrint(permissionResult.overallStatus);
```

Capabilities answer a different question: whether a feature is supported in
the current runtime and whether it still needs host setup.

```dart
final capabilities =
    await FirebaseMessagingHandler.instance.getCapabilities();

for (final capability in NotificationCapability.values) {
  final status = capabilities[capability];
  debugPrint(
    '${capability.name}: ${status.supported} '
    'setup=${status.requiresSetup} reason=${status.reason}',
  );
}
```

Use the capability matrix to hide or explain unavailable controls. Use
diagnostics to find configuration problems. Neither replaces a physical-device
test for background delivery, notification actions, or terminated launches.

## Testing

### Fast package tests

Run analysis and the local suite from the package root:

```bash
flutter analyze
flutter test
(cd server && npm test)
```

[test/handlers_integration_test.dart](test/handlers_integration_test.dart)
exercises lifecycle and click handling with synthetic `RemoteMessage` values.
It does not need Firebase credentials or a device:

```bash
flutter test test/handlers_integration_test.dart
```

The public test-mode helpers can drive host-app widget tests without Firebase:

```dart
setUp(() {
  FirebaseMessagingHandler.setTestMode(true);
});

tearDown(() {
  FirebaseMessagingHandler.setTestMode(false);
});

test('routes a notification click', () async {
  final stream = FirebaseMessagingHandler.getMockClickStream()!;

  FirebaseMessagingHandler.addMockClickEvent(
    FirebaseMessagingHandler.createMockNotificationData(
      title: 'Test',
      payload: const {'route': '/test'},
    ),
  );

  final data = await stream.first;
  expect(data.payload['route'], '/test');
});
```

These helpers are for tests only; they do not affect production handling until
test mode is enabled.

### Device tests

Device-deployable tests live in `example/` because the package root is a
plugin, not an application runner.

The comprehensive suite can run without send credentials, but skips real-send
cases. With the repository’s test Firebase project configured:

```bash
cd example
FCM_CREDENTIALS=$(base64 -i ../test/firebase_config/service_account.json | tr -d '\n')

flutter test integration_test/comprehensive_test.dart \
  --dart-define=FCM_TEST_SENDER_ID=<firebase-project-number> \
  --dart-define=FCM_SERVICE_ACCOUNT_B64=$FCM_CREDENTIALS \
  --device-id <device-id>
```

The focused real-push suite retrieves the device token, sends through FCM HTTP
v1, and asserts the client result:

```bash
flutter test integration_test/real_push_test.dart \
  --dart-define=FCM_TEST_SENDER_ID=<firebase-project-number> \
  --dart-define=FCM_SERVICE_ACCOUNT_B64=$FCM_CREDENTIALS \
  --device-id <device-id>
```

Android tray actions, background data bridging, notification taps, and a
killed-process launch have a dedicated ADB harness:

```bash
bash test/firebase_config/android_lifecycle_e2e.sh \
  --device <adb-device-id> \
  --key-file test/firebase_config/service_account.json
```

Credentials under `test/firebase_config/` are gitignored. Never commit them.
See [the integration-test guide](integration_test/README.md) for iOS driver,
permission, and manual cold-start instructions.

### Release checks

Before publishing:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
(cd server && npm test)
flutter pub publish --dry-run
pana --flutter-sdk /path/to/flutter .
```

The full release procedure is in
[doc/release-checklist.md](doc/release-checklist.md).

## Platform support

This table describes package-owned behavior. Actual delivery also depends on
Firebase/APNs credentials, user permission, network state, browser setup, and
operating-system policy.

| Capability | Android | iOS | Web | macOS | Windows | Linux |
| --- | --- | --- | --- | --- | --- | --- |
| FCM remote delivery | Yes | Yes | Yes | Firebase-dependent | No | No |
| Foreground local presentation | Yes | Yes | Browser API | Yes | Yes, with toast identity | Yes |
| One-time scheduling | Yes | Yes | No | Yes | Runtime-dependent | No package guarantee |
| Recurring scheduling | Yes | Yes | No | Yes | No package guarantee | No package guarantee |
| Exact schedule control | Permission-gated | OS-managed | No | OS-managed | No | No |
| Notification actions | Yes | Registered categories | Service worker | Registered categories | Upstream-dependent | Upstream-dependent |
| Inline reply | Yes | Yes | No | Yes | Upstream-dependent | No guarantee |
| Direct app-icon badge mutation | No | Yes | No | No | No | No |
| Groups or threads | Groups | Threads | Tag replacement | Threads | Upstream-dependent | Upstream-dependent |
| Inbox, preferences, policy | Yes | Yes | Yes | Yes | Yes | Yes |
| FCM topics | Yes | Yes | Yes | Firebase-dependent | No | No |
| Delivery-metrics toggle | Android SDK | Native hook required | Worker setup required | Native setup | No | No |

Call `getCapabilities()` for the current runtime rather than hard-coding this
table into product logic. See
[the detailed capability notes](doc/platform-capabilities.md).

## Troubleshooting

### A notification never arrives

Work from the outside in:

1. Run `runDiagnostics()` and inspect every recommendation.
2. Confirm the token belongs to this Firebase project and current app install.
3. Check Firebase credentials, application ID/bundle ID, and platform config
   files.
4. Check notification permission and Android channel settings.
5. Send a minimal system-presented notification from the Firebase Console.
6. Test the exact HTTP v1 payload on a physical device.
7. If it is data-only, check OS background restrictions and message priority.

Android force-stop prevents delivery until the user opens the app again. Apple
data-only delivery is best-effort. Neither behavior can be bypassed by a
Flutter package.

### Foreground messages arrive but no banner appears

The app is responsible for foreground presentation. Confirm
`enableForegroundMessageHandling` is true and
`ForegroundNotificationOptions.enabled` has not been disabled. On Android,
check the channel’s importance. On Apple platforms, check permission and the
configured Darwin presentation details.

### Android shows a silent or low-priority notification

Android channel settings are persistent. Once a user or app creates a channel,
changing its importance or sound in Dart does not rewrite the existing system
channel. Use a new channel ID for materially different behavior, or ask the
user to change the existing channel in system settings.

Also verify that:

- the small icon resource exists;
- the payload names the expected channel;
- the channel was created before the notification;
- device-level sound, vibration, and Do Not Disturb settings allow it.

### Scheduling does not fire

Check that the scheduled time is in the future and notification permission is
available. Use inexact scheduling unless exact timing is a product
requirement. For exact Android schedules, declare the appropriate permission,
query capabilities, and call `requestExactAlarmPermission()`. Add reboot
support in the host manifest when schedules must survive a restart.

After timezone changes, call `refreshLocalTimezone()` and reschedule reminders
whose intended local wall-clock time changed.

### iOS reports that an APNs token is unavailable

Confirm the Push Notifications capability, Background Modes configuration,
bundle ID, provisioning profile, APNs key in Firebase, and a physical-device
run. Leave Firebase AppDelegate proxying enabled unless you have implemented
all required delegate forwarding yourself.

### A custom sound does not play

Check the resource location and filename, then check system settings. On
Android, sound belongs to the channel and an existing channel keeps its
original sound. On Apple platforms, ensure the sound is part of the app target
and the payload uses the correct complete filename.

### Web works only while the page is open

Inspect service-worker registration, scope, Firebase config, VAPID key, browser
permission, HTTPS deployment, and the browser console. A worker outside the
Flutter app’s controlling scope cannot handle background messages for it.

### Actions appear on one platform but not another

Register Apple action categories at initialization. On Android, ensure the
notification is client-presented when package-defined actions are required.
On web, implement the worker click/action bridge. Always check capabilities
before showing an inline-reply feature.

### Turn on package logs

Set `enableDebugLogging: true` while diagnosing a development device. Do not
leave verbose payload logging enabled in production.

## Further documentation

- [Documentation index](doc/index.md)
- [Migrating to 2.0.0](doc/v2-migration.md)
- [Notification envelope v2](doc/features/envelope-v2.md)
- [Server recipes](doc/features/server-recipes.md)
- [Android setup](doc/getting-started/android-setup.md)
- [iOS setup](doc/getting-started/ios-setup.md)
- [Web setup](doc/getting-started/web-setup.md)
- [Desktop setup](doc/getting-started/desktop-setup.md)
- [Example application](example/README.md)
- [Changelog](CHANGELOG.md)

## Contributing

Issues and pull requests are welcome at
[github.com/afewgoodcoders/firebase_messaging_handler](https://github.com/afewgoodcoders/firebase_messaging_handler).

For a local checkout:

```bash
flutter pub get
flutter analyze
flutter test
(cd server && npm test)
```

Please include tests for behavior changes and avoid committing Firebase
credentials, tokens, generated build output, or private notification payloads.

## License

BSD 3-Clause. See [LICENSE](LICENSE).

Maintained by [A Few Good Coders](https://afewgoodcoders.com).
