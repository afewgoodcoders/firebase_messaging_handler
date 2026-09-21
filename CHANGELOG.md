# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.0.0]

### Added

- Versioned notification envelope v2 with validation, expiration, commands, collapse/deduplication keys, localization, actions, and string-only FCM encoding
- Durable idempotency, topic state, policy counters, background interactions, and configurable runtime state storage
- Fine-grained permission requests, explicit token synchronization, runtime capability reporting, and typed operation results
- Action categories, background actions, inline replies, dismiss events, grouped/threaded notifications, and native presentation-detail escape hatches
- Exact/inexact Android schedule modes, exact-alarm capability checks, active/pending notification inspection, and Android channel deletion/status APIs
- Web service-worker template with rich presentation, commands, click/action/close bridging, and reinitializable stream lifecycle
- Explicit `client` versus `system` remote presentation, with data-only policy control or OS-rendered background reliability
- Web parity for action notifications, inbox persistence, in-app routing, and silent commands
- Explicit background-isolate bootstrap and Linux/Windows native notification-detail overrides
- Privacy-preserving analytics modes and opt-in Android FCM delivery-metrics export
- Native iOS badge bridge and Windows toast identity configuration
- Reference TypeScript server package with HTTP v1 encoding, retry/backoff, token registry, stale-token cleanup, scheduling, idempotency, DLQ, authorization/App Check boundary, and audit events
- JSON Schema, migration guide, platform capability matrix, and production deployment documentation

### Changed

- `initialize(FCMConfiguration)` no longer prompts for permission or creates a token unless explicitly configured
- Provisional Apple authorization is treated as usable, and denied permission no longer makes package initialization fail
- Foreground Apple delivery is rendered once through the package pipeline; schedule acceptance emits `scheduled` rather than `delivered`
- Data-only actions are normalized from the JSON strings required by FCM HTTP v1
- Token deletion and topic unsubscription are independent; topic failures now propagate to callers
- Debug logging is opt-in and analytics excludes content and raw tokens by default
- Package, iOS podspec, examples, and documentation now target the 2.0.0 contract

### Fixed

- Configuration fields that were previously accepted but not wired into runtime behavior
- Listener leaks, dispose-time notification cancellation, null-message deduplication collisions, unbounded history, and non-durable frequency limits
- iOS foreground suppression, action-category registration, inline reply propagation, group/thread identifiers, stable notification IDs, and truthful badge support
- Silent success results for unsupported web/local operations and failed presentation attempts

### Breaking

- Safe initialization defaults require applications to call `requestNotificationPermission()` and `synchronizeToken()` at an appropriate user-driven point
- Pending-notification inspection now returns `List<PendingNotificationSnapshot>` instead of an untyped list
- Action, grouping, and threading presentation helpers now return `Future<bool>` so unsupported or failed operations are observable
- Debug logging defaults to disabled; enable `FCMConfiguration.enableDebugLogging` during development when needed
- See `doc/v2-migration.md` for the complete migration checklist

## [1.0.7]

### Added
- **One-call initialization** — added `FirebaseMessagingHandler.initialize(FCMConfiguration)` with smart Android channel and icon defaults
- **Notification control plane** — added typed categories, persisted user preferences, quiet hours, frequency limits, and daily caps across package-managed delivery surfaces
- **Preference center** — added an embeddable Flutter preferences widget with category, sound, badge, quiet-hours, and system-settings controls
- **Typed delivery events** — added a single stream for received, delivered, suppressed, deferred, opened, and action outcomes
- **Policy coverage** — added unit and widget tests for delivery decisions, preference persistence, and preference-center interactions

### Changed
- **Current local-notification support** — upgraded `flutter_local_notifications` to `^22.3.1` so the package supports the latest stable dependency release
- **Supported Android toolchain** — aligned the plugin and example with Android API 24, Android `compileSdk` 36, AGP 8.11.1, Kotlin 2.2.20, and Gradle 8.14.5
- **Project identity** — updated package metadata, support links, native identifiers, and example-app identifiers for A Few Good Coders and the `afewgoodcoders/firebase_messaging_handler` repository
- **Current Dart formatting** — normalized Dart sources with the formatter used by the current pub.dev analysis toolchain

