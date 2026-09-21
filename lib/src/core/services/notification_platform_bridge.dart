import 'package:flutter/services.dart';

import '../utils/platform_utils.dart';

/// Native operations that cannot be expressed by `flutter_local_notifications`.
class NotificationPlatformBridge {
  NotificationPlatformBridge._();

  /// Shared bridge instance.
  static final NotificationPlatformBridge instance =
      NotificationPlatformBridge._();

  static const MethodChannel _channel = MethodChannel(
    'firebase_messaging_handler',
  );

  /// Whether this package provides a native app-icon badge implementation.
  Future<bool> isBadgeSupported() async {
    if (!isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isBadgeSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Applies an app-icon badge count through the native platform API.
  Future<bool> setBadgeCount(int count) async {
    if (!isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('setBadgeCount', <String, int>{
            'count': count,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Reads the app-icon badge count from the native platform API.
  Future<int?> getBadgeCount() async {
    if (!isIOS) return null;
    try {
      return await _channel.invokeMethod<int>('getBadgeCount');
    } on MissingPluginException {
      return null;
    }
  }
}
