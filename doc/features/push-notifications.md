---
layout: page
title: Push Notifications
---

# Push Notifications

The package wraps raw `firebase_messaging` with a unified lifecycle model so foreground, background, resume, and terminated flows can be handled consistently.

On Windows and Linux, Firebase Messaging itself is unavailable. The package
falls back to desktop local mode for supported local presentation, inbox flows,
quiet hours, and in-app templates. Query `getCapabilities()` before exposing
scheduling or other upstream-dependent local features; FCM-specific APIs
degrade gracefully and explain the limitation in diagnostics.

## Highlights

- unified click stream
- late-subscriber click queue
- background dispatcher helper
- normalized message model