### Fixed
- **Synthetic handler test** — moved the non-device handler harness under `test/` so Flutter runs it on the test VM instead of trying to deploy the plugin package as an app

---

## [1.0.6]

### Added
- **Release checklist documentation** — added a package release checklist covering formatting, analysis, tests, dry-run publishing, `pana` scoring, and Android integration tests
- **Platform capability guide** — expanded the docs landing page with platform support, setup paths, and capability expectations across Android, iOS, Web, desktop, and macOS

### Changed
- **Integration test guide** — refreshed Android integration-test instructions to clarify that runnable device tests live under the example app, while package-root integration tests are synthetic only
- **README documentation index** — updated documentation links from the stale `docs/` path to the actual `doc/` directory

### Fixed
- **Stale README roadmap** — removed the outdated note that listed already-shipped capabilities as “coming up”
- **Release documentation drift** — moved verification details out of release notes and into the dedicated release checklist

---

## [1.0.5]

### Added
- **Timezone refresh APIs** — `refreshLocalTimezone()` and `getConfiguredLocalTimezone()` added to `FirebaseMessagingHandler.instance` for apps that reschedule reminders after app resume or timezone changes
- **Diagnostics timezone metadata** — `runDiagnostics()` now includes the currently configured timezone in `configuredTimezone`
- **Weekly scheduling helper** — `scheduleWeeklyNotification()` added for recurring notifications on a specific weekday
- **Swift Package Manager manifest path** — added `ios/firebase_messaging_handler/Package.swift`, matching Flutter's current SPM package layout expectation

### Changed
- **Web/WASM public import graph** — web analysis now uses a web-safe notification manager and foreground-options path so native local-notification implementations are not pulled into WASM analysis
- **Platform-neutral channel model** — `NotificationChannelData` no longer directly depends on `flutter_local_notifications`; Android conversion to `AndroidNotificationChannel` now lives in the Flutter local notifications extension layer
- **iOS podspec version sync** — podspec version now matches the package release version

### Fixed
- **Timezone-safe scheduled notifications** — scheduled notifications now configure `tz.local` from the device timezone via `flutter_timezone` before calling `zonedSchedule`
- **Pub platform scoring** — package now reports full platform support with WASM-ready and Swift PM-ready status

---

## [1.0.4]

### Fixed
- **Web: `webVapidKey` parameter added to `init()`** — FCM token retrieval on web now works correctly. Pass your Firebase Web Push certificate key via `webVapidKey`; previously `senderId` was incorrectly forwarded as the VAPID key, causing token fetch to fail silently
- **Web: binding crash on startup** — `FirebaseMessagingHandlerWeb.registerWith()` was touching `FirebaseMessagingHandler.instance` during plugin registration, before `WidgetsFlutterBinding` was initialized. This triggered `SharedPreferences.getInstance()` too early and threw a `DartError` on web. The premature singleton touch has been removed; the singleton initialises lazily when `init()` is called as intended
- **Web: `firebase_core` added as explicit dependency** — the package now declares `firebase_core` directly instead of relying on it as a transitive dependency of `firebase_messaging`
- **Web: actionable FCM token error logs** — `token-subscribe-failed` (missing Web Push certificate) and related errors now bail immediately without retrying and log exactly what is wrong and how to fix it, rather than silently retrying four times
- **Web: Firebase app diagnostic log** — on web, `FCMService.initialize()` now logs the connected Firebase project ID, appId, and senderId so misconfiguration is immediately visible
- **Example app: false "Firebase Not Configured" on web** — the setup check no longer attempts `getToken()` on web, so the example proceeds to the home screen as expected

---

## [1.0.3]

### Added
- **Swift Package Manager (SPM) support** — `ios/Package.swift` added; iOS plugin now resolves via SPM in addition to CocoaPods

### Changed
- **WASM compatibility** — replaced `universal_html` dependency with `dart:js_interop`-based abstraction; package now passes WASM analysis
- iOS native stub simplified — removed unused `FirebaseCore`/`FirebaseMessaging` imports (FCM is handled entirely by `firebase_messaging`)

---

## [1.0.2]

### Changed
- `flutter_local_notifications` lower bound tightened to `^21.0.0` — aligns constraint with the v21 named parameter API the package actually requires

---

## [1.0.1]

