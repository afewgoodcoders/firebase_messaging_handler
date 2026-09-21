import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationEnvelope', () {
    test('round-trips through string-only FCM data', () {
      final DateTime sentAt = DateTime.utc(2026, 9, 20, 10);
      final NotificationEnvelope envelope = NotificationEnvelope(
        id: 'order-42',
        idempotencyKey: 'order-42-paid',
        title: 'Order paid',
        body: 'Your receipt is ready.',
        category: 'orders',
        route: '/orders/42',
        actions: const <NotificationAction>[
          NotificationAction(id: 'open', title: 'Open'),
          NotificationAction(
            id: 'reply',
            title: 'Reply',
            textInput: true,
            inputLabel: 'Message',
          ),
        ],
        timeToLive: const Duration(hours: 1),
        remotePresentation: NotificationRemotePresentation.system,
        sentAt: sentAt,
        analytics: const <String, dynamic>{'campaign': 'receipt'},
        platform: const <String, dynamic>{
          'android': <String, dynamic>{'tag': 'order-42'},
        },
        data: const <String, dynamic>{'orderId': 42},
      );

      final Map<String, String> encoded = envelope.toFcmData();
      expect(encoded.values, everyElement(isA<String>()));

      final NotificationEnvelope decoded = NotificationEnvelope.fromMap(
        encoded,
      );
      expect(decoded.id, 'order-42');
      expect(decoded.actions, hasLength(2));
      expect(decoded.actions.last.textInput, isTrue);
      expect(decoded.timeToLive, const Duration(hours: 1));
      expect(decoded.remotePresentation, NotificationRemotePresentation.system);
      expect(decoded.analytics['campaign'], 'receipt');
      expect(decoded.data['orderId'], 42);
      expect(decoded.validate().isValid, isTrue);
    });

    test('allows content-free cancel commands', () {
      const NotificationEnvelope envelope = NotificationEnvelope(
        id: 'order-42',
        command: NotificationEnvelopeCommand.cancel,
      );

      expect(envelope.validate().isValid, isTrue);
      expect(
        NotificationEnvelope.fromMap(envelope.toFcmData()).command,
        NotificationEnvelopeCommand.cancel,
      );
    });

    test('rejects duplicate actions and reserved application keys', () {
      const NotificationEnvelope envelope = NotificationEnvelope(
        id: 'message-1',
        title: 'Hello',
        actions: <NotificationAction>[
          NotificationAction(id: 'open', title: 'Open'),
          NotificationAction(id: 'open', title: 'Again'),
        ],
        data: <String, dynamic>{'title': 'reserved'},
      );

      expect(
        envelope.validate().errors,
        containsAll(<String>[
          'action IDs must be unique: open',
          'data key "title" is reserved by the v2 envelope',
        ]),
      );
    });

    test('detects expiry from absolute time or TTL', () {
      final DateTime now = DateTime.utc(2026, 9, 20, 12);
      final NotificationEnvelope envelope = NotificationEnvelope(
        id: 'expiring',
        title: 'Soon',
        sentAt: now.subtract(const Duration(minutes: 2)),
        timeToLive: const Duration(minutes: 1),
      );

      expect(envelope.isExpired(now), isTrue);
    });

    test('rejects TTLs beyond FCM limits and non-positive expiry windows', () {
      final DateTime sentAt = DateTime.utc(2026, 9, 20, 12);
      final NotificationEnvelope tooLong = NotificationEnvelope(
        id: 'too-long',
        title: 'Too long',
        timeToLive: const Duration(days: 28, seconds: 1),
      );
      final NotificationEnvelope noWindow = NotificationEnvelope(
        id: 'no-window',
        title: 'No window',
        sentAt: sentAt,
        expiresAt: sentAt,
      );

      expect(
        tooLong.validate().errors,
        contains('timeToLive must be between zero and 28 days'),
      );
      expect(
        noWindow.validate().errors,
        contains('expiresAt must be later than sentAt'),
      );
    });

    test('enforces the conservative FCM data size limit', () {
      final NotificationEnvelope envelope = NotificationEnvelope(
        id: 'large',
        title: 'Large',
        data: <String, dynamic>{'blob': List<String>.filled(5000, 'x').join()},
      );

      expect(envelope.toFcmData, throwsA(isA<RangeError>()));
    });
  });
}
