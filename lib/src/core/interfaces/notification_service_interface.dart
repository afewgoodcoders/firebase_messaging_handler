import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../models/export.dart';
import '../../enums/repeat_interval_enum.dart';

/// Interface for local notification service operations
abstract class NotificationServiceInterface {
  /// Initializes the local notification service
  Future<bool> initialize({
    required List<NotificationChannelData> androidChannels,
    required String androidIconPath,
    List<NotificationActionCategory> actionCategories =
        const <NotificationActionCategory>[],
    WindowsNotificationOptions? windows,
    bool enableDebugLogging = false,
  });

  /// Shows a local notification
  Future<bool> showNotification({
    required int id,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
    String? channelId,
    String? groupKey,
    String? sortKey,
    String? category,
    String? threadIdentifier,
    bool isGroupSummary = false,
    String? groupAlertSummary,
    AndroidNotificationDetails? androidDetailsOverride,
    DarwinNotificationDetails? iosDetailsOverride,
    LinuxNotificationDetails? linuxDetailsOverride,
    WindowsNotificationDetails? windowsDetailsOverride,
  });

  /// Shows a notification with actions
  Future<bool> showNotificationWithActions({
    required int id,
    required String title,
    required String body,
    required List<NotificationAction> actions,
    Map<String, dynamic>? payload,
    String? channelId,
    String? actionCategoryId,
  });

  /// Schedules a notification
  Future<bool> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    Map<String, dynamic>? payload,
    String? channelId,
    List<NotificationAction>? actions,
    String? actionCategoryId,
    NotificationScheduleMode scheduleMode = NotificationScheduleMode.inexact,
  });

  /// Schedules a recurring notification
  Future<bool> scheduleRecurringNotification({
    required int id,
    required String title,
    required String body,
    required RepeatIntervalEnum repeatInterval,
    required DateTime initialScheduleDate,
    Map<String, dynamic>? payload,
    String? channelId,
    List<NotificationAction>? actions,
  });

  /// Cancels a notification
  Future<bool> cancelNotification(int id);

  /// Cancels all notifications
  Future<bool> cancelAllNotifications();

  /// Gets pending notifications
  Future<List<PendingNotificationSnapshot>> getPendingNotifications();

  /// Gets notifications currently visible in the system notification UI.
  Future<List<ActiveNotificationSnapshot>> getActiveNotifications();

  /// Returns whether system notifications are enabled for this application.
  Future<bool?> areNotificationsEnabled();

  /// Deletes an Android notification channel created by the application.
  Future<bool> deleteNotificationChannel(String channelId);

  /// Refreshes the timezone used by scheduled notifications.
  Future<String?> refreshLocalTimezone();

  /// Returns the timezone currently configured for scheduling.
  Future<String?> getConfiguredLocalTimezone();

  /// Creates a notification channel
  Future<void> createNotificationChannel(NotificationChannelData channel);

  /// Gets notification app launch details
  Future<dynamic> getNotificationAppLaunchDetails();

  /// Checks if the current platform supports application icon badges
  Future<bool> isBadgeSupported();

  /// Returns the current browser notification permission (web only)
  Future<String> getWebNotificationPermissionStatus();

  /// Returns browser capability and runtime checks for web notification support.
  Future<Map<String, dynamic>> getWebRuntimeDiagnostics();

  /// Opens this app's notification settings when supported by the platform.
  Future<bool> openAppNotificationSettings();

  /// Whether Android can currently schedule exact alarms.
  Future<bool?> canScheduleExactNotifications();

  /// Opens or requests Android's exact-alarm permission flow.
  Future<bool> requestExactAlarmPermission();
}
