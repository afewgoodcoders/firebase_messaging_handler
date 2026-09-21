import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../interfaces/storage_service_interface.dart';
import '../../constants/export.dart';

/// Storage service implementation using SharedPreferences
class StorageService implements StorageServiceInterface {
  static StorageService? _instance;
  SharedPreferences? _prefs;
  bool _saveNotifications = true;
  int _maxStoredNotifications = 100;
  bool _debugLoggingEnabled = false;

  /// Singleton instance
  static StorageService get instance {
    _instance ??= StorageService._internal();
    return _instance!;
  }

  StorageService._internal();

  /// Applies runtime storage limits from [FCMConfiguration].
  void configure({
    required bool saveNotifications,
    required int maxStoredNotifications,
    bool enableDebugLogging = false,
  }) {
    _saveNotifications = saveNotifications;
    _maxStoredNotifications = maxStoredNotifications;
    _debugLoggingEnabled = enableDebugLogging;
  }

  /// Initializes the storage service
  Future<void> _initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<void> saveFcmToken(String token) async {
    try {
      await _initialize();
      await _prefs!.setString(
        FirebaseMessagingHandlerConstants.fcmTokenPrefKey,
        token,
      );
      _logMessage('[StorageService] FCM token saved');
    } catch (error, stack) {
      _logMessage('[StorageService] Save FCM token error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  @override
  Future<String?> getFcmToken() async {
    try {
      await _initialize();
      final String? token = _prefs!.getString(
        FirebaseMessagingHandlerConstants.fcmTokenPrefKey,
      );
      _logMessage(
        '[StorageService] FCM token retrieved: ${token != null ? 'found' : 'null'}',
      );
      return token;
    } catch (error, stack) {
      _logMessage('[StorageService] Get FCM token error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
      return null;
    }
  }

  @override
  Future<void> removeFcmToken() async {
    try {
      await _initialize();
      await _prefs!.remove(FirebaseMessagingHandlerConstants.fcmTokenPrefKey);
      _logMessage('[StorageService] FCM token removed');
    } catch (error, stack) {
      _logMessage('[StorageService] Remove FCM token error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  @override
  Future<void> saveNotification(dynamic message) async {
    try {
      if (!_saveNotifications) return;
      await _initialize();

      // Get existing notifications
      final String? storedData = _prefs!.getString(
        FirebaseMessagingHandlerConstants.sessionPrefKey,
      );
      final List<Map<String, dynamic>> currentMessages = storedData != null
          ? List<Map<String, dynamic>>.from(jsonDecode(storedData))
          : [];

      // Check if message already exists
      final int messageHash = message.messageId.hashCode;
      final bool isDuplicate = currentMessages.any((msg) {
        return msg['messageId']?.hashCode == messageHash;
      });

      if (!isDuplicate) {
        // Add new message
        currentMessages.add(message.toMap());
        if (currentMessages.length > _maxStoredNotifications) {
          currentMessages.removeRange(
            0,
            currentMessages.length - _maxStoredNotifications,
          );
        }

        // Save updated list
        await _prefs!.setString(
          FirebaseMessagingHandlerConstants.sessionPrefKey,
          jsonEncode(currentMessages),
        );

        _logMessage(
          '[StorageService] Notification saved: ${message.messageId}',
        );
      }
    } catch (error, stack) {
      _logMessage('[StorageService] Save notification error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  @override
  Future<List<dynamic>> getStoredNotifications() async {
    try {
      await _initialize();
      final String? storedData = _prefs!.getString(
        FirebaseMessagingHandlerConstants.sessionPrefKey,
      );

      if (storedData != null) {
        final List<dynamic> jsonList = jsonDecode(storedData);
        final List<RemoteMessage> restoredMessages = jsonList
            .cast<Map<String, dynamic>>()
            .map((data) => RemoteMessage.fromMap(data))
            .toList();

        _logMessage(
          '[StorageService] Retrieved ${restoredMessages.length} stored notifications',
        );
        return restoredMessages;
      }

      return [];
    } catch (error, stack) {
      _logMessage('[StorageService] Get stored notifications error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
      return [];
    }
  }

  @override
  Future<void> clearStoredNotifications() async {
    try {
      await _initialize();
      await _prefs!.remove(FirebaseMessagingHandlerConstants.sessionPrefKey);
      _logMessage('[StorageService] Stored notifications cleared');
    } catch (error, stack) {
      _logMessage('[StorageService] Clear stored notifications error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  @override
  Future<void> saveConfiguration(String key, dynamic value) async {
    try {
      await _initialize();

      if (value is String) {
        await _prefs!.setString(key, value);
      } else if (value is int) {
        await _prefs!.setInt(key, value);
      } else if (value is bool) {
        await _prefs!.setBool(key, value);
      } else if (value is double) {
        await _prefs!.setDouble(key, value);
      } else if (value is List<String>) {
        await _prefs!.setStringList(key, value);
      } else {
        // For complex objects, convert to JSON string
        await _prefs!.setString(key, jsonEncode(value));
      }

      _logMessage('[StorageService] Configuration saved: $key');
    } catch (error, stack) {
      _logMessage('[StorageService] Save configuration error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  @override
  Future<dynamic> getConfiguration(String key) async {
    try {
      await _initialize();

      // Try different types
      if (_prefs!.containsKey(key)) {
        final dynamic value = _prefs!.get(key);

        // If it's a string that might be JSON, try to decode it
        if (value is String) {
          try {
            return jsonDecode(value);
          } catch (e) {
            return value;
          }
        }

        return value;
      }

      return null;
    } catch (error, stack) {
      _logMessage('[StorageService] Get configuration error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
      return null;
    }
  }

  @override
  Future<void> removeConfiguration(String key) async {
    try {
      await _initialize();
      await _prefs!.remove(key);
      _logMessage('[StorageService] Configuration removed: $key');
    } catch (error, stack) {
      _logMessage('[StorageService] Remove configuration error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  /*
   * Why: Silent pushes that should render in-app messaging might arrive while the UI tree
   * is unavailable, so we stage them in local storage and hydrate the stream later.
   */
  @override
  Future<void> savePendingInAppMessage(
    Map<String, dynamic> message, {
    DateTime? nextEligibleAt,
  }) async {
    try {
      await _initialize();
      final String? stored = _prefs!.getString(
        FirebaseMessagingHandlerConstants.inAppMessagesPrefKey,
      );
      final List<Map<String, dynamic>> existing = stored != null
          ? List<Map<String, dynamic>>.from(jsonDecode(stored) as List)
          : <Map<String, dynamic>>[];
      if (nextEligibleAt != null) {
        message = Map<String, dynamic>.from(message)
          ..['__nextEligibleAt'] = nextEligibleAt.toIso8601String();
      }
      existing.removeWhere(
        (Map<String, dynamic> item) => item['id'] == message['id'],
      );
      existing.add(message);
      await _prefs!.setString(
        FirebaseMessagingHandlerConstants.inAppMessagesPrefKey,
        jsonEncode(existing),
      );
      _logMessage('[StorageService] Pending in-app message saved');
    } catch (error, stack) {
      _logMessage('[StorageService] Save pending in-app message error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingInAppMessages() async {
    try {
      await _initialize();
      final String? stored = _prefs!.getString(
        FirebaseMessagingHandlerConstants.inAppMessagesPrefKey,
      );
      if (stored == null) {
        return <Map<String, dynamic>>[];
      }
      final List<dynamic> decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .map<Map<String, dynamic>>(
            (dynamic item) => Map<String, dynamic>.from(item as Map),
          )
          .toList();
    } catch (error, stack) {
      _logMessage('[StorageService] Get pending in-app messages error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
      return <Map<String, dynamic>>[];
    }
  }

  @override
  Future<void> clearPendingInAppMessages({String? id}) async {
    try {
      await _initialize();
      if (id == null) {
        await _prefs!.remove(
          FirebaseMessagingHandlerConstants.inAppMessagesPrefKey,
        );
        _logMessage('[StorageService] Pending in-app messages cleared');
        return;
      }

      final List<Map<String, dynamic>> existing =
          await getPendingInAppMessages();
      final List<Map<String, dynamic>> filtered = existing
          .where((Map<String, dynamic> message) => message['id'] != id)
          .toList();
      await _prefs!.setString(
        FirebaseMessagingHandlerConstants.inAppMessagesPrefKey,
        jsonEncode(filtered),
      );
      _logMessage(
        '[StorageService] Pending in-app message cleared for id: $id',
      );
    } catch (error, stack) {
      _logMessage(
        '[StorageService] Clear pending in-app messages error: $error',
      );
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  @override
  Future<void> setPendingInAppMessages(
    List<Map<String, dynamic>> messages,
  ) async {
    try {
      await _initialize();
      await _prefs!.setString(
        FirebaseMessagingHandlerConstants.inAppMessagesPrefKey,
        jsonEncode(messages),
      );
    } catch (error, stack) {
      _logMessage('[StorageService] Set pending in-app error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  @override
  Future<void> saveInAppDeliveryHistory(Map<String, dynamic> history) async {
    try {
      await _initialize();
      await _prefs!.setString(
        FirebaseMessagingHandlerConstants.inAppDeliveryHistoryPrefKey,
        jsonEncode(history),
      );
      _logMessage('[StorageService] In-app delivery history saved');
    } catch (error, stack) {
      _logMessage('[StorageService] Save delivery history error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  @override
  Future<Map<String, dynamic>> getInAppDeliveryHistory() async {
    try {
      await _initialize();
      final String? stored = _prefs!.getString(
        FirebaseMessagingHandlerConstants.inAppDeliveryHistoryPrefKey,
      );
      if (stored == null) {
        return <String, dynamic>{};
      }
      return Map<String, dynamic>.from(jsonDecode(stored) as Map);
    } catch (error, stack) {
      _logMessage('[StorageService] Get delivery history error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
      return <String, dynamic>{};
    }
  }

  @override
  Future<void> clearInAppDeliveryHistory() async {
    try {
      await _initialize();
      await _prefs!.remove(
        FirebaseMessagingHandlerConstants.inAppDeliveryHistoryPrefKey,
      );
    } catch (error, stack) {
      _logMessage('[StorageService] Clear delivery history error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  @override
  Future<void> saveQueuedBackgroundMessage(Map<String, dynamic> message) async {
    try {
      await _initialize();
      final String? stored = _prefs!.getString(
        FirebaseMessagingHandlerConstants.backgroundMessageQueuePrefKey,
      );
      final List<Map<String, dynamic>> existing = stored != null
          ? List<Map<String, dynamic>>.from(jsonDecode(stored) as List)
          : <Map<String, dynamic>>[];
      existing.removeWhere(
        (Map<String, dynamic> item) =>
            item['messageId'] == message['messageId'],
      );
      existing.add(message);
      await _prefs!.setString(
        FirebaseMessagingHandlerConstants.backgroundMessageQueuePrefKey,
        jsonEncode(existing),
      );
      _logMessage('[StorageService] Queued background message stored');
    } catch (error, stack) {
      _logMessage('[StorageService] Save queued background error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getQueuedBackgroundMessages() async {
    try {
      await _initialize();
      final String? stored = _prefs!.getString(
        FirebaseMessagingHandlerConstants.backgroundMessageQueuePrefKey,
      );
      if (stored == null) {
        return <Map<String, dynamic>>[];
      }
      final List<dynamic> decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .map<Map<String, dynamic>>(
            (dynamic item) => Map<String, dynamic>.from(item as Map),
          )
          .toList();
    } catch (error, stack) {
      _logMessage('[StorageService] Get queued background error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
      return <Map<String, dynamic>>[];
    }
  }

  @override
  Future<void> clearQueuedBackgroundMessages({String? messageId}) async {
    try {
      await _initialize();
      if (messageId == null) {
        await _prefs!.remove(
          FirebaseMessagingHandlerConstants.backgroundMessageQueuePrefKey,
        );
        return;
      }
      final List<Map<String, dynamic>> existing =
          await getQueuedBackgroundMessages();
      existing.removeWhere(
        (Map<String, dynamic> item) => item['messageId'] == messageId,
      );
      await _prefs!.setString(
        FirebaseMessagingHandlerConstants.backgroundMessageQueuePrefKey,
        jsonEncode(existing),
      );
    } catch (error, stack) {
      _logMessage('[StorageService] Clear queued background error: $error');
      _logMessage('[StorageService] Stack trace: $stack');
    }
  }

  void _logMessage(String message) {
    if (kDebugMode && _debugLoggingEnabled) {
      print(message);
    }
  }
}
