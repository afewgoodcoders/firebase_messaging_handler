/* firebase_messaging_handler v2 service worker template.
 * Copy to web/firebase-messaging-sw.js and replace the Firebase config values.
 */
importScripts('https://www.gstatic.com/firebasejs/12.9.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.9.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'YOUR_API_KEY',
  authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
  projectId: 'YOUR_PROJECT_ID',
  storageBucket: 'YOUR_PROJECT_ID.firebasestorage.app',
  messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
  appId: 'YOUR_APP_ID',
});

const messaging = firebase.messaging();

function parseJson(value, fallback) {
  if (!value) return fallback;
  try { return JSON.parse(value); } catch (_) { return fallback; }
}

async function closeMatchingNotifications(data) {
  const tag = data.tag || data.id;
  const notifications = await self.registration.getNotifications(tag ? { tag } : undefined);
  for (const notification of notifications) notification.close();
}

messaging.onBackgroundMessage(async (payload) => {
  const data = payload.data || {};
  const command = data.command || 'display';
  if (command === 'cancel' || command === 'markRead' || command === 'silent') {
    if (command === 'cancel') await closeMatchingNotifications(data);
    return;
  }

  const actions = parseJson(data.actions, [])
    .filter((action) => !action.textInput)
    .map((action) => ({ action: action.id, title: action.title, icon: action.icon }));
  const title = payload.notification?.title || data.title || 'Notification';
  const body = payload.notification?.body || data.body || '';
  const options = {
    body,
    icon: data.icon || '/icons/Icon-192.png',
    badge: data.badge || '/icons/Icon-72.png',
    image: payload.notification?.image || data.image,
    tag: data.tag || data.id || payload.messageId,
    renotify: data.renotify === 'true',
    requireInteraction: data.requireInteraction === 'true',
    silent: data.silent === 'true',
    actions,
    data: {
      ...data,
      route: data.route || data.deeplink || '/',
      messageId: payload.messageId || data.id,
    },
  };
  await self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const route = data.route || '/';
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      client.postMessage({
        type: 'firebase_messaging_handler_click',
        actionId: event.action || null,
        data,
      });
      if ('focus' in client) {
        await client.focus();
        if ('navigate' in client && route) await client.navigate(route);
        return;
      }
    }
    if (self.clients.openWindow) await self.clients.openWindow(route);
  })());
});

self.addEventListener('notificationclose', (event) => {
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      client.postMessage({
        type: 'firebase_messaging_handler_close',
        data: event.notification.data || {},
      });
    }
  })());
});
