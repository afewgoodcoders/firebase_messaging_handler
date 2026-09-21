import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';

typedef AnalyticsCallback =
    FutureOr<void> Function(String event, Map<String, dynamic> data);

/// Interface for analytics service operations
abstract class AnalyticsServiceInterface {
  /// Tracks an analytics event
  Future<void> trackEvent(String event, Map<String, dynamic> data);

  /// Sets the analytics callback
  void setCallback(AnalyticsCallback callback);

  /// Gets the current platform
  String getCurrentPlatform();

  /// Tracks notification received event
  Future<void> trackNotificationReceived(RemoteMessage message);

  /// Tracks notification clicked event
  Future<void> trackNotificationClicked(RemoteMessage message);

  /// Tracks notification scheduled event
  Future<void> trackNotificationScheduled(Map<String, dynamic> data);

  /// Tracks FCM token event
  Future<void> trackTokenEvent(String event, String? token);
}
