# v2 reference notification server

This zero-runtime-dependency TypeScript package is a production reference for
the server half of `firebase_messaging_handler` 2.0.0. It targets Node 22.6+
and talks directly to the FCM HTTP v1 API.

It includes:

- envelope validation, preview, and string-only FCM encoding
- explicit client-vs-system remote presentation, including safe APNs defaults
- installation/user/topic/condition targeting
- token metadata and stale-token pruning
- idempotency claims, batches of at most 500 targets, correlation IDs, and
  transient retry with Retry-After plus jitter
- scheduling, cancellation, bounded retry, and dead-letter handling
- bearer-role and optional App Check authorization boundary
- audit/event sink without a required logging vendor

Run tests with `npm test`.

## Production adapters required

The in-memory stores are test and local-development implementations. Replace
them with durable adapters before deployment:

- `TokenRegistry`: indexed by installation ID, user ID, and token; encrypt
  tokens at rest and restrict administrative reads.
- `IdempotencyStore`: use a conditional insert/unique key with expiry.
- `NotificationJobStore`: use a transactional queue that leases due jobs and
  prevents two workers from sending the same job.
- `NotificationEventSink`: send structured events to your audit/metrics system.

Use Application Default Credentials or workload identity to implement the
`accessToken` callback. Never ship a service-account key to Flutter or commit a
key file to this repository.

## Request boundary

Authorize every public registration/send endpoint before calling
`NotificationServer`. `NotificationRequestAuthorizer` supports a verified
bearer principal, required roles, and App Check. Also apply body-size limits,
per-principal rate limits, target allowlists, and server-side preference/tenant
checks at the HTTP framework boundary.

## Operational minimum

- Record correlation ID, envelope ID, target class, FCM result code, latency,
  attempt count, and stale-token count. Do not log raw tokens or full message
  content by default.
- Alert on sustained 429/5xx responses, auth failures, DLQ growth, and token
  invalidation spikes.
- Respect Retry-After, add jitter, cap concurrency, and avoid synchronized
  traffic spikes around round clock times.
- Retain idempotency records at least through message TTL and queue retry time.
- Periodically expire registrations that have not refreshed and reconcile user
  sign-out by installation ID.

The package deliberately does not start an unauthenticated HTTP server. Host it
inside your existing service, identity, database, and deployment controls.
