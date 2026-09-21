import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Snapshot of a foreground remote message used to build local presentation
/// options at display time.
class ForegroundNotificationContext {
  /// The original Firebase message being processed.
  final RemoteMessage message;

  /// Convenience access to `message.notification?.title`.
  final String? title;

  /// Convenience access to `message.notification?.body`.
  final String? body;

  /// Immutable copy of the message data payload.
  final Map<String, dynamic> data;

  /// Builds a presentation context from a foreground message.
  ForegroundNotificationContext({required this.message})
    : title = message.notification?.title,
      body = message.notification?.body,
      data = Map<String, dynamic>.unmodifiable(message.data);
}

/// Builds Android foreground notification details dynamically for a message.
typedef AndroidForegroundNotificationBuilder =
    FutureOr<AndroidNotificationDetails?> Function(
      ForegroundNotificationContext context,
    );

/// Builds iOS foreground notification details dynamically for a message.
typedef IOSForegroundNotificationBuilder =
    FutureOr<DarwinNotificationDetails?> Function(
      ForegroundNotificationContext context,
    );

/// Controls how foreground remote messages are translated into local
/// notifications when the app is active.
class ForegroundNotificationOptions {
  /// Whether fallback foreground presentation is enabled at all.
  final bool enabled;

  /// Default Android notification details when no builder override is provided.
  final AndroidNotificationDetails? androidDefaults;

  /// Default iOS notification details when no builder override is provided.
  final DarwinNotificationDetails? iosDefaults;

  /// Per-message Android override builder.
  final AndroidForegroundNotificationBuilder? androidBuilder;

  /// Per-message iOS override builder.
  final IOSForegroundNotificationBuilder? iosBuilder;

  /// Default sound file name for Android (without extension, placed in res/raw/)
  final String? androidSoundFileName;

  /// Default sound file name for iOS (placed in project)
  final String? iosSoundFileName;

  /// Creates a foreground presentation policy.
  const ForegroundNotificationOptions({
    this.enabled = true,
    this.androidDefaults,
    this.iosDefaults,
    this.androidBuilder,
    this.iosBuilder,
    this.androidSoundFileName,
    this.iosSoundFileName,
  });

  /// Sensible defaults for heads-up style foreground presentation.
  static const ForegroundNotificationOptions defaults =
      ForegroundNotificationOptions(
        enabled: true,
        androidDefaults: AndroidNotificationDetails(
          'default_channel',
          'Default Notifications',
          channelDescription:
              'Default notification channel for foreground messages',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          enableVibration: true,
          playSound: true,
        ),
        iosDefaults: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      );
}
