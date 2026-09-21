# Web service worker

Copy `firebase-messaging-sw.template.js` to the deployed Flutter web root as
`firebase-messaging-sw.js`, replace the Firebase configuration, and ensure it
is registered at the scope controlling the app.

The worker handles envelope display/cancel/silent commands, image/icon/badge,
tag replacement, actions, clicks, closes, focus/navigation, and sends
interaction messages back to the Dart click and delivery-event streams.

Requirements:

- HTTPS or localhost
- notification permission requested from a user gesture
- a Firebase Web Push certificate and matching `webVapidKey`
- no second worker competing for the same scope

If you enable Firebase delivery-metrics export, do it in this service worker as
required by the Firebase JavaScript SDK; the Dart configuration toggle is for
Android only.