### Changed
- `flutter_local_notifications` constraint widened to `>=18.0.1 <22.0.0` — now fully compatible with v21 (named parameter API)

### Fixed
- Updated all `flutter_local_notifications` call sites to v21 named parameter API (`show`, `initialize`, `zonedSchedule`, `periodicallyShow`, `cancel`)
- Removed deprecated `uiLocalNotificationDateInterpretation` parameter from `zonedSchedule` calls
- Removed broken CI and codecov badges from README

---

## [1.0.0]

### Added
- **Android & macOS platform support** — both platforms now fully declared
- **`lastTokenError`** on `FirebaseMessagingHandler.instance` — surfaces the exact reason an FCM token could not be retrieved (e.g. APNs not configured, simulator)

### Changed
- **`flutter_local_notifications` constraint** widened to `>=18.0.1 <22.0.0` — compatible with v19, v20, and v21
- **FCM token failures now return `null`** instead of silent mock tokens — check `lastTokenError` for the reason

---

## [0.1.1-beta.1]

### Added
- **Modular architecture** — complete rewrite into `core/managers`, `core/services`, `core/interfaces`, `core/utils` layers; clean separation of concerns
- **Unified handler API** — single `Future<bool> Function(NormalizedMessage, NotificationLifecycle)` callback that works across foreground, background, and terminated states without manual `@pragma` wiring
- **`NormalizedMessage` model** — consistent `title`, `body`, `imageUrl`, `data`, `actions`, `receivedAt`, `origin`, `channelId`, `raw` across all lifecycles
- **`NotificationLifecycle` enum** — `foreground`, `background`, `terminated`, `resume`, `initial`
- **Auto initial-notification emission** — terminated-launch notifications automatically queued and emitted onto the unified click stream; opt-out available
- **In-app messaging engine** — silent FCM push (`fcmh_inapp` key) triggers in-app templates registered via `registerInAppNotificationTemplates`
- **`builtin_generic` renderer** — seven layout variants driven by `layout:` key: `dialog`, `banner` (top/bottom), `bottom_sheet`, `snackbar`, `tooltip`, `carousel`, `html_modal`
- **Frequency caps and quiet hours** — lifecycle-aware presentation throttling; configurable quiet windows
- **Notification inbox** — `NotificationInboxView` widget with swipe-to-delete, mark-as-read, pagination; `NotificationInboxStorageInterface` for swappable persistence (SharedPrefs default + in-memory test impl)
- **`BridgingPayloadValidator`** — validates data-only payloads before bridging; rejects missing `title`/`body`, type errors, script injection; increments `diagnostics.invalidPayloadCount`
- **Data-only bridging** — configurable key mapping to promote silent payloads to local notifications; web suppression with once-per-session log
- **`BadgeManager`** — unified badge abstraction over `flutter_local_notifications` (iOS) and notification channels (Android); local persistence
- **`PermissionWizardService`** — `requestAllPermissions()` with rich `PermissionWizardResult` covering Android (POST_NOTIFICATIONS) and iOS (alert/badge/sound/provisional)
- **`runDiagnostics()`** on `FirebaseMessagingHandler.instance` — returns `NotificationDiagnosticsResult` with permission status, token availability, badge support, background handler registration state, pending count, web permission, invalid payload count
- **`bin/setup.dart` doctor script** — checks `google-services.json`, `GoogleService-Info.plist`, AndroidManifest permissions; auto-patches `INTERNET` and `POST_NOTIFICATIONS`
- **Smart default channel** — auto-creates a high-importance channel at init if none exist, preventing silent foreground notifications on Android
- **Background dispatcher helper** — `@pragma('vm:entry-point')`-safe entry point; hydrates storage and queues before user handler runs
- **`FmhAnalyticsService`** — pluggable analytics callback tracking received, click, action, schedule, and token events
- **`InAppOverlayHost` / `InAppOverlayController`** — managed overlay stack for presenting in-app templates above all other widgets
- **`BuiltInInAppTemplates.versionPrompt`** — pre-built app update prompt template
- **`NotificationInboxView`** — full inbox widget with theming knobs, avatar/image support, swipe gestures, empty state, and action chips
- **Pending click queue** — click events delivered to late stream subscribers (background/terminated taps before `listen` call)
- **Web platform registration** — `FirebaseMessagingHandlerWeb` Dart plugin class via `flutter_web_plugins`
- **Platform utilities** — conditional `platform_utils.dart` with IO and web stubs; `js_compat.dart` for web JS interop
- **New tests** — click-stream queue delivery, `BridgingPayloadValidator` accept/reject matrix, `InboxStorageService` upsert/paging/markRead/delete, golden harness (alchemist)
- **`flutter_widget_from_html_core`** dependency for `html_modal` template layout
- **`timezone`** dependency for accurate scheduled notification delivery

