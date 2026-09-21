# Server Recipes

Lightweight backend payloads for `firebase_messaging_handler`.

For v2 production systems, use the tested [`server/`](../server/) reference
package and validate against the versioned JSON Schema. The files here are
small transport examples and do not implement authorization, App Check,
idempotency, token cleanup, scheduling, or retry policy.

This directory exists to remove guesswork for backend teams. The examples here are intentionally practical and aligned with the payload shapes the package parses today.

## Structure

- `cloud_functions/`: Firebase Admin SDK examples for Cloud Functions or Node backends
- `rest_api/`: FCM HTTP v1 examples for curl and API clients

## Payload Conventions

### System-presented notification + data

Use `notification` for system-rendered pushes and set the matching envelope
mode in `data`. This tells the client that the operating system owns background
presentation, avoiding a second package-managed alert:

```json
{
  "message": {
    "token": "<device-token>",
    "notification": {
      "title": "Order shipped",
      "body": "Track package #A-1042"
    },
    "data": {
      "deeplink": "app://orders/A-1042",
      "schemaVersion": "2",
      "id": "order-A-1042-shipped",
      "command": "display",
      "remotePresentation": "system",
      "analytics": "{\"campaign\":\"shipping_update\"}"
    }
  }
}
```

### Data-only bridge

For silent payloads that should be promoted into a local notification by the package, include at least `title` or `body` inside `data`.

Set `remotePresentation` to `client` (or omit it, because `client` is the v2
default) so package preferences, quiet hours, expiry, and deduplication can run
before presentation.

Supported optional bridge fields include:

- `channelId`
- `image`
- `deeplink`
- `templateId`
- `priority`
- `category`
- `analytics` as a JSON string map
- `actions` as a JSON string array of `{id,title,destructive?,payload?}`

### In-app trigger

For in-app rendering, send `fcmh_inapp` as a JSON string under `data`.

```json
{
  "id": "promo_2026_launch",
  "templateId": "builtin_generic",
  "trigger": "immediate",
  "content": {
    "layout": "banner",
    "title": "New feature live",
    "body": "Try the diagnostics panel today.",
    "cta_label": "Open",
    "deeplink": "app://diagnostics"
  },
  "analytics": {
    "campaignId": "launch_2026",
    "variant": "A"
  }
}
```

## Files

- [Cloud Functions examples](./cloud_functions/)
- [REST API examples](./rest_api/)

## Notes

- FCM HTTP v1 expects all `message.data` values to be strings.
- Every new send should include `schemaVersion`, a stable `id`, and `command`.
- iOS and Android delivery behavior still differs for foreground, background, and terminated states; test recipes on physical devices before rollout.
- Prefer topic sends for campaigns and token sends for transactional traffic.
