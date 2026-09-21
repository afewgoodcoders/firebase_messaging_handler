---
layout: page
title: Server Recipes
---

# Server Recipes

The repository includes a tested TypeScript reference package under `server/`
and lightweight payload samples under `server_recipes/`.

Included recipes cover:

- basic transactional push
- data-only bridge payloads
- notification actions
- rich media
- topic campaigns

The reference package additionally covers token registration, envelope
validation, FCM HTTP v1 retry/backoff, idempotency, scheduling, stale-token
cleanup, authorization/App Check boundaries, audit events, and dead letters.

Repository paths:

- `server_recipes/README.md`
- `server_recipes/cloud_functions/`
- `server_recipes/rest_api/`
- `server/README.md`
- `schema/notification-envelope-v2.schema.json`

For production sends, prefer `server/src/envelope.ts` so every value is encoded
as an FCM-compatible string and payload size is validated before the request.
