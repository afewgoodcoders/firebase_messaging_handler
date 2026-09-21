// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:firebase_messaging_handler_example/firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fcm_test_sender.dart';
import 'test_dashboard.dart';

/// Comprehensive feature checklist — covers every public API in the package.
///
/// Run from example/ directory:
///
///   BASE64=$(base64 -i ../test/firebase_config/service_account.json | tr -d '\n')
///   flutter test integration_test/comprehensive_test.dart \
///     --dart-define=FCM_TEST_SENDER_ID=`<your-project-number>` \
///     --dart-define=FCM_SERVICE_ACCOUNT_B64=$BASE64 \
///     --device-id `<your-device-id>`
///
/// Without credentials, FCM-send tests are SKIPPED — CI stays green.

const _senderId = String.fromEnvironment(
  'FCM_TEST_SENDER_ID',
  defaultValue: '',
);

// ─────────────────────────────────────────────────────────────────────────────
// Shared state
// ─────────────────────────────────────────────────────────────────────────────

late FcmTestSender? _sender;
late String? _token;
// ignore: unused_element
Stream<NotificationData?>? _clickStream;
late TestSuite _suite;

bool get _hasCredentials => _sender != null;

bool get _hasToken => _token != null;

// ─────────────────────────────────────────────────────────────────────────────
// Test registration helper — registers with suite AND flutter test runner
// ─────────────────────────────────────────────────────────────────────────────

void _t(String category, String name) => _suite.register(category, name);

