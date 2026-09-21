---
layout: page
title: Web Setup
---

# Web Setup

Web support requires Firebase web configuration plus a valid service worker setup for messaging.

## Checklist

- Add Firebase web config to your app
- Copy `web/firebase-messaging-sw.template.js` to the deployed app root as
  `firebase-messaging-sw.js`, configure Firebase, and register it at the scope
  controlling the Flutter app
- Pass the public Web Push certificate as `webVapidKey`
- Request browser notification permission from a user gesture, then call
  `synchronizeToken()`
- Confirm icon and badge assets are available
- Confirm service-worker click/action messages reach `deliveryEvents` and the
  click stream

## Diagnostics

Use the package diagnostics APIs and browser devtools console to validate permission state and service worker behavior.

Web supports remote delivery and worker actions. It does not provide durable
local scheduling, portable badge mutation, or inline notification replies.
