import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

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

/// Web/WASM-safe Android foreground builder placeholder.
typedef AndroidForegroundNotificationBuilder =
    FutureOr<Object?> Function(ForegroundNotificationContext context);

/// Web/WASM-safe iOS foreground builder placeholder.
typedef IOSForegroundNotificationBuilder =
    FutureOr<Object?> Function(ForegroundNotificationContext context);

/// Controls how foreground remote messages are translated into local
/// notifications when the app is active.
class ForegroundNotificationOptions {
  /// Whether fallback foreground presentation is enabled at all.
  final bool enabled;

  /// Web/WASM-safe placeholder for native Android defaults.
  final Object? androidDefaults;

  /// Web/WASM-safe placeholder for native iOS defaults.
  final Object? iosDefaults;

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

  /// Sensible defaults for web foreground presentation.
  static const ForegroundNotificationOptions defaults =
      ForegroundNotificationOptions();
}
