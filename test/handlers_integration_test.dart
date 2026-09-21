import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Integration-style harness without real FCM: exercises background/foreground
/// paths using synthetic RemoteMessage instances.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FirebaseMessagingHandler.setTestMode(true);

  group('Unified handler + inbox integration (synthetic messages)', () {
    late List<NotificationData?> clicks;
    late List<NormalizedMessage> unified;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FirebaseMessagingHandler.resetMockData();
      clicks = <NotificationData?>[];
      unified = <NormalizedMessage>[];

      await FirebaseMessagingHandler.instance.setUnifiedMessageHandler((
        normalized,
        lifecycle,
      ) async {
        unified.add(normalized);
        return true; // mark handled to avoid queuing
      });
    });

    tearDown(() async {
      await FirebaseMessagingHandler.instance.setUnifiedMessageHandler(null);
    });

    test(
      'background dispatcher feeds unified handler and click stream',
      () async {
        final RemoteMessage bgMessage =
            FirebaseMessagingHandler.createMockRemoteMessage(
              messageId: 'bg-1',
              title: 'BG Title',
              body: 'BG Body',
              data: <String, dynamic>{'foo': 'bar'},
            );

        // Simulate background handling
        await FirebaseMessagingHandler.handleBackgroundMessage(bgMessage);

        // Verify unified handler saw it
        expect(unified.length, 1);
        expect(unified.first.id, isNotEmpty);

        final clickSubscription = FirebaseMessagingHandler.getMockClickStream()
            ?.listen(clicks.add);

        // Simulate a tap after a background notification is delivered.
        FirebaseMessagingHandler.addMockClickEvent(
          FirebaseMessagingHandler.createMockNotificationData(
            title: 'BG Title',
            body: 'BG Body',
            payload: bgMessage.data,
            type: NotificationTypeEnum.background,
            messageId: bgMessage.messageId,
          ),
        );

        // Allow stream events
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(clicks.length, 1);
        expect(clicks.first?.title, 'BG Title');
        await clickSubscription?.cancel();
      },
    );

    test('background dispatcher runs explicit bootstrap first', () async {
      var bootstrapped = false;
      final RemoteMessage message =
          FirebaseMessagingHandler.createMockRemoteMessage(
            messageId: 'bootstrap-1',
            title: 'Bootstrapped',
          );

      await FirebaseMessagingHandler.handleBackgroundMessage(
        message,
        bootstrap: () async {
          bootstrapped = true;
        },
      );

      expect(bootstrapped, isTrue);
      expect(unified.single.id, 'bootstrap-1');
    });

    test('foreground message hits unified handler', () async {
      final RemoteMessage fgMessage =
          FirebaseMessagingHandler.createMockRemoteMessage(
            messageId: 'fg-1',
            title: 'FG Title',
            body: 'FG Body',
          );

      final clickSubscription = FirebaseMessagingHandler.getMockClickStream()
          ?.listen(clicks.add);

      FirebaseMessagingHandler.addMockNotification(fgMessage);
      FirebaseMessagingHandler.addMockClickEvent(
        FirebaseMessagingHandler.createMockNotificationData(
          title: 'FG Title',
          body: 'FG Body',
          payload: fgMessage.data,
          type: NotificationTypeEnum.foreground,
          messageId: fgMessage.messageId,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(unified.length, 1);
      expect(unified.first.title, 'FG Title');
      expect(clicks.length, 1);
      expect(clicks.first?.title, 'FG Title');
      await clickSubscription?.cancel();
    });

    test('normalizes JSON actions from an FCM data payload', () async {
      final RemoteMessage message =
          FirebaseMessagingHandler.createMockRemoteMessage(
            messageId: 'actions-1',
            title: 'New message',
            data: <String, dynamic>{
              'actions': '[{"id":"reply","title":"Reply","textInput":true}]',
              'analytics': '{"campaign":"messages"}',
            },
          );

      FirebaseMessagingHandler.addMockNotification(message);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(unified, hasLength(1));
      expect(unified.single.actions, hasLength(1));
      expect(unified.single.actions!.single.textInput, isTrue);
      expect(unified.single.analytics?['campaign'], 'messages');
    });
  });
}
