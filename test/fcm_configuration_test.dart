import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FCMConfiguration', () {
    test('round-trips categories and delivery policy', () {
      const FCMConfiguration configuration = FCMConfiguration(
        senderId: 'sender',
        webVapidKey: 'vapid',
        requestPermissionOnInitialize: true,
        permissionOptions: NotificationPermissionOptions(provisional: true),
        synchronizeTokenOnInitialize: true,
        exportDeliveryMetricsToBigQuery: true,
        analyticsOptions: NotificationAnalyticsOptions(
          privacy: NotificationAnalyticsPrivacy.fullPayload,
        ),
        actionCategories: <NotificationActionCategory>[
          NotificationActionCategory(
            id: 'messages',
            actions: <NotificationAction>[
              NotificationAction(id: 'reply', title: 'Reply', textInput: true),
            ],
          ),
        ],
        notificationCategories: <NotificationCategory>[
          NotificationCategory(
            id: 'orders',
            name: 'Orders',
            defaultEnabled: false,
          ),
        ],
        deliveryPolicy: NotificationDeliveryPolicy(
          quietHours: NotificationQuietHours(
            startHour: 22,
            startMinute: 30,
            endHour: 7,
          ),
          globalInterval: Duration(minutes: 5),
          perCategoryInterval: Duration(minutes: 15),
          globalDailyCap: 20,
          perCategoryDailyCap: 5,
        ),
      );

      final FCMConfiguration decoded = FCMConfiguration.fromMap(
        configuration.toMap(),
      );

      expect(decoded.senderId, 'sender');
      expect(decoded.webVapidKey, 'vapid');
      expect(decoded.requestPermissionOnInitialize, isTrue);
      expect(decoded.permissionOptions.provisional, isTrue);
      expect(decoded.synchronizeTokenOnInitialize, isTrue);
      expect(decoded.exportDeliveryMetricsToBigQuery, isTrue);
      expect(
        decoded.analyticsOptions.privacy,
        NotificationAnalyticsPrivacy.fullPayload,
      );
      expect(decoded.actionCategories.single.actions.single.textInput, isTrue);
      expect(decoded.notificationCategories.single.id, 'orders');
      expect(decoded.notificationCategories.single.defaultEnabled, isFalse);
      expect(decoded.deliveryPolicy.quietHours?.startMinute, 30);
      expect(decoded.deliveryPolicy.globalInterval, const Duration(minutes: 5));
      expect(decoded.deliveryPolicy.perCategoryDailyCap, 5);
    });

    test('uses privacy-preserving v2 initialization defaults', () {
      const FCMConfiguration configuration = FCMConfiguration();

      expect(configuration.requestPermissionOnInitialize, isFalse);
      expect(configuration.synchronizeTokenOnInitialize, isFalse);
      expect(configuration.enableDebugLogging, isFalse);
      expect(configuration.exportDeliveryMetricsToBigQuery, isFalse);
      expect(
        configuration.analyticsOptions.privacy,
        NotificationAnalyticsPrivacy.metadataOnly,
      );
    });

    test('rejects duplicate category IDs', () {
      const FCMConfiguration configuration = FCMConfiguration(
        notificationCategories: <NotificationCategory>[
          NotificationCategory(id: 'orders', name: 'Orders'),
          NotificationCategory(id: 'orders', name: 'Duplicate'),
        ],
      );

      expect(configuration.isValid, isFalse);
      expect(
        configuration.validationErrors,
        contains('Notification category IDs must be unique: orders'),
      );
    });
  });
}
