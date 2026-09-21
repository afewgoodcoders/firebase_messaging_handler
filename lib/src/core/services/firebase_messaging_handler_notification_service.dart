import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../utils/web_interop.dart' as web_interop;
import '../interfaces/notification_service_interface.dart';
import '../managers/notification_manager.dart';
import '../../enums/export.dart';
import '../../extensions/android_notification_channel_extensions.dart';
import '../../constants/firebase_messaging_handler_constants.dart';
import '../../models/export.dart';
import '../utils/platform_utils.dart';
import 'storage_service.dart';
import 'notification_platform_bridge.dart';
import '../interfaces/notification_state_store.dart';

/// Background action entry point used by `flutter_local_notifications`.
@pragma('vm:entry-point')
void firebaseMessagingHandlerNotificationTapBackground(
  NotificationResponse response,
) {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(
    FirebaseMessagingHandlerNotificationService.instance
        .handleNotificationResponse(
          response,
          lifecycle: NotificationLifecycle.background,
        ),
  );
}

/// Local notification service implementation for Firebase Messaging Handler
class FirebaseMessagingHandlerNotificationService
    implements NotificationServiceInterface {
  static FirebaseMessagingHandlerNotificationService? _instance;
  FlutterLocalNotificationsPlugin? _localNotifications;
  bool _isInitialized = false;
  final StorageService _storageService = StorageService.instance;
  final NotificationPlatformBridge _platformBridge =
      NotificationPlatformBridge.instance;
  final NotificationStateStore _backgroundStateStore =
      SharedPreferencesNotificationStateStore();
  int? _cachedBadgeCount;
  String? _configuredTimezoneIdentifier;
  bool _debugLoggingEnabled = false;

  /// Singleton instance
  static FirebaseMessagingHandlerNotificationService get instance {
    _instance ??= FirebaseMessagingHandlerNotificationService._internal();
    return _instance!;
  }

  FirebaseMessagingHandlerNotificationService._internal();

  /// Ensure the service is initialized before use
  void _ensureInitialized() {
    if (isWeb) {
      return;
    }
    if (!_isInitialized || _localNotifications == null) {
      throw Exception(
        'NotificationService not initialized. Call initialize() first.',
      );
    }
  }

  @override
  Future<bool> initialize({
    required List<NotificationChannelData> androidChannels,
    required String androidIconPath,
    List<NotificationActionCategory> actionCategories =
        const <NotificationActionCategory>[],
    WindowsNotificationOptions? windows,
    bool enableDebugLogging = false,
  }) async {
    _debugLoggingEnabled = enableDebugLogging;
    try {
      if (isWeb) {
        _isInitialized = true;
        _logMessage(
          '[NotificationService] Web environment detected - skipping local notifications init',
        );
        return true;
      }

      _localNotifications = FlutterLocalNotificationsPlugin();

      await refreshLocalTimezone();

      final List<DarwinNotificationCategory> darwinCategories = actionCategories
          .map(_toDarwinCategory)
          .toList();
      final DarwinInitializationSettings darwinSettings =
          DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
            requestProvisionalPermission: false,
            requestCriticalPermission: false,
            notificationCategories: darwinCategories,
          );
      final InitializationSettings initializationSettings =
          InitializationSettings(
            android: AndroidInitializationSettings(androidIconPath),
            iOS: darwinSettings,
            macOS: darwinSettings,
            linux: const LinuxInitializationSettings(
              defaultActionName: 'Open notification',
            ),
            windows: windows == null
                ? null
                : WindowsInitializationSettings(
                    appName: windows.appName,
                    appUserModelId: windows.appUserModelId,
                    guid: windows.guid,
                    iconPath: windows.iconPath,
                  ),
          );

      final bool? isInitialized = await _localNotifications!.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            firebaseMessagingHandlerNotificationTapBackground,
      );

      if (isInitialized == true) {
        // Create Android notification channels
        for (final NotificationChannelData channel in androidChannels) {
          await _createAndroidChannel(channel);
        }

        // Configure iOS notification categories
        _isInitialized = true;
        _logMessage('[NotificationService] Initialized successfully');
        return true;
      }

      _logMessage('[NotificationService] Initialization failed');
      return false;
    } catch (error, stack) {
      _logMessage('[NotificationService] Initialization error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  @override
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
  }) async {
    try {
      if (isWeb) {
        return await showWebNotification(
          title: title,
          body: body,
          icon: '/icons/Icon-192.png',
          data: payload ?? <String, dynamic>{},
        );
      }

      _ensureInitialized();
      final NotificationDetails notificationDetails = NotificationDetails(
        android:
            androidDetailsOverride ??
            AndroidNotificationDetails(
              channelId ?? 'default_channel',
              'Default Notifications',
              importance: Importance.max,
              priority: Priority.high,
              groupKey: groupKey,
              setAsGroupSummary: isGroupSummary,
              groupAlertBehavior: isGroupSummary
                  ? GroupAlertBehavior.summary
                  : GroupAlertBehavior.all,
            ),
        iOS:
            iosDetailsOverride ??
            DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
              presentBadge: true,
              categoryIdentifier: category,
              threadIdentifier: threadIdentifier,
              subtitle: groupAlertSummary,
            ),
        linux: linuxDetailsOverride,
        windows: windowsDetailsOverride,
      );

      await _localNotifications!.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: jsonEncode(payload ?? {}),
      );

      _logMessage('[NotificationService] Notification shown: $title');
      return true;
    } catch (error, stack) {
      _logMessage('[NotificationService] Show notification error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  @override
  Future<bool> showNotificationWithActions({
    required int id,
    required String title,
    required String body,
    required List<NotificationAction> actions,
    Map<String, dynamic>? payload,
    String? channelId,
    String? actionCategoryId,
  }) async {
    try {
      if (isWeb) {
        _logMessage(
          '[NotificationService] Notification actions are not supported on web',
        );
        return await showWebNotification(
          title: title,
          body: body,
          icon: '/icons/Icon-192.png',
          data: payload ?? <String, dynamic>{},
        );
      }

      _ensureInitialized();
      await _localNotifications!.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId ?? 'action_channel',
            'Action Notifications',
            importance: Importance.max,
            priority: Priority.high,
            actions: actions.map(_toAndroidAction).toList(),
          ),
          iOS: DarwinNotificationDetails(
            categoryIdentifier: actionCategoryId,
            presentAlert: true,
            presentSound: true,
            presentBadge: false,
          ),
        ),
        payload: jsonEncode({
          'title': title,
          'body': body,
          'actions': actions
              .map((NotificationAction action) => action.toMap())
              .toList(),
          ...payload ?? {},
        }),
      );

      _logMessage(
        '[NotificationService] Notification with actions shown: $title',
      );
      return true;
    } catch (error, stack) {
      _logMessage(
        '[NotificationService] Show notification with actions error: $error',
      );
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  @override
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
  }) async {
    try {
      if (isWeb) {
        _logMessage(
          '[NotificationService] Scheduling is not supported on web - ignoring request',
        );
        return false;
      }

      if (scheduledDate.isBefore(DateTime.now())) {
        _logMessage(
          '[NotificationService] Cannot schedule notification in the past',
        );
        return false;
      }

      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId ?? 'scheduled_notifications',
          'Scheduled Notifications',
          importance: Importance.max,
          priority: Priority.high,
          actions: actions?.map(_toAndroidAction).toList(),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: false,
          categoryIdentifier: actionCategoryId,
        ),
      );

      _ensureInitialized();
      await _localNotifications!.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
        notificationDetails: notificationDetails,
        androidScheduleMode: _toAndroidScheduleMode(scheduleMode),
        payload: jsonEncode(payload ?? {}),
      );

      _logMessage(
        '[NotificationService] Notification scheduled for: ${scheduledDate.toString()}',
      );
      return true;
    } catch (error, stack) {
      _logMessage('[NotificationService] Schedule notification error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  @override
  Future<bool> scheduleRecurringNotification({
    required int id,
    required String title,
    required String body,
    required RepeatIntervalEnum repeatInterval,
    required DateTime initialScheduleDate,
    Map<String, dynamic>? payload,
    String? channelId,
    List<NotificationAction>? actions,
  }) async {
    try {
      if (isWeb) {
        _logMessage(
          '[NotificationService] Recurring scheduling is not supported on web',
        );
        return false;
      }

      _ensureInitialized();

      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId ?? 'recurring_notifications',
          'Recurring Notifications',
          importance: Importance.max,
          priority: Priority.high,
          actions: actions?.map(_toAndroidAction).toList(),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: false,
        ),
      );

      final Map<String, dynamic> encodedPayload =
          payload ?? <String, dynamic>{};

      if (repeatInterval == RepeatIntervalEnum.hourly ||
          repeatInterval == RepeatIntervalEnum.minutely) {
        if (actions != null && actions.isNotEmpty) {
          _logMessage(
            '[NotificationService] Actions are not supported for periodic notifications; ignoring provided actions',
          );
        }
        final RepeatInterval periodicInterval =
            repeatInterval == RepeatIntervalEnum.hourly
            ? RepeatInterval.hourly
            : RepeatInterval.everyMinute;

        await _localNotifications!.periodicallyShow(
          id: id,
          title: title,
          body: body,
          repeatInterval: periodicInterval,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: jsonEncode(encodedPayload),
        );

        _logMessage(
          '[NotificationService] Periodic notification scheduled (interval: ${repeatInterval.name}) for id: $id',
        );
        return true;
      }

      final tz.TZDateTime normalizedDate = _normalizeScheduledDate(
        initialScheduleDate,
        repeatInterval,
      );
      final DateTimeComponents? matchComponents =
          _mapRepeatIntervalToDateTimeComponents(repeatInterval);

      if (matchComponents == null) {
        _logMessage(
          '[NotificationService] Unsupported repeat interval: ${repeatInterval.name}',
        );
        return false;
      }

      await _localNotifications!.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: normalizedDate,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode(encodedPayload),
        matchDateTimeComponents: matchComponents,
      );

      _logMessage(
        '[NotificationService] Recurring notification scheduled (interval: ${repeatInterval.name}) starting ${normalizedDate.toString()}',
      );
      return true;
    } catch (error, stack) {
      _logMessage(
        '[NotificationService] Schedule recurring notification error: $error',
      );
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  @override
  Future<bool> cancelNotification(int id) async {
    try {
      if (isWeb) {
        _logMessage(
          '[NotificationService] Cancel notification ignored on web (no local schedule)',
        );
        return false;
      }

      _ensureInitialized();
      await _localNotifications!.cancel(id: id);
      _logMessage('[NotificationService] Notification cancelled: $id');
      return true;
    } catch (error, stack) {
      _logMessage('[NotificationService] Cancel notification error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  @override
  Future<bool> cancelAllNotifications() async {
    try {
      if (isWeb) {
        _logMessage(
          '[NotificationService] Cancel all notifications ignored on web',
        );
        return false;
      }

      _ensureInitialized();
      await _localNotifications!.cancelAll();
      _logMessage('[NotificationService] All notifications cancelled');
      return true;
    } catch (error, stack) {
      _logMessage(
        '[NotificationService] Cancel all notifications error: $error',
      );
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  @override
  Future<List<PendingNotificationSnapshot>> getPendingNotifications() async {
    try {
      if (isAndroid) {
        _ensureInitialized();
        final List<PendingNotificationRequest> pending =
            await _localNotifications!.pendingNotificationRequests();
        return pending
            .map(
              (PendingNotificationRequest item) => PendingNotificationSnapshot(
                id: item.id,
                title: item.title,
                body: item.body,
                payload: item.payload,
              ),
            )
            .toList(growable: false);
      }
      return <PendingNotificationSnapshot>[];
    } catch (error, stack) {
      _logMessage(
        '[NotificationService] Get pending notifications error: $error',
      );
      _logMessage('[NotificationService] Stack trace: $stack');
      return <PendingNotificationSnapshot>[];
    }
  }

  @override
  Future<List<ActiveNotificationSnapshot>> getActiveNotifications() async {
    if (isWeb) return <ActiveNotificationSnapshot>[];
    try {
      _ensureInitialized();
      final List<ActiveNotification> active = await _localNotifications!
          .getActiveNotifications();
      return active
          .map(
            (ActiveNotification item) => ActiveNotificationSnapshot(
              id: item.id,
              channelId: item.channelId,
              groupKey: item.groupKey,
              title: item.title,
              body: item.body,
              payload: item.payload,
              tag: item.tag,
              bigText: item.bigText,
            ),
          )
          .toList(growable: false);
    } catch (error, stack) {
      _logMessage(
        '[NotificationService] Get active notifications error: $error',
      );
      _logMessage('[NotificationService] Stack trace: $stack');
      return <ActiveNotificationSnapshot>[];
    }
  }

  @override
  Future<bool?> areNotificationsEnabled() async {
    if (!isAndroid) return null;
    try {
      final FlutterLocalNotificationsPlugin plugin =
          _localNotifications ?? FlutterLocalNotificationsPlugin();
      return await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
    } catch (error, stack) {
      _logMessage('[NotificationService] Notification status error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return null;
    }
  }

  @override
  Future<bool> deleteNotificationChannel(String channelId) async {
    if (!isAndroid || channelId.trim().isEmpty) return false;
    try {
      final FlutterLocalNotificationsPlugin plugin =
          _localNotifications ?? FlutterLocalNotificationsPlugin();
      final AndroidFlutterLocalNotificationsPlugin? android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return false;
      await android.deleteNotificationChannel(channelId: channelId);
      return true;
    } catch (error, stack) {
      _logMessage('[NotificationService] Delete channel error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  @override
  Future<String?> refreshLocalTimezone() async {
    return await _configureLocalTimeZone();
  }

  @override
  Future<String?> getConfiguredLocalTimezone() async {
    return _configuredTimezoneIdentifier;
  }

  @override
  Future<void> createNotificationChannel(
    NotificationChannelData channel,
  ) async {
    try {
      if (isAndroid) {
        await _localNotifications!
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(channel.toAndroidNotificationChannel());
        _logMessage('[NotificationService] Channel created: ${channel.id}');
      }
    } catch (error, stack) {
      _logMessage('[NotificationService] Create channel error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
    }
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async {
    try {
      if (isWeb) {
        _logMessage(
          '[NotificationService] Launch details unavailable on web platform',
        );
        return null;
      }

      // Do not hard require initialize() here so apps can call checkInitial()
      // early during startup. On Android, the plugin must be initialized once
      // to capture the launch intent; do a minimal, safe initialization.
      if (_localNotifications == null) {
        final FlutterLocalNotificationsPlugin temp =
            FlutterLocalNotificationsPlugin();
        try {
          final InitializationSettings init = InitializationSettings(
            android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: const DarwinInitializationSettings(),
          );
          await temp.initialize(settings: init);
        } catch (_) {
          // Best-effort; still attempt to read launch details
        }
        return await temp.getNotificationAppLaunchDetails();
      }

      return await _localNotifications!.getNotificationAppLaunchDetails();
    } catch (error, stack) {
      _logMessage('[NotificationService] Get launch details error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return null;
    }
  }

  @override
  Future<bool> isBadgeSupported() async {
    try {
      return await _platformBridge.isBadgeSupported();
    } catch (error, stack) {
      _logMessage('[NotificationService] Badge support check error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  @override
  Future<String> getWebNotificationPermissionStatus() async {
    if (!isWeb) {
      return 'unavailable';
    }

    try {
      return web_interop.getWebNotificationPermission();
    } catch (error, stack) {
      _logMessage('[NotificationService] Web permission status error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return 'error';
    }
  }

  @override
  Future<Map<String, dynamic>> getWebRuntimeDiagnostics() async {
    if (!isWeb) {
      return <String, dynamic>{'supported': false, 'reason': 'unavailable'};
    }

    try {
      return web_interop.getWebRuntimeDiagnostics();
    } catch (error, stack) {
      _logMessage(
        '[NotificationService] Web runtime diagnostics error: $error',
      );
      _logMessage('[NotificationService] Stack trace: $stack');
      return <String, dynamic>{'supported': false, 'error': error.toString()};
    }
  }

  @override
  Future<bool> openAppNotificationSettings() async {
    if (isWeb) return false;
    try {
      final FlutterLocalNotificationsPlugin plugin =
          _localNotifications ?? FlutterLocalNotificationsPlugin();
      return await plugin.openAppNotificationSettings() ?? false;
    } on UnimplementedError {
      return false;
    } catch (error, stack) {
      _logMessage(
        '[NotificationService] Open notification settings error: $error',
      );
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  @override
  Future<bool?> canScheduleExactNotifications() async {
    if (!isAndroid) return null;
    try {
      final FlutterLocalNotificationsPlugin plugin =
          _localNotifications ?? FlutterLocalNotificationsPlugin();
      return await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.canScheduleExactNotifications();
    } catch (error, stack) {
      _logMessage('[NotificationService] Exact alarm check error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  @override
  Future<bool> requestExactAlarmPermission() async {
    if (!isAndroid) return false;
    try {
      final FlutterLocalNotificationsPlugin plugin =
          _localNotifications ?? FlutterLocalNotificationsPlugin();
      return await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestExactAlarmsPermission() ??
          false;
    } catch (error, stack) {
      _logMessage('[NotificationService] Exact alarm request error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  /// Shows web notification
  Future<bool> showWebNotification({
    required String title,
    required String body,
    required String icon,
    required Map<String, dynamic> data,
  }) async {
    try {
      if (!isWeb) return false;

      final bool shown = await web_interop.showWebNotification(
        title: title,
        body: body,
        icon: icon,
        data: data,
      );

      _logMessage(
        shown
            ? '[NotificationService] Web notification displayed: $title'
            : '[NotificationService] Web notification not displayed; permission must be granted from a user gesture.',
      );
      return shown;
    } catch (error, stack) {
      _logMessage('[NotificationService] Show web notification error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  /// Sets iOS badge count
  Future<void> setIOSBadgeCount(int count) async {
    try {
      if (isIOS) {
        await _updateBadgeCount(count);
      }
    } catch (error, stack) {
      _logMessage('[NotificationService] Set iOS badge count error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
    }
  }

  /// Gets iOS badge count
  Future<int?> getIOSBadgeCount() async {
    try {
      if (isIOS) {
        return await _getStoredBadgeCount();
      }
    } catch (error, stack) {
      _logMessage('[NotificationService] Get iOS badge count error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
    }
    return null;
  }

  /// Sets Android badge count
  Future<void> setAndroidBadgeCount(int count) async {
    try {
      if (isAndroid) {
        await _updateBadgeCount(count);
      }
    } catch (error, stack) {
      _logMessage(
        '[NotificationService] Set Android badge count error: $error',
      );
      _logMessage('[NotificationService] Stack trace: $stack');
    }
  }

  /// Gets Android badge count
  Future<int?> getAndroidBadgeCount() async {
    try {
      if (isAndroid) {
        return await _getStoredBadgeCount();
      }
    } catch (error, stack) {
      _logMessage(
        '[NotificationService] Get Android badge count error: $error',
      );
      _logMessage('[NotificationService] Stack trace: $stack');
    }
    return null;
  }

  /// Clears badge count for both platforms
  Future<void> clearBadgeCount() async {
    try {
      if (isWeb) {
        _logMessage(
          '[NotificationService] Badge count clearing not supported on web',
        );
        return;
      }

      final bool supported = await isBadgeSupported();
      if (!supported) {
        _logMessage(
          '[NotificationService] Badge count clearing not supported on this platform',
        );
        return;
      }

      final bool updated = await _platformBridge.setBadgeCount(0);
      if (updated) {
        await _clearStoredBadgeCount();
        _logMessage('[NotificationService] Badge count cleared');
      }
    } catch (error, stack) {
      _logMessage('[NotificationService] Clear badge count error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
    }
  }

  Future<bool> _updateBadgeCount(int count) async {
    if (isWeb) {
      _logMessage(
        '[NotificationService] Badge updates are not available on web',
      );
      return false;
    }

    try {
      final bool supported = await isBadgeSupported();
      if (!supported) {
        _logMessage(
          '[NotificationService] App badges not supported on current platform',
        );
        return false;
      }

      final bool updated = await _platformBridge.setBadgeCount(count);
      if (!updated) return false;
      await _persistBadgeCount(count);
      _logMessage('[NotificationService] Badge count set to: $count');
      return true;
    } catch (error, stack) {
      _logMessage('[NotificationService] Update badge error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
      return false;
    }
  }

  Future<void> _persistBadgeCount(int count) async {
    _cachedBadgeCount = count;
    try {
      await _storageService.saveConfiguration(
        FirebaseMessagingHandlerConstants.badgeCountPrefKey,
        count,
      );
    } catch (error, stack) {
      _logMessage('[NotificationService] Persist badge error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
    }
  }

  Future<int> _getStoredBadgeCount() async {
    final int? nativeCount = await _platformBridge.getBadgeCount();
    if (nativeCount != null) {
      _cachedBadgeCount = nativeCount;
      return nativeCount;
    }
    if (_cachedBadgeCount != null) {
      return _cachedBadgeCount!;
    }

    try {
      final dynamic stored = await _storageService.getConfiguration(
        FirebaseMessagingHandlerConstants.badgeCountPrefKey,
      );

      if (stored is int) {
        _cachedBadgeCount = stored;
        return stored;
      }
      if (stored is double) {
        final int converted = stored.toInt();
        _cachedBadgeCount = converted;
        return converted;
      }
    } catch (error, stack) {
      _logMessage('[NotificationService] Read badge error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
    }

    return 0;
  }

  Future<void> _clearStoredBadgeCount() async {
    _cachedBadgeCount = 0;
    try {
      await _storageService.removeConfiguration(
        FirebaseMessagingHandlerConstants.badgeCountPrefKey,
      );
    } catch (error, stack) {
      _logMessage('[NotificationService] Clear badge storage error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
    }
  }

  tz.TZDateTime _normalizeScheduledDate(
    DateTime initial,
    RepeatIntervalEnum repeatInterval,
  ) {
    tz.TZDateTime scheduled = tz.TZDateTime.from(initial, tz.local);
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    while (scheduled.isBefore(now)) {
      scheduled = _incrementScheduledDate(scheduled, repeatInterval);
      if (scheduled.isAtSameMomentAs(now)) {
        break;
      }
    }
    return scheduled;
  }

  tz.TZDateTime _incrementScheduledDate(
    tz.TZDateTime date,
    RepeatIntervalEnum repeatInterval,
  ) {
    switch (repeatInterval) {
      case RepeatIntervalEnum.daily:
        return date.add(const Duration(days: 1));
      case RepeatIntervalEnum.weekly:
        return date.add(const Duration(days: 7));
      case RepeatIntervalEnum.monthly:
        return tz.TZDateTime(
          date.location,
          date.year,
          date.month + 1,
          date.day,
          date.hour,
          date.minute,
          date.second,
        );
      case RepeatIntervalEnum.yearly:
        return tz.TZDateTime(
          date.location,
          date.year + 1,
          date.month,
          date.day,
          date.hour,
          date.minute,
          date.second,
        );
      case RepeatIntervalEnum.hourly:
        return date.add(const Duration(hours: 1));
      case RepeatIntervalEnum.minutely:
        return date.add(const Duration(minutes: 1));
    }
  }

  DateTimeComponents? _mapRepeatIntervalToDateTimeComponents(
    RepeatIntervalEnum repeatInterval,
  ) {
    switch (repeatInterval) {
      case RepeatIntervalEnum.daily:
        return DateTimeComponents.time;
      case RepeatIntervalEnum.weekly:
        return DateTimeComponents.dayOfWeekAndTime;
      case RepeatIntervalEnum.monthly:
        return DateTimeComponents.dayOfMonthAndTime;
      case RepeatIntervalEnum.yearly:
        return DateTimeComponents.dateAndTime;
      default:
        return null;
    }
  }

  Future<void> _createAndroidChannel(NotificationChannelData channel) async {
    try {
      await _localNotifications!
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel.toAndroidNotificationChannel());
    } catch (error, stack) {
      _logMessage('[NotificationService] Create Android channel error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
    }
  }

  AndroidNotificationAction _toAndroidAction(NotificationAction action) {
    return AndroidNotificationAction(
      action.id,
      action.title,
      showsUserInterface: action.foreground,
      cancelNotification: action.cancelNotification,
      allowGeneratedReplies: action.textInput,
      inputs: action.textInput
          ? <AndroidNotificationActionInput>[
              AndroidNotificationActionInput(
                label: action.inputLabel,
                choices: action.inputChoices,
                allowFreeFormInput: action.allowFreeFormInput,
              ),
            ]
          : const <AndroidNotificationActionInput>[],
    );
  }

  AndroidScheduleMode _toAndroidScheduleMode(NotificationScheduleMode mode) {
    switch (mode) {
      case NotificationScheduleMode.inexact:
        return AndroidScheduleMode.inexact;
      case NotificationScheduleMode.inexactAllowWhileIdle:
        return AndroidScheduleMode.inexactAllowWhileIdle;
      case NotificationScheduleMode.exact:
        return AndroidScheduleMode.exact;
      case NotificationScheduleMode.exactAllowWhileIdle:
        return AndroidScheduleMode.exactAllowWhileIdle;
    }
  }

  DarwinNotificationCategory _toDarwinCategory(
    NotificationActionCategory category,
  ) {
    return DarwinNotificationCategory(
      category.id,
      actions: category.actions.map((NotificationAction action) {
        final Set<DarwinNotificationActionOption> options =
            <DarwinNotificationActionOption>{
              if (action.destructive)
                DarwinNotificationActionOption.destructive,
              if (action.foreground) DarwinNotificationActionOption.foreground,
              if (action.requiresAuthentication)
                DarwinNotificationActionOption.authenticationRequired,
            };
        if (action.textInput) {
          return DarwinNotificationAction.text(
            action.id,
            action.title,
            buttonTitle: action.inputButtonTitle ?? action.title,
            placeholder: action.inputLabel,
            options: options,
          );
        }
        return DarwinNotificationAction.plain(
          action.id,
          action.title,
          options: options,
        );
      }).toList(),
    );
  }

  Future<String?> _configureLocalTimeZone() async {
    if (isWeb) {
      _configuredTimezoneIdentifier = null;
      return null;
    }

    tz.initializeTimeZones();

    if (isLinux || isWindows) {
      _configuredTimezoneIdentifier = null;
      return null;
    }

    try {
      final TimezoneInfo timeZoneInfo =
          await FlutterTimezone.getLocalTimezone();
      final String identifier = timeZoneInfo.identifier.trim();
      if (identifier.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(identifier));
        _configuredTimezoneIdentifier = identifier;
        return identifier;
      }
    } catch (error, stack) {
      _logMessage('[NotificationService] Configure timezone error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
    }

    _configuredTimezoneIdentifier = null;
    return null;
  }

  Future<void> _onNotificationResponse(NotificationResponse response) async {
    await handleNotificationResponse(response);
  }

  /// Processes foreground and background local-notification interactions.
  Future<void> handleNotificationResponse(
    NotificationResponse response, {
    NotificationLifecycle lifecycle = NotificationLifecycle.resume,
  }) async {
    try {
      final bool selectedNotification =
          response.notificationResponseType ==
          NotificationResponseType.selectedNotification;
      final bool selectedAction =
          response.notificationResponseType ==
          NotificationResponseType.selectedNotificationAction;
      final bool dismissed =
          response.notificationResponseType ==
          NotificationResponseType.notificationDismissed;
      if (dismissed) {
        if (lifecycle == NotificationLifecycle.background) {
          await _storePendingInteraction(<String, dynamic>{
            'type': NotificationDeliveryEventType.dismissed.name,
            'messageId': response.id?.toString() ?? 'local_notification',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });
          return;
        }
        NotificationManager.instance.emitDeliveryEvent(
          NotificationDeliveryEvent(
            type: NotificationDeliveryEventType.dismissed,
            surface: NotificationDeliverySurface.local,
            messageId: response.id?.toString() ?? 'local_notification',
            timestamp: DateTime.now(),
            lifecycle: lifecycle,
          ),
        );
        return;
      }
      if (selectedNotification || selectedAction) {
        _logMessage(
          '[NotificationService] Notification response received: ${response.id}',
        );

        // Forward to click stream so foreground taps are published consistently
        final String? rawPayload = response.payload;
        Map<String, dynamic> payload = <String, dynamic>{};
        if (rawPayload != null && rawPayload.isNotEmpty) {
          try {
            final dynamic decoded = jsonDecode(rawPayload);
            if (decoded is Map<String, dynamic>) {
              payload = decoded;
            }
          } catch (_) {
            // Ignore malformed payloads; keep empty map
          }
        }
        if (selectedAction) {
          payload = <String, dynamic>{
            ...payload,
            'actionId': response.actionId,
            'actionInput': response.input,
          };
        }

        if (lifecycle == NotificationLifecycle.background) {
          await _storePendingInteraction(<String, dynamic>{
            'type': selectedAction
                ? NotificationDeliveryEventType.actionSelected.name
                : NotificationDeliveryEventType.opened.name,
            'messageId':
                payload['messageId']?.toString() ??
                response.id?.toString() ??
                'local_notification',
            'actionId': response.actionId,
            'actionInput': response.input,
            'payload': payload,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });
          return;
        }

        NotificationManager.instance.emitDeliveryEvent(
          NotificationDeliveryEvent(
            type: selectedAction
                ? NotificationDeliveryEventType.actionSelected
                : NotificationDeliveryEventType.opened,
            surface: NotificationDeliverySurface.local,
            messageId:
                payload['messageId']?.toString() ??
                response.id?.toString() ??
                'local_notification',
            timestamp: DateTime.now(),
            lifecycle: lifecycle,
            categoryId: payload['category']?.toString(),
            actionId: selectedAction ? response.actionId : null,
            actionInput: selectedAction ? response.input : null,
            data: payload,
          ),
        );

        NotificationManager.instance.emitTestClick(
          NotificationData(
            payload: payload,
            // Foreground tap on a local notification we presented
            type: NotificationTypeEnum.foreground,
            isFromTerminated: false,
          ),
        );
      }
    } catch (error, stack) {
      _logMessage('[NotificationService] Notification response error: $error');
      _logMessage('[NotificationService] Stack trace: $stack');
    }
  }

  Future<void> _storePendingInteraction(
    Map<String, dynamic> interaction,
  ) async {
    const String key = 'fmh_v2_pending_interactions';
    final Object? raw = await _backgroundStateStore.read(key);
    final List<dynamic> pending = raw is List
        ? List<dynamic>.from(raw)
        : <dynamic>[];
    pending.add(interaction);
    if (pending.length > 100) {
      pending.removeRange(0, pending.length - 100);
    }
    await _backgroundStateStore.write(key, pending);
  }

  void _logMessage(String message) {
    if (kDebugMode && _debugLoggingEnabled) {
      print(message);
    }
  }
}
