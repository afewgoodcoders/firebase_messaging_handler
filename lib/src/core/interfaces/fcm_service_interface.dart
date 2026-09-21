import 'package:firebase_messaging/firebase_messaging.dart';

import '../../models/notification_permission_options.dart';

/// Interface for Firebase Cloud Messaging service operations
abstract class FCMServiceInterface {
  /// Initializes the FCM service
  Future<bool> initialize();

  /// Requests notification permissions
  Future<bool> requestPermissions({
    NotificationPermissionOptions options =
        const NotificationPermissionOptions(),
  });

  /// Requests permission and returns the complete platform settings.
  Future<NotificationSettings> requestPermissionSettings({
    NotificationPermissionOptions options =
        const NotificationPermissionOptions(),
  });

  /// Gets the FCM token
  Future<String?> getToken({String? vapidKey});

  /// Subscribes to a topic
  Future<void> subscribeToTopic(String topic);

  /// Unsubscribes from a topic
  Future<void> unsubscribeFromTopic(String topic);

  /// Deletes the FCM token
  Future<void> deleteToken();

  /// Gets the initial message if app was opened from notification
  Future<dynamic> getInitialMessage();

  /// Stream for foreground messages
  Stream<dynamic> get onMessage;

  /// Stream for background messages
  Stream<dynamic> get onMessageOpenedApp;

  /// Stream for background message handler
  Stream<dynamic> get onBackgroundMessage;

  /// Stream for token refresh events
  Stream<String> get onTokenRefresh;

  /// Returns the current notification permission settings
  Future<NotificationSettings> getNotificationSettings();

  /// Registers the background message handler.
  Future<void> setBackgroundMessageHandler(
    Future<void> Function(RemoteMessage message) handler,
  );

  /// Sets foreground notification presentation options
  Future<void> setForegroundNotificationPresentationOptions({
    bool alert = true,
    bool badge = true,
    bool sound = true,
  });

  /// Enables or disables Firebase delivery-metrics export where supported.
  Future<void> setDeliveryMetricsExportToBigQuery(bool enabled);
}