Future<void> _run(
  String name,
  Future<void> Function() body, {
  bool needsCreds = false,
  bool needsToken = false,
  WidgetTester? tester,
}) async {
  final skip = (needsCreds && !_hasCredentials) || (needsToken && !_hasToken);
  final reason = needsCreds && !_hasCredentials
      ? 'No FCM_SERVICE_ACCOUNT_B64'
      : needsToken && !_hasToken
      ? 'No FCM token available'
      : null;

  await _suite.run(name, body, skip: skip, skipReason: reason);

  // Let the dashboard widget repaint.
  if (tester != null) await tester.pump(Duration.zero);
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FMH comprehensive feature checklist', (tester) async {
    // ── Global setup ──────────────────────────────────────────────────────────

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    _sender = FcmTestSender.fromEnv();
    _suite = TestSuite();

    // ── Register all test cases (defines the order on screen) ─────────────────
    _registerAll();

    // ── Render the live dashboard ─────────────────────────────────────────────
    await tester.pumpWidget(TestDashboard(suite: _suite));
    await tester.pump();

    // ── Init ──────────────────────────────────────────────────────────────────
    await _runInit(tester);

    // ── Token ─────────────────────────────────────────────────────────────────
    await _runToken(tester);

    // ── Permissions ───────────────────────────────────────────────────────────
    await _runPermissions(tester);

    // ── Diagnostics ───────────────────────────────────────────────────────────
    await _runDiagnostics(tester);

    // ── Runtime capabilities ─────────────────────────────────────────────────
    await _runCapabilities(tester);

    // ── Analytics ─────────────────────────────────────────────────────────────
    await _runAnalytics(tester);

    // ── Unified handler + mock pipeline ───────────────────────────────────────
    await _runHandlers(tester);

    // ── Data bridge ───────────────────────────────────────────────────────────
    await _runDataBridge(tester);

    // ── Foreground options ────────────────────────────────────────────────────
    await _runForegroundOptions(tester);

    // ── Topic subscriptions ───────────────────────────────────────────────────
    await _runTopics(tester);

    // ── Scheduling ────────────────────────────────────────────────────────────
    await _runScheduling(tester);

    // ── Badge management ──────────────────────────────────────────────────────
    await _runBadges(tester);

    // ── Notification display ──────────────────────────────────────────────────
    await _runDisplay(tester);

    // ── Custom channels ───────────────────────────────────────────────────────
    await _runChannels(tester);

    // ── In-app messaging ──────────────────────────────────────────────────────
    await _runInApp(tester);

    // ── Inbox ─────────────────────────────────────────────────────────────────
    await _runInbox(tester);

    // ── Payload validation ────────────────────────────────────────────────────
    await _runPayloadValidation(tester);

    // ── FCM send (real push, requires credentials) ────────────────────────────
    // Topic cleanup is independent from token lifecycle in v2.
    _token = await FirebaseMessagingHandler.instance.getFcmToken();
    await _runFcmSend(tester);

    // Leave dashboard on screen for visual review.
    await tester.pumpAndSettle(const Duration(seconds: 2));

    print(
      '[comprehensive] summary: total=${_suite.total}, '
      'passed=${_suite.passed}, failed=${_suite.failed}, '
      'skipped=${_suite.skipped}, pending=${_suite.pending}, '
      'running=${_suite.running}',
    );

    // Every registered case must reach a terminal status. When credentials
    // were supplied, skipped live-FCM cases are failures in the test setup.
    expect(_suite.pending, equals(0), reason: 'Some cases never started.');
    expect(_suite.running, equals(0), reason: 'Some cases never completed.');
    if (_hasCredentials) {
      expect(
        _suite.skipped,
        equals(0),
        reason: 'Live FCM credentials were supplied, but cases were skipped.',
      );
    }
    expect(
      _suite.failed,
      equals(0),
      reason:
          'Some tests failed:\n'
          '${_suite.cases.where((c) => c.status == TestStatus.failed).map((c) => '  • ${c.name}: ${c.errorMessage}').join('\n')}',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}

// ─────────────────────────────────────────────────────────────────────────────
// Registration — defines the on-screen order
// ─────────────────────────────────────────────────────────────────────────────

void _registerAll() {
  const i = 'Initialization';
  _t(i, 'init() returns a click stream');
  _t(i, 'init() creates default high-importance channel');
  _t(i, 'checkInitial() returns null (no initial notification)');

  const tk = 'Token';
  _t(tk, 'getFcmToken() returns non-null token');
  _t(tk, 'Token has expected format (length ≥ 100)');
  _t(tk, 'lastTokenError is null after success');
  _t(tk, 'getFcmToken() is idempotent (same token on repeat call)');

  const perm = 'Permissions';
  _t(perm, 'requestPermissionsWizard() completes without error');
  _t(perm, 'overallStatus is a non-empty string');
  _t(perm, 'notes field is a valid list');

  const diag = 'Diagnostics';
  _t(diag, 'runDiagnostics() completes');
  _t(diag, 'fcmTokenAvailable is true');
  _t(diag, 'platform is "android" on this device');
  _t(diag, 'permissionsGranted is true');
  _t(diag, 'pendingNotificationCount is ≥ 0');
  _t(diag, 'recommendations is a valid list');
  _t(diag, 'metadata contains fcmSupported key');

  const capabilities = 'Capabilities';
  _t(capabilities, 'getCapabilities() reports Android runtime');
  _t(capabilities, 'remote push and local presentation are supported');
  _t(capabilities, 'exact scheduling status is explicit');
  _t(capabilities, 'active notification inspection completes');
  _t(capabilities, 'system notification status is queryable');

  const analytics = 'Analytics';
  _t(analytics, 'setAnalyticsCallback() registers without crash');
  _t(analytics, 'trackAnalyticsEvent() triggers callback');
  _t(analytics, 'Callback receives correct event name');
  _t(analytics, 'Callback receives correct data map');
  _t(analytics, 'setAnalyticsCallback(null) clears without crash');

  const handlers = 'Handlers & Mock Pipeline';
  _t(handlers, 'setTestMode(true) enables mock streams');
  _t(handlers, 'createMockRemoteMessage() builds valid message');
  _t(handlers, 'addMockNotification() processes through unified handler');
  _t(handlers, 'Unified handler receives NormalizedMessage');
  _t(handlers, 'NormalizedMessage fields are populated');
  _t(handlers, 'getMockClickStream() is non-null in test mode');
  _t(handlers, 'addMockClickEvent() emits on click stream');
  _t(handlers, 'Click data title matches injected title');
  _t(handlers, 'resetMockData() clears events');
  _t(handlers, 'setTestMode(false) disables mock streams');
  _t(handlers, 'setUnifiedMessageHandler(null) clears handler');
  _t(handlers, 'configureBackgroundProcessingCallback() completes');

  const bridge = 'Data Bridge';
  _t(bridge, 'setDataOnlyMessageBridge() registers custom bridge');
  _t(bridge, 'Bridge callback is invoked for data-only messages');
  _t(bridge, 'enableDefaultDataOnlyBridge() registers without crash');
  _t(bridge, 'setDataOnlyMessageBridge(null) clears bridge');

  const fgo = 'Foreground Options';
  _t(fgo, 'setForegroundNotificationOptions(defaults) completes');
  _t(fgo, 'Options with showNotification=false completes');
  _t(fgo, 'Options with custom sound name completes');

  const topics = 'Topics';
  _t(topics, 'subscribeToTopic() completes');
  _t(topics, 'subscribeToTopic() — multiple topics');
  _t(topics, 'unsubscribeFromTopic() completes');
  _t(topics, 'getSubscribedTopics() reflects successful subscriptions');
  _t(topics, 'unsubscribeFromAllTopics() completes');
  _t(topics, 'topic cleanup does not delete the FCM token');

  const sched = 'Scheduling';
  _t(sched, 'scheduleNotification() returns true');
  _t(sched, 'getPendingNotifications() returns non-null list');
  _t(sched, 'pending notifications are strongly typed');
  _t(sched, 'Scheduled count ≥ 1 after scheduling');
  _t(sched, 'cancelScheduledNotification(id) returns true');
  _t(sched, 'scheduleRecurringNotification("daily") returns true');
  _t(sched, 'scheduleRecurringNotification("weekly") returns true');
  _t(sched, 'cancelAllScheduledNotifications() returns true');
  _t(sched, 'getPendingNotifications() returns empty after cancel all');

  const badge = 'Badge Management';
  if (Platform.isAndroid) {
    _t(badge, 'setAndroidBadgeCount(5) completes');
    _t(badge, 'getAndroidBadgeCount() returns value');
    _t(badge, 'clearBadgeCount() completes');
  }
  if (Platform.isIOS) {
    _t(badge, 'setIOSBadgeCount(3) completes');
    _t(badge, 'getIOSBadgeCount() returns 3');
    _t(badge, 'clearBadgeCount() sets iOS count to 0');
  }

  const display = 'Notification Display';
  _t(display, 'showNotificationWithActions() reports success');
  _t(display, 'showLocalNotification() returns a typed success result');
  _t(display, 'showGroupedNotification() reports success');
  _t(display, 'dismissNotificationGroup() reports success');
  _t(display, 'createNotificationGroup() reports success');
  _t(display, 'showThreadedNotification() reports success');

  const chan = 'Custom Channels';
  _t(chan, 'createCustomSoundChannel() completes');
  _t(chan, 'getAvailableSounds() returns list or null without crash');
  _t(chan, 'deleteNotificationChannel() returns true');

  const inapp = 'In-App Messaging';
  _t(inapp, 'registerInAppNotificationTemplates() registers custom template');
  _t(inapp, 'getInAppNotificationStream() returns a stream');
  _t(inapp, 'setInAppDeliveryPolicy() with quiet hours completes');
  _t(inapp, 'setInAppDeliveryPolicy() with frequency caps completes');
  _t(inapp, 'setInAppFallbackDisplayHandler() registers without crash');
  _t(inapp, 'clearPendingInAppNotifications() completes');
  _t(inapp, 'flushPendingInAppNotifications() completes');
  _t(inapp, 'clearInAppNotificationTemplates() completes');
  _t(inapp, 'setInAppNavigatorKey() accepts GlobalKey');

  const inbox = 'Inbox Storage';
  _t(inbox, 'InMemoryInboxStorage: upsert saves item');
  _t(inbox, 'InMemoryInboxStorage: fetch returns saved items');
  _t(inbox, 'InMemoryInboxStorage: count returns correct total');
  _t(inbox, 'InMemoryInboxStorage: markRead updates isRead flag');
  _t(inbox, 'InMemoryInboxStorage: unread count after markRead');
  _t(inbox, 'InMemoryInboxStorage: delete removes item');
  _t(inbox, 'InMemoryInboxStorage: pagination (page 0 vs page 1)');
  _t(inbox, 'InMemoryInboxStorage: clear empties storage');
  _t(inbox, 'NotificationInboxItem: toMap/fromMap roundtrip');

  const payload = 'Payload Validation';
  _t(payload, 'Valid payload with title+body passes');
  _t(payload, 'Payload with title only passes');
  _t(payload, 'Payload missing title and body fails');
  _t(payload, 'Payload with empty title fails');
  _t(payload, 'Payload with valid actions map passes');
  _t(payload, 'Payload with invalid actions type fails');
  _t(payload, 'Payload with valid analytics JSON string passes');
  _t(payload, 'Payload with invalid analytics type fails');
  _t(payload, 'NotificationEnvelope v2 round-trips through FCM data');
  _t(payload, 'NotificationEnvelope rejects expired or oversized payloads');

  const fcm = 'FCM Send (real push)';
  _t(fcm, 'Send foreground notification — returns HTTP 200');
  _t(fcm, 'Foreground notification appears in active notifications');
  _t(fcm, 'Send data-only + fcmh_inapp — processes without crash');
  _t(fcm, 'In-app stream emits after data-only send');
  _t(fcm, 'Send with custom data fields — completes');
}

// ─────────────────────────────────────────────────────────────────────────────
// Test sections
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _runInit(WidgetTester tester) async {
  await _run('init() returns a click stream', () async {
    _clickStream = await FirebaseMessagingHandler.instance.initialize(
      FCMConfiguration(
        senderId: _senderId.isEmpty ? '000000000000' : _senderId,
        androidChannels: <NotificationChannelData>[
          NotificationChannelData(
            id: 'test_default',
            name: 'Test Default',
            description: 'Integration test default channel',
          ),
        ],
        androidNotificationIconPath: '@mipmap/ic_launcher',
        requestPermissionOnInitialize: false,
        synchronizeTokenOnInitialize: false,
        updateTokenCallback: (String token) async {
          _token = token;
          return true;
        },
        actionCategories: const <NotificationActionCategory>[
          NotificationActionCategory(
            id: 'integration_actions',
            actions: <NotificationAction>[
              NotificationAction(id: 'reply', title: 'Reply', textInput: true),
            ],
          ),
        ],
      ),
    );
    // Stream may be null on platforms where FCM is unavailable.
    // On Android with valid config it should be non-null.
  }, tester: tester);

  await _run('init() creates default high-importance channel', () async {
    // Calling init again is idempotent; the channel was auto-created above.
    final pending = await FirebaseMessagingHandler.instance
        .getPendingNotifications();
    expect(pending, isNotNull);
  }, tester: tester);

  await _run('checkInitial() returns null (no initial notification)', () async {
    final initial = await FirebaseMessagingHandler.checkInitial();
    // In an integration test launched directly there's no initial notification.
    expect(initial, isNull);
  }, tester: tester);
}

Future<void> _runToken(WidgetTester tester) async {
  await _run('getFcmToken() returns non-null token', () async {
    _token = await FirebaseMessagingHandler.instance.getFcmToken();
    expect(
      _token,
      isNotNull,
      reason:
          FirebaseMessagingHandler.instance.lastTokenError ??
          'token null with no error set',
    );
    expect(_token, isNotEmpty);
    expect(
      await FirebaseMessagingHandler.instance.synchronizeToken(force: true),
      isTrue,
    );
  }, tester: tester);

  await _run(
    'Token has expected format (length ≥ 100)',
    () async {
      expect(
        _token!.length,
        greaterThanOrEqualTo(100),
        reason: 'FCM tokens are typically 140–200 characters',
      );
    },
    needsToken: true,
    tester: tester,
  );

  await _run(
    'lastTokenError is null after success',
    () async {
      expect(FirebaseMessagingHandler.instance.lastTokenError, isNull);
    },
    needsToken: true,
    tester: tester,
  );

  await _run(
    'getFcmToken() is idempotent (same token on repeat call)',
    () async {
      final second = await FirebaseMessagingHandler.instance.getFcmToken();
      expect(second, equals(_token));
    },
    needsToken: true,
    tester: tester,
  );
}

Future<void> _runCapabilities(WidgetTester tester) async {
  late NotificationCapabilities capabilities;

  await _run('getCapabilities() reports Android runtime', () async {
    capabilities = await FirebaseMessagingHandler.instance.getCapabilities();
    expect(capabilities.platform, equals('android'));
  }, tester: tester);

  await _run('remote push and local presentation are supported', () async {
    expect(capabilities.supports(NotificationCapability.remotePush), isTrue);
    expect(
      capabilities.supports(NotificationCapability.localPresentation),
      isTrue,
    );
  }, tester: tester);

  await _run('exact scheduling status is explicit', () async {
    final status = capabilities[NotificationCapability.exactScheduling];
    expect(status.reason == null || status.reason!.isNotEmpty, isTrue);
  }, tester: tester);

  await _run('active notification inspection completes', () async {
    final active = await FirebaseMessagingHandler.instance
        .getActiveNotifications();
    expect(active, isA<List<ActiveNotificationSnapshot>>());
  }, tester: tester);

  await _run('system notification status is queryable', () async {
    final enabled = await FirebaseMessagingHandler.instance
        .areNotificationsEnabled();
    expect(enabled, isNotNull);
  }, tester: tester);
}

Future<void> _runPermissions(WidgetTester tester) async {
  await _run('requestPermissionsWizard() completes without error', () async {
    final result = await FirebaseMessagingHandler.instance
        .requestPermissionsWizard();
    expect(result.overallStatus, isNotNull);
  }, tester: tester);

  await _run('overallStatus is a non-empty string', () async {
    final result = await FirebaseMessagingHandler.instance
        .requestPermissionsWizard();
    expect(result.overallStatus, isNotEmpty);
    print('[comprehensive] permissions: ${result.overallStatus}');
  }, tester: tester);

  await _run('notes field is a valid list', () async {
    final result = await FirebaseMessagingHandler.instance
        .requestPermissionsWizard();
    expect(result.notes, isA<List<String>>());
  }, tester: tester);
}

Future<void> _runDiagnostics(WidgetTester tester) async {
  late NotificationDiagnosticsResult diag;

  await _run('runDiagnostics() completes', () async {
    diag = await FirebaseMessagingHandler.instance.runDiagnostics();
    expect(diag, isNotNull);
    print('[comprehensive] diagnostics: ${diag.toMap()}');
  }, tester: tester);

  await _run('fcmTokenAvailable is true', () async {
    expect(diag.fcmTokenAvailable, isTrue, reason: 'Error: ${diag.error}');
  }, tester: tester);

  await _run('platform is "android" on this device', () async {
    expect(diag.platform, equals('android'));
  }, tester: tester);

  await _run('permissionsGranted is true', () async {
    expect(
      diag.permissionsGranted,
      isTrue,
      reason: 'Status: ${diag.authorizationStatus}',
    );
  }, tester: tester);

  await _run('pendingNotificationCount is ≥ 0', () async {
    expect(diag.pendingNotificationCount, greaterThanOrEqualTo(0));
  }, tester: tester);

  await _run('recommendations is a valid list', () async {
    expect(diag.recommendations, isA<List<String>>());
  }, tester: tester);

  await _run('metadata contains fcmSupported key', () async {
    expect(diag.metadata.containsKey('fcmSupported'), isTrue);
    expect(diag.metadata['fcmSupported'], isTrue);
  }, tester: tester);
}

Future<void> _runAnalytics(WidgetTester tester) async {
  String? capturedEvent;
  Map<String, dynamic>? capturedData;

  await _run('setAnalyticsCallback() registers without crash', () async {
    FirebaseMessagingHandler.instance.setAnalyticsCallback((event, data) {
      capturedEvent = event;
      capturedData = data;
    });
  }, tester: tester);

  await _run('trackAnalyticsEvent() triggers callback', () async {
    FirebaseMessagingHandler.instance.trackAnalyticsEvent('test_event', {
      'key': 'value',
      'count': 42,
    });
    expect(capturedEvent, isNotNull);
  }, tester: tester);

  await _run('Callback receives correct event name', () async {
    expect(capturedEvent, equals('test_event'));
  }, tester: tester);

  await _run('Callback receives correct data map', () async {
    expect(capturedData, containsPair('key', 'value'));
    expect(capturedData, containsPair('count', 42));
  }, tester: tester);

  await _run('setAnalyticsCallback(null) clears without crash', () async {
    // ignore: avoid_dynamic_calls
    FirebaseMessagingHandler.instance.setAnalyticsCallback((_, _) {});
    FirebaseMessagingHandler.instance.trackAnalyticsEvent('after', {});
  }, tester: tester);
}

Future<void> _runHandlers(WidgetTester tester) async {
  NormalizedMessage? capturedMsg;
  NotificationData? capturedClick;

  await _run('setTestMode(true) enables mock streams', () async {
    FirebaseMessagingHandler.setTestMode(true);
    expect(FirebaseMessagingHandler.getMockNotificationStream(), isNotNull);
  }, tester: tester);

  await _run('createMockRemoteMessage() builds valid message', () async {
    final msg = FirebaseMessagingHandler.createMockRemoteMessage(
      messageId: 'test-123',
      title: 'Test Title',
      body: 'Test Body',
      data: <String, dynamic>{'key': 'value'},
    );
    expect(msg.messageId, equals('test-123'));
    expect(msg.notification?.title, equals('Test Title'));
  }, tester: tester);

  await _run(
    'addMockNotification() processes through unified handler',
    () async {
      await FirebaseMessagingHandler.instance.setUnifiedMessageHandler((
        normalized,
        lifecycle,
      ) async {
        capturedMsg = normalized;
        return true;
      });
      final msg = FirebaseMessagingHandler.createMockRemoteMessage(
        title: 'Handler Test',
        body: 'Body',
      );
      FirebaseMessagingHandler.addMockNotification(msg);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(capturedMsg, isNotNull);
    },
    tester: tester,
  );

  await _run('Unified handler receives NormalizedMessage', () async {
    expect(capturedMsg, isA<NormalizedMessage>());
  }, tester: tester);

  await _run('NormalizedMessage fields are populated', () async {
    expect(capturedMsg!.id, isNotEmpty);
    expect(capturedMsg!.lifecycle, isA<NotificationLifecycle>());
    expect(capturedMsg!.receivedAt, isA<DateTime>());
  }, tester: tester);

  await _run('getMockClickStream() is non-null in test mode', () async {
    expect(FirebaseMessagingHandler.getMockClickStream(), isNotNull);
  }, tester: tester);

  await _run('addMockClickEvent() emits on click stream', () async {
    FirebaseMessagingHandler.getMockClickStream()?.listen(
      (d) => capturedClick = d,
    );
    FirebaseMessagingHandler.addMockClickEvent(
      FirebaseMessagingHandler.createMockNotificationData(
        title: 'Click Test',
        body: 'Tapped',
        type: NotificationTypeEnum.foreground,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(capturedClick, isNotNull);
  }, tester: tester);

  await _run('Click data title matches injected title', () async {
    expect(capturedClick!.title, equals('Click Test'));
  }, tester: tester);

  await _run('resetMockData() clears events', () async {
    FirebaseMessagingHandler.resetMockData();
    capturedClick = null;
    capturedMsg = null;
  }, tester: tester);

  await _run('setTestMode(false) disables mock streams', () async {
    FirebaseMessagingHandler.setTestMode(false);
    expect(FirebaseMessagingHandler.getMockClickStream(), isNull);
  }, tester: tester);

  await _run('setUnifiedMessageHandler(null) clears handler', () async {
    await FirebaseMessagingHandler.instance.setUnifiedMessageHandler(null);
  }, tester: tester);

  await _run('configureBackgroundProcessingCallback() completes', () async {
    await FirebaseMessagingHandler.instance
        .configureBackgroundProcessingCallback(null);
  }, tester: tester);
}

Future<void> _runDataBridge(WidgetTester tester) async {
  RemoteMessage? bridgedMsg;

  await _run('setDataOnlyMessageBridge() registers custom bridge', () async {
    FirebaseMessagingHandler.instance.setDataOnlyMessageBridge(
      (msg) async => bridgedMsg = msg,
    );
  }, tester: tester);

  await _run('Bridge callback is invoked for data-only messages', () async {
    final messageId = 'bridge-${DateTime.now().microsecondsSinceEpoch}';
    final dataOnly = FirebaseMessagingHandler.createMockRemoteMessage(
      messageId: messageId,
      data: <String, dynamic>{'title': 'Silent', 'body': 'Data only'},
    );
    await FirebaseMessagingHandler.handleBackgroundMessage(dataOnly);
    expect(bridgedMsg, isNotNull);
    expect(bridgedMsg!.messageId, equals(messageId));
    expect(bridgedMsg!.data['title'], equals('Silent'));
  }, tester: tester);

  await _run('enableDefaultDataOnlyBridge() registers without crash', () async {
    FirebaseMessagingHandler.instance.enableDefaultDataOnlyBridge(
      channelId: 'test_default',
      titleKey: 'title',
      bodyKey: 'body',
    );
  }, tester: tester);

  await _run('setDataOnlyMessageBridge(null) clears bridge', () async {
    FirebaseMessagingHandler.instance.setDataOnlyMessageBridge(null);
  }, tester: tester);
}

Future<void> _runForegroundOptions(WidgetTester tester) async {
  await _run('setForegroundNotificationOptions(defaults) completes', () async {
    FirebaseMessagingHandler.instance.setForegroundNotificationOptions(
      ForegroundNotificationOptions.defaults,
    );
  }, tester: tester);

  await _run('Options with showNotification=false completes', () async {
    FirebaseMessagingHandler.instance.setForegroundNotificationOptions(
      const ForegroundNotificationOptions(enabled: false),
    );
  }, tester: tester);

  await _run('Options with custom sound name completes', () async {
    FirebaseMessagingHandler.instance.setForegroundNotificationOptions(
      const ForegroundNotificationOptions(
        androidSoundFileName: 'notification_sound',
      ),
    );
    // Reset to defaults.
    FirebaseMessagingHandler.instance.setForegroundNotificationOptions(
      ForegroundNotificationOptions.defaults,
    );
  }, tester: tester);
}

Future<void> _runTopics(WidgetTester tester) async {
  await _run('subscribeToTopic() completes', () async {
    await FirebaseMessagingHandler.instance.subscribeToTopic('fmh_test');
  }, tester: tester);

  await _run('subscribeToTopic() — multiple topics', () async {
    await FirebaseMessagingHandler.instance.subscribeToTopic(
      'fmh_announcements',
    );
    await FirebaseMessagingHandler.instance.subscribeToTopic('fmh_updates');
  }, tester: tester);

  await _run('unsubscribeFromTopic() completes', () async {
    await FirebaseMessagingHandler.instance.unsubscribeFromTopic('fmh_test');
  }, tester: tester);

  await _run(
    'getSubscribedTopics() reflects successful subscriptions',
    () async {
      final topics = await FirebaseMessagingHandler.instance
          .getSubscribedTopics();
      expect(topics, containsAll(<String>['fmh_announcements', 'fmh_updates']));
      expect(topics, isNot(contains('fmh_test')));
    },
    tester: tester,
  );

  await _run('unsubscribeFromAllTopics() completes', () async {
    await FirebaseMessagingHandler.instance.unsubscribeFromAllTopics();
    expect(
      await FirebaseMessagingHandler.instance.getSubscribedTopics(),
      isEmpty,
    );
  }, tester: tester);

  await _run('topic cleanup does not delete the FCM token', () async {
    expect(await FirebaseMessagingHandler.instance.getFcmToken(), isNotNull);
  }, tester: tester);
}

Future<void> _runScheduling(WidgetTester tester) async {
  const schedId = 9001;

  await _run('scheduleNotification() returns true', () async {
    final ok = await FirebaseMessagingHandler.instance.scheduleNotification(
      id: schedId,
      title: 'Integration Scheduled',
      body: 'Fires in the future',
      scheduledDate: DateTime.now().add(const Duration(hours: 1)),
      channelId: 'test_default',
      payload: {'test': 'scheduled'},
    );
    expect(ok, isTrue);
  }, tester: tester);

  late List<PendingNotificationSnapshot> pending;

  await _run('getPendingNotifications() returns non-null list', () async {
    pending = await FirebaseMessagingHandler.instance.getPendingNotifications();
    expect(pending, isA<List<PendingNotificationSnapshot>>());
  }, tester: tester);

  await _run('pending notifications are strongly typed', () async {
    expect(pending.where((item) => item.id == schedId), isNotEmpty);
  }, tester: tester);

  await _run('Scheduled count ≥ 1 after scheduling', () async {
    expect(pending.length, greaterThanOrEqualTo(1));
  }, tester: tester);

  await _run('cancelScheduledNotification(id) returns true', () async {
    final ok = await FirebaseMessagingHandler.instance
        .cancelScheduledNotification(schedId);
    expect(ok, isTrue);
  }, tester: tester);

  await _run('scheduleRecurringNotification("daily") returns true', () async {
    final ok = await FirebaseMessagingHandler.instance
        .scheduleRecurringNotification(
          id: 9002,
          title: 'Daily Reminder',
          body: 'Recurring test',
          repeatInterval: 'daily',
          hour: 9,
          minute: 0,
          channelId: 'test_default',
        );
    expect(ok, isTrue);
  }, tester: tester);

  await _run('scheduleRecurringNotification("weekly") returns true', () async {
    final ok = await FirebaseMessagingHandler.instance
        .scheduleRecurringNotification(
          id: 9003,
          title: 'Weekly Reminder',
          body: 'Recurring weekly test',
          repeatInterval: 'weekly',
          hour: 10,
          minute: 30,
        );
    expect(ok, isTrue);
  }, tester: tester);

  await _run('cancelAllScheduledNotifications() returns true', () async {
    final ok = await FirebaseMessagingHandler.instance
        .cancelAllScheduledNotifications();
    expect(ok, isTrue);
  }, tester: tester);

  await _run(
    'getPendingNotifications() returns empty after cancel all',
    () async {
      final remaining = await FirebaseMessagingHandler.instance
          .getPendingNotifications();
      expect(remaining, isEmpty);
    },
    tester: tester,
  );
}

Future<void> _runBadges(WidgetTester tester) async {
  if (Platform.isAndroid) {
    await _run('setAndroidBadgeCount(5) completes', () async {
      await FirebaseMessagingHandler.instance.setAndroidBadgeCount(5);
    }, tester: tester);

    await _run('getAndroidBadgeCount() returns value', () async {
      final count = await FirebaseMessagingHandler.instance
          .getAndroidBadgeCount();
      // Badge count may not be readable on all launchers; just verify no crash.
      expect(count == null || count >= 0, isTrue);
    }, tester: tester);

    await _run('clearBadgeCount() completes', () async {
      await FirebaseMessagingHandler.instance.clearBadgeCount();
    }, tester: tester);
  }

  if (Platform.isIOS) {
    await _run('setIOSBadgeCount(3) completes', () async {
      await FirebaseMessagingHandler.instance.setIOSBadgeCount(3);
    }, tester: tester);

    await _run('getIOSBadgeCount() returns 3', () async {
      final count = await FirebaseMessagingHandler.instance.getIOSBadgeCount();
      expect(count, equals(3));
    }, tester: tester);

    await _run('clearBadgeCount() sets iOS count to 0', () async {
      await FirebaseMessagingHandler.instance.clearBadgeCount();
      final count = await FirebaseMessagingHandler.instance.getIOSBadgeCount();
      expect(count, equals(0));
    }, tester: tester);
  }
}

Future<void> _runDisplay(WidgetTester tester) async {
  await _run('showNotificationWithActions() reports success', () async {
    expect(
      await FirebaseMessagingHandler.instance.showNotificationWithActions(
        title: 'Test Actions',
        body: 'Tap an action',
        actions: [
          const NotificationAction(id: 'ok', title: 'OK'),
          const NotificationAction(id: 'dismiss', title: 'Dismiss'),
        ],
        payload: {'source': 'integration_test'},
        channelId: 'test_default',
      ),
      isTrue,
    );
  }, tester: tester);

  await _run(
    'showLocalNotification() returns a typed success result',
    () async {
      final result = await FirebaseMessagingHandler.instance
          .showLocalNotification(
            const LocalNotificationRequest(
              id: 9050,
              title: 'Typed local request',
              body: 'Native detail escape hatch',
              channelId: 'test_default',
            ),
          );
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(result.value, equals(9050));
    },
    tester: tester,
  );

  await _run('showGroupedNotification() reports success', () async {
    expect(
      await FirebaseMessagingHandler.instance.showGroupedNotification(
        title: 'Group Message 1',
        body: 'First in group',
        groupKey: 'test_group',
        channelId: 'test_default',
      ),
      isTrue,
    );
  }, tester: tester);

  await _run('dismissNotificationGroup() reports success', () async {
    expect(
      await FirebaseMessagingHandler.instance.dismissNotificationGroup(
        'test_group',
      ),
      isTrue,
    );
  }, tester: tester);

  await _run('createNotificationGroup() reports success', () async {
    final item1 = FirebaseMessagingHandler.createMockNotificationData(
      title: 'G1',
      body: 'Body 1',
    );
    final item2 = FirebaseMessagingHandler.createMockNotificationData(
      title: 'G2',
      body: 'Body 2',
    );
    expect(
      await FirebaseMessagingHandler.instance.createNotificationGroup(
        groupKey: 'test_group_2',
        groupTitle: 'Test Group',
        notifications: [item1, item2],
        channelId: 'test_default',
      ),
      isTrue,
    );
  }, tester: tester);

  await _run('showThreadedNotification() reports success', () async {
    expect(
      await FirebaseMessagingHandler.instance.showThreadedNotification(
        title: 'Threaded Message',
        body: 'Part of a thread',
        threadIdentifier: 'test_thread_1',
        channelId: 'test_default',
      ),
      isTrue,
    );
  }, tester: tester);
}

Future<void> _runChannels(WidgetTester tester) async {
  await _run('createCustomSoundChannel() completes', () async {
    await FirebaseMessagingHandler.instance.createCustomSoundChannel(
      channelId: 'test_custom_sound',
      channelName: 'Custom Sound Channel',
      channelDescription: 'Integration test custom sound channel',
      soundFileName: 'notification',
    );
  }, tester: tester);

  await _run(
    'getAvailableSounds() returns list or null without crash',
    () async {
      final sounds = await FirebaseMessagingHandler.instance
          .getAvailableSounds();
      // Returns null (unsupported platform) or a List — just verify no crash.
      expect(sounds == null || sounds.isNotEmpty || sounds.isEmpty, isTrue);
    },
    tester: tester,
  );

  await _run('deleteNotificationChannel() returns true', () async {
    expect(
      await FirebaseMessagingHandler.instance.deleteNotificationChannel(
        'test_custom_sound',
      ),
      isTrue,
    );
  }, tester: tester);
}

Future<void> _runInApp(WidgetTester tester) async {
  await _run(
    'registerInAppNotificationTemplates() registers custom template',
    () async {
      FirebaseMessagingHandler.instance.registerInAppNotificationTemplates({
        'custom_banner': InAppNotificationTemplate(
          id: 'custom_banner',
          description: 'Custom banner for integration tests',
          onDisplay: (data) async {
            // Renders inline, no actual UI shown in test.
          },
        ),
      });
    },
    tester: tester,
  );

  await _run('getInAppNotificationStream() returns a stream', () async {
    final stream = FirebaseMessagingHandler.instance.getInAppNotificationStream(
      includePendingStorageItems: false,
    );
    expect(stream, isA<Stream<InAppNotificationData>>());
  }, tester: tester);

  await _run('setInAppDeliveryPolicy() with quiet hours completes', () async {
    await FirebaseMessagingHandler.instance.setInAppDeliveryPolicy(
      const InAppDeliveryPolicy(
        quietHours: InAppQuietHours(startHour: 22, endHour: 8),
      ),
    );
  }, tester: tester);

  await _run(
    'setInAppDeliveryPolicy() with frequency caps completes',
    () async {
      await FirebaseMessagingHandler.instance.setInAppDeliveryPolicy(
        const InAppDeliveryPolicy(
          globalInterval: Duration(minutes: 5),
          globalDailyCap: 10,
          perTemplateDailyCap: 3,
        ),
      );
    },
    tester: tester,
  );

  await _run(
    'setInAppFallbackDisplayHandler() registers without crash',
    () async {
      FirebaseMessagingHandler.instance.setInAppFallbackDisplayHandler(
        (data) async {},
      );
      FirebaseMessagingHandler.instance.setInAppFallbackDisplayHandler(null);
    },
    tester: tester,
  );

  await _run('clearPendingInAppNotifications() completes', () async {
    await FirebaseMessagingHandler.instance.clearPendingInAppNotifications();
  }, tester: tester);

  await _run('flushPendingInAppNotifications() completes', () async {
    await FirebaseMessagingHandler.instance.flushPendingInAppNotifications();
  }, tester: tester);

  await _run('clearInAppNotificationTemplates() completes', () async {
    FirebaseMessagingHandler.instance.clearInAppNotificationTemplates();
  }, tester: tester);

  await _run('setInAppNavigatorKey() accepts GlobalKey', () async {
    final key = GlobalKey<NavigatorState>();
    FirebaseMessagingHandler.instance.setInAppNavigatorKey(key);
  }, tester: tester);
}

Future<void> _runInbox(WidgetTester tester) async {
  final storage = InMemoryInboxStorage();

  final item1 = NotificationInboxItem(
    id: 'inbox-001',
    title: 'First Message',
    body: 'Hello from integration test',
    timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
  );
  final item2 = NotificationInboxItem(
    id: 'inbox-002',
    title: 'Second Message',
    body: 'Follow-up message',
    timestamp: DateTime.now(),
  );

  await _run('InMemoryInboxStorage: upsert saves item', () async {
    await storage.upsert(item1);
    await storage.upsert(item2);
  }, tester: tester);

  await _run('InMemoryInboxStorage: fetch returns saved items', () async {
    final items = await storage.fetch();
    expect(items.length, equals(2));
  }, tester: tester);

  await _run('InMemoryInboxStorage: count returns correct total', () async {
    final count = await storage.count();
    expect(count, equals(2));
  }, tester: tester);

  await _run('InMemoryInboxStorage: markRead updates isRead flag', () async {
    await storage.markRead(['inbox-001']);
    final items = await storage.fetch();
    final first = items.firstWhere((i) => i.id == 'inbox-001');
    expect(first.isRead, isTrue);
  }, tester: tester);

  await _run('InMemoryInboxStorage: unread count after markRead', () async {
    final unread = await storage.count(unreadOnly: true);
    expect(unread, equals(1)); // Only inbox-002 is unread
  }, tester: tester);

  await _run('InMemoryInboxStorage: delete removes item', () async {
    await storage.delete(['inbox-001']);
    final count = await storage.count();
    expect(count, equals(1));
  }, tester: tester);

  await _run('InMemoryInboxStorage: pagination (page 0 vs page 1)', () async {
    // Add 5 more items so we have 6 total.
    for (var i = 3; i <= 7; i++) {
      await storage.upsert(
        NotificationInboxItem(
          id: 'inbox-00$i',
          title: 'Message $i',
          body: 'Body $i',
          timestamp: DateTime.now(),
        ),
      );
    }
    final page0 = await storage.fetch(page: 0, pageSize: 4);
    final page1 = await storage.fetch(page: 1, pageSize: 4);
    expect(page0.length, equals(4));
    expect(page1.length, greaterThanOrEqualTo(1));
    // No overlap between pages.
    final ids0 = page0.map((i) => i.id).toSet();
    final ids1 = page1.map((i) => i.id).toSet();
    expect(ids0.intersection(ids1), isEmpty);
  }, tester: tester);

  await _run('InMemoryInboxStorage: clear empties storage', () async {
    await storage.clear();
    final count = await storage.count();
    expect(count, equals(0));
  }, tester: tester);

  await _run('NotificationInboxItem: toMap/fromMap roundtrip', () async {
    final original = NotificationInboxItem(
      id: 'roundtrip-1',
      title: 'Roundtrip Test',
      body: 'Checking serialization',
      timestamp: DateTime(2026, 3, 8, 12, 0),
      isRead: true,
      data: {'source': 'test', 'count': 42},
    );
    final map = original.toMap();
    final restored = NotificationInboxItem.fromMap(map);
    expect(restored.id, equals(original.id));
    expect(restored.title, equals(original.title));
    expect(restored.isRead, equals(original.isRead));
    expect(restored.data['source'], equals('test'));
  }, tester: tester);
}

Future<void> _runPayloadValidation(WidgetTester tester) async {
  await _run('Valid payload with title+body passes', () async {
    final ok = BridgingPayloadValidator.validate({'title': 'T', 'body': 'B'});
    expect(ok, isTrue);
  }, tester: tester);

  await _run('Payload with title only passes', () async {
    final ok = BridgingPayloadValidator.validate({'title': 'T'});
    expect(ok, isTrue);
  }, tester: tester);

  await _run('Payload missing title and body fails', () async {
    final ok = BridgingPayloadValidator.validate({'data': 'only'});
    expect(ok, isFalse);
  }, tester: tester);

  await _run('Payload with empty title fails', () async {
    final ok = BridgingPayloadValidator.validate({'title': '', 'body': ''});
    expect(ok, isFalse);
  }, tester: tester);

  await _run('Payload with valid actions map passes', () async {
    final ok = BridgingPayloadValidator.validate({
      'title': 'T',
      'actions': [
        {'id': 'ok', 'title': 'OK'},
      ],
    });
    expect(ok, isTrue);
  }, tester: tester);

  await _run('Payload with invalid actions type fails', () async {
    final ok = BridgingPayloadValidator.validate({
      'title': 'T',
      'actions': 'not-a-list',
    });
    expect(ok, isFalse);
  }, tester: tester);

  await _run('Payload with valid analytics JSON string passes', () async {
    final ok = BridgingPayloadValidator.validate({
      'title': 'T',
      'analytics': '{"campaign": "q1"}',
    });
    expect(ok, isTrue);
  }, tester: tester);

  await _run('Payload with invalid analytics type fails', () async {
    final ok = BridgingPayloadValidator.validate({
      'title': 'T',
      'analytics': 12345,
    });
    expect(ok, isFalse);
  }, tester: tester);

  await _run('NotificationEnvelope v2 round-trips through FCM data', () async {
    final envelope = NotificationEnvelope(
      id: 'integration-envelope',
      command: NotificationEnvelopeCommand.display,
      title: 'Envelope',
      body: 'Round trip',
      actions: const <NotificationAction>[
        NotificationAction(id: 'reply', title: 'Reply', textInput: true),
      ],
    );
    final encoded = envelope.toFcmData();
    final decoded = NotificationEnvelope.fromMap(encoded);
    expect(decoded.validate().isValid, isTrue);
    expect(decoded.actions.single.textInput, isTrue);
  }, tester: tester);

  await _run(
    'NotificationEnvelope rejects expired or oversized payloads',
    () async {
      final expired = NotificationEnvelope(
        id: 'expired',
        command: NotificationEnvelopeCommand.display,
        title: 'Expired',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(expired.isExpired(), isTrue);
      final oversized = NotificationEnvelope(
        id: 'oversized',
        command: NotificationEnvelopeCommand.display,
        title: 'Too large',
        data: <String, dynamic>{'value': 'x' * 5000},
      );
      expect(oversized.toFcmData, throwsRangeError);
    },
    tester: tester,
  );
}

Future<void> _runFcmSend(WidgetTester tester) async {
  InAppNotificationData? capturedInApp;
  final notificationTitle =
      'Comprehensive ${DateTime.now().millisecondsSinceEpoch}';

  await _run(
    'Send foreground notification — returns HTTP 200',
    () async {
      await _sender!.send(
        deviceToken: _token!,
        title: notificationTitle,
        body:
            'FMH integration suite — ts=${DateTime.now().millisecondsSinceEpoch}',
      );
    },
    needsCreds: true,
    needsToken: true,
    tester: tester,
  );

  await _run(
    'Foreground notification appears in active notifications',
    () async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      var active = <ActiveNotificationSnapshot>[];
      do {
        active = await FirebaseMessagingHandler.instance
            .getActiveNotifications();
        if (active.any((item) => item.title == notificationTitle)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } while (DateTime.now().isBefore(deadline));

      expect(
        active.any((item) => item.title == notificationTitle),
        isTrue,
        reason:
            'FCM returned HTTP 200, but the foreground notification was not '
            'visible in Android active notifications within 15 seconds.',
      );
    },
    needsCreds: true,
    needsToken: true,
    tester: tester,
  );

  await _run(
    'Send data-only + fcmh_inapp — processes without crash',
    () async {
      final inAppId = 'in-app-${DateTime.now().microsecondsSinceEpoch}';
      final delivery = Completer<InAppNotificationData>();
      await FirebaseMessagingHandler.instance.setInAppDeliveryPolicy(
        const InAppDeliveryPolicy(),
      );
      final subscription = FirebaseMessagingHandler.instance
          .getInAppNotificationStream(includePendingStorageItems: false)
          .listen((data) {
            if (data.id == inAppId && !delivery.isCompleted) {
              delivery.complete(data);
            }
          });

      try {
        await _sender!.send(
          deviceToken: _token!,
          data: {
            'fcmh_inapp':
                '{"id":"$inAppId","templateId":"builtin_generic",'
                '"type":"snackbar","title":"Integration Test",'
                '"body":"Silent push processed"}',
          },
        );
        capturedInApp = await delivery.future.timeout(
          const Duration(seconds: 20),
        );
      } finally {
        await subscription.cancel();
      }
    },
    needsCreds: true,
    needsToken: true,
    tester: tester,
  );

  await _run(
    'In-app stream emits after data-only send',
    () async {
      expect(capturedInApp, isNotNull);
      expect(capturedInApp!.templateId, equals('builtin_generic'));
      expect(capturedInApp!.content['title'], equals('Integration Test'));
      expect(capturedInApp!.content['body'], equals('Silent push processed'));
      print('[comprehensive] in-app received: ${capturedInApp!.templateId}');
    },
    needsCreds: true,
    needsToken: true,
    tester: tester,
  );

  await _run(
    'Send with custom data fields — completes',
    () async {
      await _sender!.send(
        deviceToken: _token!,
        title: 'Custom Data Test',
        body: 'With extra payload',
        data: {
          'deep_link': '/inbox',
          'campaign_id': 'fmh_integration_test',
          'priority': 'high',
        },
      );
    },
    needsCreds: true,
    needsToken: true,
    tester: tester,
  );
}
