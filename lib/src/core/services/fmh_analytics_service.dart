import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../interfaces/analytics_service_interface.dart';
import '../utils/platform_utils.dart';
import '../../models/notification_analytics_options.dart';

/// Analytics service implementation
class FmhAnalyticsService implements AnalyticsServiceInterface {
  static FmhAnalyticsService? _instance;
  AnalyticsCallback? _analyticsCallback;
  NotificationAnalyticsOptions _options = const NotificationAnalyticsOptions();
  bool _debugLoggingEnabled = false;

  /// Singleton instance
  static FmhAnalyticsService get instance {
    _instance ??= FmhAnalyticsService._internal();
    return _instance!;
  }

  FmhAnalyticsService._internal();

  @override
  Future<void> trackEvent(String event, Map<String, dynamic> properties) async {
    try {
      if (_options.privacy == NotificationAnalyticsPrivacy.disabled) return;
      if (_analyticsCallback != null) {
        await _analyticsCallback!(event, properties);
      }
      _logMessage('[FmhAnalyticsService] Event tracked: $event');
    } catch (error, stack) {
      _logMessage('[FmhAnalyticsService] Track event error: $error');
      _logMessage('[FmhAnalyticsService] Stack trace: $stack');
    }
  }

  @override
  void setCallback(AnalyticsCallback callback) {
    _analyticsCallback = callback;
    _logMessage('[FmhAnalyticsService] Analytics callback set');
  }

  /// Applies analytics privacy settings before any future event is emitted.
  void configure(
    NotificationAnalyticsOptions options, {
    bool enableDebugLogging = false,
  }) {
    _options = options;
    _debugLoggingEnabled = enableDebugLogging;
  }

  @override
  String getCurrentPlatform() {
    if (isWeb) return 'web';
    if (isAndroid) return 'android';
    if (isIOS) return 'ios';
    if (isMacOS) return 'macos';
    if (isWindows) return 'windows';
    if (isLinux) return 'linux';
    if (isFuchsia) return 'fuchsia';
    return isWeb ? 'web' : 'unknown';
  }

  @override
  Future<void> trackNotificationReceived(RemoteMessage message) async {
    try {
      final Map<String, dynamic> properties = {
        'message_id': message.messageId,
        'sent_time': message.sentTime?.toIso8601String(),
        'has_notification': message.notification != null,
        'data_key_count': message.data.length,
        if (_options.privacy == NotificationAnalyticsPrivacy.fullPayload) ...{
          'title': message.notification?.title,
          'body': message.notification?.body,
          'data': message.data,
        },
      };

      await trackEvent('notification_received', properties);
    } catch (error, stack) {
      _logMessage(
        '[FmhAnalyticsService] Track notification received error: $error',
      );
      _logMessage('[FmhAnalyticsService] Stack trace: $stack');
    }
  }

  @override
  Future<void> trackNotificationClicked(RemoteMessage message) async {
    try {
      final Map<String, dynamic> properties = {
        'message_id': message.messageId,
        'sent_time': message.sentTime?.toIso8601String(),
        'action': 'click',
        if (_options.privacy == NotificationAnalyticsPrivacy.fullPayload) ...{
          'title': message.notification?.title,
          'body': message.notification?.body,
          'data': message.data,
        },
      };

      await trackEvent('notification_clicked', properties);
    } catch (error, stack) {
      _logMessage(
        '[FmhAnalyticsService] Track notification clicked error: $error',
      );
      _logMessage('[FmhAnalyticsService] Stack trace: $stack');
    }
  }

  @override
  Future<void> trackNotificationScheduled(Map<String, dynamic> data) async =>
      trackEvent('notification_scheduled', data);

  @override
  Future<void> trackTokenEvent(String eventType, String? token) async {
    try {
      final Map<String, dynamic> properties = {
        'token_present': token != null,
        'token_length': token?.length,
        'event_type': eventType,
        'timestamp': DateTime.now().toIso8601String(),
      };

      await trackEvent('token_event', properties);
    } catch (error, stack) {
      _logMessage('[FmhAnalyticsService] Track token event error: $error');
      _logMessage('[FmhAnalyticsService] Stack trace: $stack');
    }
  }

  void _logMessage(String message) {
    if (kDebugMode && _debugLoggingEnabled) {
      print(message);
    }
  }
}
