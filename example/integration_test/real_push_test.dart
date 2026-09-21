// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:firebase_messaging_handler_example/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fcm_test_sender.dart';

/// Real-FCM end-to-end integration tests.
///
/// The test app authenticates with Google via a service account embedded at
/// compile time (base64 via --dart-define), then POSTs a real FCM message to
/// fcm.googleapis.com.  Firebase delivers it back to this same device,
/// verifying the full round-trip without any external dashboard.
///
/// ────────────────────────────────────────────────────────────────────────────
/// HOW TO RUN (from example/ directory)
/// ────────────────────────────────────────────────────────────────────────────
///
///   BASE64=$(base64 -i ../test/firebase_config/service_account.json | tr -d '\n')
///
///   flutter test integration_test/real_push_test.dart \
///     --dart-define=FCM_TEST_SENDER_ID=your-project-number \
///     --dart-define=FCM_SERVICE_ACCOUNT_B64=$BASE64 \
///     --device-id your-device-id
///
/// Without FCM_SERVICE_ACCOUNT_B64 all send-dependent tests SKIP (not fail),
/// so CI without credentials stays green.
/// ────────────────────────────────────────────────────────────────────────────

const _skipReason =
    'FCM_SERVICE_ACCOUNT_B64 not set — skipping real-FCM send tests. '
    'Pass via --dart-define=FCM_SERVICE_ACCOUNT_B64=<base64-encoded-json>.';

