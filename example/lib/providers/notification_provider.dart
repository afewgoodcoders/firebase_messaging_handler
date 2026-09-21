import 'package:flutter/foundation.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ActivityLogEntry {
  ActivityLogEntry(this.label) : timestamp = DateTime.now();

  ActivityLogEntry.fromMap(Map<String, dynamic> map)
    : label = map['label'],
      timestamp = DateTime.parse(map['timestamp']);

  final String label;
  final DateTime timestamp;

  Map<String, dynamic> toMap() {
    return {'label': label, 'timestamp': timestamp.toIso8601String()};
  }
}

class NotificationProvider extends ChangeNotifier {
  final List<NotificationData> _notifications = [];
  final List<ActivityLogEntry> _activityLog = [];
  NotificationData? _initialNotification;
  NotificationData? _activeNotification;
  String? _fcmToken;
  String? _tokenError;
  bool _isInitialized = false;
  int _iosBadgeCount = 0;
  int _androidBadgeCount = 0;

  static const String _notificationsKey = 'cached_notifications';
  static const String _activityLogKey = 'cached_activity_log';
  static const String _initialNotificationKey = 'cached_initial_notification';

  List<NotificationData> get notifications => _notifications;
  List<ActivityLogEntry> get activityLog => List.unmodifiable(_activityLog);
  NotificationData? get initialNotification => _initialNotification;
  NotificationData? get activeNotification => _activeNotification;
  String? get fcmToken => _fcmToken;

  /// Human-readable reason the FCM token could not be retrieved, or null if it succeeded.
  String? get tokenError => _tokenError;
  bool get isInitialized => _isInitialized;
  int get iosBadgeCount => _iosBadgeCount;
  int get androidBadgeCount => _androidBadgeCount;

  void addNotification(NotificationData notification) {
    _notifications.insert(0, notification); // Latest first
    _saveToCache();
    notifyListeners();
  }

  void setInitialNotification(NotificationData? notification) {
    _initialNotification = notification;
    _saveToCache();
    notifyListeners();
  }

  void setActiveNotification(NotificationData? notification) {
    _activeNotification = notification;
    if (notification != null) {
      addActivity('Opened ${notification.title ?? 'notification'}');
    }
    notifyListeners();
  }

  void setFcmToken(String? token, {String? error}) {
    _fcmToken = token;
    _tokenError = error;
    notifyListeners();
  }

  void setInitialized(bool initialized) {
    _isInitialized = initialized;
    notifyListeners();
  }

  void setIOSBadgeCount(int count) {
    _iosBadgeCount = count;
    notifyListeners();
  }

  void setAndroidBadgeCount(int count) {
    _androidBadgeCount = count;
    notifyListeners();
  }

  void clearNotifications() {
    _notifications.clear();
    _saveToCache();
    notifyListeners();
  }

  void addActivity(String message) {
    _activityLog.insert(0, ActivityLogEntry(message));
    _saveToCache();
    notifyListeners();
  }

  void clearActivity() {
    _activityLog.clear();
    _saveToCache();
    notifyListeners();
  }

  void clearAll() {
    _notifications.clear();
    _activityLog.clear();
    _initialNotification = null;
    _activeNotification = null;
    _iosBadgeCount = 0;
    _androidBadgeCount = 0;
    notifyListeners();
  }

  void incrementIOSBadge() {
    _iosBadgeCount++;
    notifyListeners();
  }

  void incrementAndroidBadge() {
    _androidBadgeCount++;
    notifyListeners();
  }

  void clearBadges() {
    _iosBadgeCount = 0;
    _androidBadgeCount = 0;
    notifyListeners();
  }

  /// Load cached data from SharedPreferences
  Future<void> loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load notifications
      final notificationsJson = prefs.getString(_notificationsKey);
      if (notificationsJson != null) {
        final List<dynamic> notificationsList = json.decode(notificationsJson);
        _notifications.clear();
        _notifications.addAll(
          notificationsList.map((json) => NotificationData.fromMap(json)),
        );
      }

      // Load activity log
      final activityLogJson = prefs.getString(_activityLogKey);
      if (activityLogJson != null) {
        final List<dynamic> activityLogList = json.decode(activityLogJson);
        _activityLog.clear();
        _activityLog.addAll(
          activityLogList.map((json) => ActivityLogEntry.fromMap(json)),
        );
      }

      // Load initial notification
      final initialNotificationJson = prefs.getString(_initialNotificationKey);
      if (initialNotificationJson != null) {
        _initialNotification = NotificationData.fromMap(
          json.decode(initialNotificationJson),
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[NotificationProvider] Error loading cached data: $e');
    }
  }

  /// Save data to SharedPreferences
  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save notifications
      final notificationsJson = json.encode(
        _notifications.map((notification) => notification.toMap()).toList(),
      );
      await prefs.setString(_notificationsKey, notificationsJson);

      // Save activity log
      final activityLogJson = json.encode(
        _activityLog.map((entry) => entry.toMap()).toList(),
      );
      await prefs.setString(_activityLogKey, activityLogJson);

      // Save initial notification
      if (_initialNotification != null) {
        final initialNotificationJson = json.encode(
          _initialNotification!.toMap(),
        );
        await prefs.setString(_initialNotificationKey, initialNotificationJson);
      } else {
        await prefs.remove(_initialNotificationKey);
      }
    } catch (e) {
      debugPrint('[NotificationProvider] Error saving to cache: $e');
    }
  }

  /// Clear all cached timeline data
  Future<void> clearTimelineCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_notificationsKey);
      await prefs.remove(_activityLogKey);
      await prefs.remove(_initialNotificationKey);

      _notifications.clear();
      _activityLog.clear();
      _initialNotification = null;
      _activeNotification = null;

      notifyListeners();
    } catch (e) {
      debugPrint('[NotificationProvider] Error clearing timeline cache: $e');
    }
  }
}