### Changed
- Public API facade (`FirebaseMessagingHandler`) fully preserved; all new APIs are additive
- Example app rebuilt as **FCM Showcase** — scenario inspector, activity timeline, inbox screen, template trigger demos, APNs setup guidance, diagnostics sheet, token copy overlay
- README restructured with feature-by-feature walkthrough, quick-start, and payload cookbook

### Fixed
- Foreground click stream on Android — events were silently dropped when the stream had no listener at the time of tap
- iOS duplicate foreground notifications — the package now prevents showing a local notification when Firebase already delivered it in the foreground
- iOS initial message detection — added 100 ms retry for iOS timing edge case on cold start
- `app_badger` / `flutter_app_badger` namespace conflicts — removed; badge management now handled via `flutter_local_notifications` and platform channel fallback

---

## [0.1.0]

### Added
- `subscribeToTopic(String topic)` — subscribe to an FCM topic
- `unsubscribeFromTopic(String topic)` — unsubscribe from a topic
- `unsubscribeFromAllTopics()` — bulk topic unsubscription
- `NotificationStreamExtensions` — stream utility extensions
- Terminated-state notification fix — initial message now correctly retrieved on cold start via `getInitialMessage()`

### Changed
- Removed native Android and iOS plugin stubs — package now relies entirely on `firebase_messaging` and `flutter_local_notifications` for native work (pure-Dart approach)
- `firebase_messaging` minimum constraint raised to `>=15.1.4`
- Dropped Linux, macOS, Windows example targets — focused on Android and iOS

### Fixed
- Click stream not delivering terminated-state notification on first launch
- Example app not handling notification tap navigation correctly

---

## [0.0.8]

### Fixed
- Dependency version constraints causing resolution failures with newer `firebase_messaging` and `flutter_local_notifications` releases

---

## [0.0.7]

### Changed
- Loosened all dependency version constraints to improve compatibility

### Fixed
- Stream controller changed to `broadcast()` — previously only one listener was supported; multiple listeners now work correctly

---

## [0.0.6]

### Changed
- Example app updated to demonstrate stream restart and handler re-initialization

---

## [0.0.5]

### Added
- Stream disposal — `dispose()` now properly closes the notification stream controller and cancels all subscriptions

---

## [0.0.4]

### Changed
- README improvements with setup instructions and usage examples

---

## [0.0.3]

### Added
- "Clear token" button in example app for testing token refresh flows

### Fixed
- Minor static analysis issues — removed unused imports, tightened linting

---

## [0.0.2]

### Added
- BSD 3-Clause license file
- Flutter SDK constraint added (`>=2.12.0`)
- Broader dependency compatibility — lowered minimum SDK requirements

### Changed
- README expanded with installation and basic usage guide
- `NotificationChannelData` model fields clarified

---

## [0.0.1]

### Added
- Initial release
- `FirebaseMessagingHandler` singleton with `init()` — sets up FCM, requests permissions, creates Android notification channels, returns a click stream
- `NotificationData` model — wraps incoming FCM payloads with `title`, `body`, `payload`, `type`
- `NotificationChannelData` — configurable Android notification channel (importance, priority, sound, vibration, lights)
- `NotificationImportanceEnum`, `NotificationPriorityEnum`, `NotificationTypeEnum` — type-safe enums
- `AndroidNotificationChannelExtensions` — converts `NotificationChannelData` to `flutter_local_notifications` channel objects
- `FirebaseMessagingHandlerSharedPreferences` — local storage for FCM token caching
- Foreground and background notification handling via `firebase_messaging`
- Local notification display via `flutter_local_notifications`
- Example app demonstrating basic setup and notification receipt