const _senderId = String.fromEnvironment(
  'FCM_TEST_SENDER_ID',
  defaultValue: '',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FcmTestSender? sender;
  late String? deviceToken;

  setUpAll(() async {
    // Firebase must be initialized before any FMH or FCM calls.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    sender = FcmTestSender.fromEnv();
    if (sender == null) {
      print('[real_push] No service account — send-dependent tests will skip.');
    }

    await FirebaseMessagingHandler.instance.initialize(
      FCMConfiguration(
        senderId: _senderId.isEmpty ? '000000000000' : _senderId,
        androidChannels: <NotificationChannelData>[
          NotificationChannelData(
            id: 'integration_test',
            name: 'Integration Tests',
            description: 'FCM real-push integration test channel',
          ),
        ],
        androidNotificationIconPath: '@mipmap/ic_launcher',
        requestPermissionOnInitialize: false,
        synchronizeTokenOnInitialize: false,
        updateTokenCallback: (_) async => true,
      ),
    );

    deviceToken = await FirebaseMessagingHandler.instance.getFcmToken();
    if (deviceToken != null) {
      await FirebaseMessagingHandler.instance.synchronizeToken(force: true);
    }

    print(
      '[real_push] token: '
      '${deviceToken != null ? '${deviceToken!.substring(0, 20)}…' : 'NULL'}',
    );
    if (deviceToken == null) {
      print(
        '[real_push] lastTokenError: '
        '${FirebaseMessagingHandler.instance.lastTokenError}',
      );
    }
  });

  // ── 1. Token retrieval ─────────────────────────────────────────────────────
  test('FCM token is available on real device', () async {
    expect(
      deviceToken,
      isNotNull,
      reason:
          FirebaseMessagingHandler.instance.lastTokenError ??
          'Token null but no error set',
    );
    expect(deviceToken, isNotEmpty);
    print('[real_push] ✓ token: ${deviceToken!.substring(0, 20)}…');
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ── 2. Permissions ─────────────────────────────────────────────────────────
  // On a fresh Android install the OS dialog can't be tapped in a headless
  // test, so we assert the wizard returns A result, not a specific status.
  // Pre-grant via ADB before running to promote to 'granted':
  //   adb shell pm grant <applicationId> android.permission.POST_NOTIFICATIONS
  test('Permission wizard returns a result without crashing', () async {
    final result = await FirebaseMessagingHandler.instance
        .requestPermissionsWizard();
    expect(result.overallStatus, isNotNull);
    expect(result.overallStatus, isNotEmpty);
    print('[real_push] ✓ permissions wizard status: ${result.overallStatus}');
    if (result.overallStatus != 'granted' &&
        result.overallStatus != 'provisional') {
      print(
        '[real_push] ⚠ Permissions not granted (status: '
        '${result.overallStatus}). '
        'Pre-grant with: adb shell pm grant <appId> '
        'android.permission.POST_NOTIFICATIONS',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 15)));

  // ── 3. Diagnostics ─────────────────────────────────────────────────────────
  test('runDiagnostics reports FCM token available', () async {
    final result = await FirebaseMessagingHandler.instance.runDiagnostics();
    print('[real_push] diagnostics: ${result.toMap()}');

    // Token must be available — this is the primary health indicator.
    expect(
      result.fcmTokenAvailable,
      isTrue,
      reason: 'FCM token not available. Error: ${result.error}',
    );
    // Platform must be identified correctly.
    expect(result.platform, isNotEmpty);
    print(
      '[real_push] ✓ diagnostics: token=${result.fcmTokenAvailable}, '
      'platform=${result.platform}, permissions=${result.permissionsGranted}',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ── 4. Foreground notification send ───────────────────────────────────────
  testWidgets('FCM v2 notification reaches the foreground handler '
      '[requires FCM_SERVICE_ACCOUNT_B64]', (tester) async {
    if (sender == null) {
      markTestSkipped(_skipReason);
      return;
    }
    if (deviceToken == null) {
      markTestSkipped(
        'No FCM token — ${FirebaseMessagingHandler.instance.lastTokenError}',
      );
      return;
    }

    final completer = Completer<NormalizedMessage>();
    final envelopeId = 'foreground-${DateTime.now().millisecondsSinceEpoch}';
    await FirebaseMessagingHandler.instance.setUnifiedMessageHandler((
      message,
      lifecycle,
    ) async {
      if (message.id == envelopeId && !completer.isCompleted) {
        completer.complete(message);
      }
      return true;
    });

    print('[real_push] sending foreground notification to device…');
    await sender!.send(
      deviceToken: deviceToken!,
      title: 'Integration Test',
      body: 'Tap this — ts=${DateTime.now().millisecondsSinceEpoch}',
      data: <String, String>{
        'schemaVersion': '2',
        'id': envelopeId,
        'idempotencyKey': envelopeId,
        'command': 'display',
      },
    );
    print('[real_push] ✓ FCM send returned 200');

    final NormalizedMessage received = await completer.future.timeout(
      const Duration(seconds: 20),
    );
    expect(received.id, envelopeId);
    expect(received.title, 'Integration Test');
    await FirebaseMessagingHandler.instance.setUnifiedMessageHandler(null);
  }, timeout: const Timeout(Duration(seconds: 25)));

  test('duplicate v2 idempotency key is processed once '
      '[requires FCM_SERVICE_ACCOUNT_B64]', () async {
    if (sender == null) {
      markTestSkipped(_skipReason);
      return;
    }
    if (deviceToken == null) {
      markTestSkipped('No FCM token');
      return;
    }
    final id = 'dedupe-${DateTime.now().millisecondsSinceEpoch}';
    var deliveries = 0;
    final first = Completer<void>();
    await FirebaseMessagingHandler.instance.setUnifiedMessageHandler((
      message,
      lifecycle,
    ) async {
      if (message.data['idempotencyKey'] == id) {
        deliveries += 1;
        if (!first.isCompleted) first.complete();
      }
      return true;
    });
    final data = <String, String>{
      'schemaVersion': '2',
      'id': id,
      'idempotencyKey': id,
      'command': 'display',
      'title': 'Dedupe test',
    };
    await sender!.send(deviceToken: deviceToken!, data: data);
    await first.future.timeout(const Duration(seconds: 20));
    await sender!.send(deviceToken: deviceToken!, data: data);
    await Future<void>.delayed(const Duration(seconds: 5));
    expect(deliveries, 1);
    await FirebaseMessagingHandler.instance.setUnifiedMessageHandler(null);
  }, timeout: const Timeout(Duration(seconds: 35)));

  // ── 5. Data-only / in-app trigger ─────────────────────────────────────────
  test('Data-only payload emits through the in-app stream '
      '[requires FCM_SERVICE_ACCOUNT_B64]', () async {
    if (sender == null) {
      markTestSkipped(_skipReason);
      return;
    }
    if (deviceToken == null) {
      markTestSkipped(
        'No FCM token — ${FirebaseMessagingHandler.instance.lastTokenError}',
      );
      return;
    }

    print('[real_push] sending data-only in-app payload…');
    final inAppId = 'real-in-app-${DateTime.now().microsecondsSinceEpoch}';
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
      await sender!.send(
        deviceToken: deviceToken!,
        data: {
          'fcmh_inapp': jsonEncode(<String, dynamic>{
            'id': inAppId,
            'templateId': 'builtin_generic',
            'type': 'dialog',
            'title': 'Integration Test',
            'body': 'Data-only payload ok',
          }),
        },
      );
      final received = await delivery.future.timeout(
        const Duration(seconds: 20),
      );
      expect(received.templateId, 'builtin_generic');
      expect(received.content['title'], 'Integration Test');
      expect(received.content['body'], 'Data-only payload ok');
      print('[real_push] ✓ data-only payload emitted through in-app stream');
    } finally {
      await subscription.cancel();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
