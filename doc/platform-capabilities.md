# Platform capabilities

This table describes package-owned behavior. FCM delivery still depends on
Firebase/APNs credentials, operating-system policy, user permission, network
conditions, battery management, and correct application setup.

| Capability | Android | iOS | Web | macOS | Windows | Linux |
| --- | --- | --- | --- | --- | --- | --- |
| FCM remote delivery | Yes | Yes | Yes | Firebase-dependent; validate target | No | No |
| Foreground local presentation | Yes | Yes | Browser API | Yes | Yes, with toast identity | Yes |
| One-time scheduling | Yes | Yes | No | Yes | Yes | No package guarantee |
| Recurring scheduling | Yes | Yes | No | Yes | No package guarantee | No package guarantee |
| Exact schedule control | Permission-gated | OS-managed | No | OS-managed | No | No |
| Actions | Yes | Registered categories | Service worker | Registered categories | Upstream-dependent | Upstream-dependent |
| Inline reply | Yes | Yes | No | Yes | Upstream-dependent | No guarantee |
| Direct app-icon badge mutation | No | Yes | No | No | No | No |
| Groups / threads | Groups | Threads | Tag replacement | Threads | Upstream-dependent | Upstream-dependent |
| Inbox / preferences / policy | Yes | Yes | Yes | Yes | Yes | Yes |
| FCM topic subscription | Yes | Yes | Yes | Firebase-dependent | No | No |
| Delivery metrics toggle | Android SDK | Native app hook required | Worker setup required | Native setup | No | No |

`getCapabilities()` reports the current runtime's support and setup dependency.
It is the source of truth for conditional UI; this table is release-level
guidance.

## Intentionally outside the package boundary

- The package never stores a Firebase service-account key in a client app.
- It cannot guarantee remote delivery time; TTL, collapse, priority, and OS
  power policy still apply.
- It does not bypass permission prompts, Focus modes, Do Not Disturb, channel
  settings, or exact-alarm policy.
- iOS rich-media downloads require a Notification Service Extension in the host
  application.
- Live Activities require an app-owned ActivityKit target and push tokens. Use
  the reference server's platform override to send the Apple payload.
- Windows and Linux do not receive FCM through FlutterFire. They remain useful
  for local presentation, inbox, preferences, and in-app surfaces where the
  upstream local-notification implementation supports the requested feature.
