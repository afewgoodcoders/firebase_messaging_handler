# Migrating to 2.0.0

Version 2 separates setup from user consent and token registration. Existing
`init(...)` calls remain as a compatibility path, but new applications should
use `initialize(FCMConfiguration)`.

## Required changes

1. Change the dependency constraint to `^2.0.0`.
2. Initialize Firebase before this package.
3. Call `initialize` without assuming it will prompt the user.
4. Request permission from an explanatory, user-driven screen.
5. Synchronize the token with an authenticated backend endpoint.
6. Install the v2 service worker on web and register Apple action categories
   before the first notification arrives.

```dart
final handler = FirebaseMessagingHandler.instance;

final clicks = await handler.initialize(
  FCMConfiguration(
    defaultChannelId: 'messages',
    androidChannels: const [
      NotificationChannelData(
        id: 'messages',
        name: 'Messages',
        description: 'New messages and replies',
      ),
    ],
    actionCategories: const [
      NotificationActionCategory(
        id: 'message',
        actions: [
          NotificationAction(
            id: 'reply',
            title: 'Reply',
            textInput: true,
          ),
        ],
      ),
    ],
    updateTokenCallback: registerTokenWithBackend,
  ),
);

// Invoke these after a user gesture and your own pre-permission explanation.
await handler.requestNotificationPermission();
await handler.synchronizeToken();
```

## Behavioral changes

- Permission denial no longer fails initialization. Inbox and in-app surfaces
  can continue to work.
- Provisional Apple authorization is considered usable.
- Debug logging defaults to off.
- Analytics defaults to metadata only and never emits a raw token.
- Scheduling defaults to inexact delivery. Request exact scheduling explicitly
  with `NotificationScheduleMode.exact` or `exactAllowWhileIdle`.
- `unsubscribeFromAllTopics()` no longer deletes the FCM token.
- `dispose()` removes listeners; it does not cancel visible notifications.
- Pending notification inspection returns typed
  `PendingNotificationSnapshot` values.
- Unsupported operations return false, an empty snapshot list, or a typed
  `NotificationOperationResult` instead of reporting synthetic success.
- Action, group, and thread presentation helpers now return `Future<bool>`.
  Await and check the result if your application previously ignored a
  `Future<void>`.
- Background dependencies must be initialized inside the background isolate.
  Pass a top-level `bootstrap` callback to `handleBackgroundMessage`; an
  in-memory foreground callback cannot be serialized into Android's isolate.
- `showLocalNotification(LocalNotificationRequest(...))` is the escape hatch
  for full Android, Apple, Linux, and Windows native detail objects.

## Payload migration

Adopt the versioned envelope for new sends. All values sent through FCM
`message.data` must be strings; use `NotificationEnvelope.toFcmData()` on Dart
or `encodeEnvelope()` in the reference server package.

```json
{
  "schemaVersion": "2",
  "id": "order-1042-shipped",
  "idempotencyKey": "order-1042-shipped-v1",
  "command": "display",
  "title": "Order shipped",
  "body": "Track package A-1042",
  "route": "/orders/A-1042",
  "ttlSeconds": "3600",
  "remotePresentation": "client",
  "actions": "[{\"id\":\"track\",\"title\":\"Track\"}]"
}
```

`remotePresentation: client` is the default and sends data-only content so
package preferences, quiet hours, deduplication, and expiry checks can run
before display. Use `system` when the operating system must render background
and terminated alerts; those alerts can appear before client policy runs.

On web, v2 also persists inbox items, routes in-app messages, and displays
supported actions through the active service worker. Scheduling, native detail
overrides, channel management, and app-icon badge mutation remain unsupported
browser capabilities and return an explicit unsupported result.

Legacy payloads without `schemaVersion` are still normalized, but do not gain
the envelope's validation, expiration, or command semantics.

## Platform checks

Use `getCapabilities()` at runtime before exposing platform-dependent controls.
Use `runDiagnostics()` for setup faults. Neither method replaces physical
device testing for background delivery, terminated launches, inline replies,
or OS presentation behavior.

See [Platform capabilities](platform-capabilities.md) and
[Envelope v2](features/envelope-v2.md).
