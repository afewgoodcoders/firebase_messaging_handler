# Notification envelope v2

The envelope is the contract shared by the Flutter runtime, web service worker,
JSON Schema, and TypeScript server reference.

Required fields are `schemaVersion: 2`, a stable `id`, and a `command`.
`display` and `replace` also require title/body content or localization keys.

Commands:

- `display`: present and optionally persist a new notification.
- `replace`: present with the same stable ID/tag to update an existing item.
- `cancel`: remove the matching package-managed notification.
- `markRead`: update the package inbox record.
- `silent`: run data/in-app handling without local system presentation.

Reliability fields:

- `idempotencyKey` prevents duplicate business events.
- `dedupeKey` supports campaign-level collapse when no explicit idempotency key
  exists.
- `ttlSeconds`, `sentAt`, and `expiresAt` reject stale work on the client.
- `collapseKey` maps to FCM/APNs collapse controls on the server.
- `remotePresentation` chooses `client` (the default, allowing package policy
  before display) or `system` (FCM/APNs presents background and terminated
  alerts more reliably). System presentation cannot be recalled by client
  policy before the operating system displays it.

All nested objects and arrays are JSON-encoded into strings before they enter
FCM `message.data`. The encoder rejects a data payload larger than 4096 bytes
so oversized sends fail before they reach FCM.

Validate backend payloads against
`schema/notification-envelope-v2.schema.json`, then use a unique correlation
ID per logical send. Do not put secrets or unnecessary personal content in
notification data; device logs and notification UIs are not secret stores.
