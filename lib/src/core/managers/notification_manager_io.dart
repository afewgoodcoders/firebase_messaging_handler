import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/export.dart';
import 'in_app_message_manager.dart';
import '../../models/export.dart';
import '../../enums/export.dart';
import '../../extensions/android_notification_channel_extensions.dart';
import '../utils/platform_utils.dart';
import 'badge_manager.dart';
import '../utils/bridging_payload_validator.dart';
import '../interfaces/notification_inbox_storage_interface.dart';
import '../interfaces/notification_state_store.dart';
import '../configuration/fcm_configuration.dart';

typedef BackgroundMessageCallback =
    Future<bool> Function(RemoteMessage message);
typedef DataOnlyMessageBridge = Future<void> Function(RemoteMessage message);
typedef UnifiedMessageHandler =
    Future<bool> Function(
      NormalizedMessage message,
      NotificationLifecycle lifecycle,
    );

/// Manager class for handling notification lifecycle and operations
class NotificationManager {
  static NotificationManager? _instance;

  /// Singleton instance
  static NotificationManager get instance {
    _instance ??= NotificationManager._internal();
    return _instance!;
  }

  NotificationManager._internal();

  // Services
  final FCMService _fcmService = FCMService.instance;
  final FirebaseMessagingHandlerNotificationService _notificationService =
      FirebaseMessagingHandlerNotificationService.instance;
  final FmhAnalyticsService _analyticsService = FmhAnalyticsService.instance;
  final StorageService _storageService = StorageService.instance;
  NotificationInboxStorageInterface _inboxStorage = InboxStorageService();

  final InAppMessageManager _inAppMessageManager = InAppMessageManager.instance;
  final BadgeManager _badgeManager = BadgeManager.instance;
  ForegroundNotificationOptions _foregroundOptions =
      ForegroundNotificationOptions.defaults;
  UnifiedMessageHandler? _unifiedMessageHandler;
  int _invalidPayloadCount = 0;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  bool _backgroundHandlerRegistered = false;
  BackgroundMessageCallback? _backgroundMessageCallback;
  DataOnlyMessageBridge? _dataOnlyMessageBridge;
  NotificationDeliveryPolicyEngine? _deliveryPolicyEngine;
  void Function(NotificationDeliveryEvent event)? _deliveryEventSink;
  bool _isReplayingBackgroundQueue = false;
  FCMConfiguration _configuration = const FCMConfiguration();
  NotificationStateStore _stateStore =
      SharedPreferencesNotificationStateStore();
  late NotificationDedupeStore _dedupeStore = NotificationDedupeStore(
    stateStore: _stateStore,
  );
  bool _runtimeInitialized = false;

  // Stream controllers
  StreamController<NotificationData?>? _clickStreamController;
  Stream<NotificationData?>? _clickStream;
  final List<NotificationData?> _pendingClickEvents = <NotificationData?>[];

  // State management
  final Set<String> _openedNotifications = <String>{};
  final Set<String> _foregroundShownNotifications = <String>{};
  final Set<String> _persistedInboxIds = <String>{};
  final Map<String, Set<int>> _groupNotificationIds = <String, Set<int>>{};
  bool _hasFetchedInitialNotification = false;

  /// Initializes the notification manager
  Future<Stream<NotificationData?>?> initialize(
    FCMConfiguration configuration,
  ) async {
    try {
      _configuration = configuration;
      _fcmService.setDebugLogging(configuration.enableDebugLogging);
      _stateStore =
          configuration.stateStore ?? SharedPreferencesNotificationStateStore();
      _dedupeStore = NotificationDedupeStore(stateStore: _stateStore);
      await _stateStore.write(
        'fmh_v2_background_configuration',
        configuration.toMap(),
      );
      _foregroundOptions = ForegroundNotificationOptions(
        enabled: configuration.enableForegroundMessageHandling,
        androidDefaults: ForegroundNotificationOptions.defaults.androidDefaults,
        iosDefaults: ForegroundNotificationOptions.defaults.iosDefaults,
      );
      _analyticsService.configure(
        configuration.analyticsOptions,
        enableDebugLogging: configuration.enableDebugLogging,
      );
      _storageService.configure(
        saveNotifications: configuration.saveNotificationsToStorage,
        maxStoredNotifications: configuration.maxStoredNotifications,
        enableDebugLogging: configuration.enableDebugLogging,
      );
      _inAppMessageManager.setDebugLogging(configuration.enableDebugLogging);
      _inboxStorage = InboxStorageService(
        maxItems: configuration.maxStoredNotifications,
      );

      // Initialize services
      final bool fcmInitialized = await _fcmService.initialize();
      if (!fcmInitialized) {
        throw StateError('Firebase Messaging initialization failed.');
      }
      if (configuration.exportDeliveryMetricsToBigQuery) {
        await _fcmService.setDeliveryMetricsExportToBigQuery(true);
      }

      // [Smart Default Channel]
      // Ensure at least one high-importance channel exists to prevent "silent" notification issues on Android.
      final List<NotificationChannelData> effectiveChannels =
          _effectiveChannels(configuration);

      await _notificationService.initialize(
        androidChannels: effectiveChannels,
        androidIconPath: configuration.androidNotificationIconPath,
        actionCategories: configuration.actionCategories,
        windows: configuration.windows,
        enableDebugLogging: configuration.enableDebugLogging,
      );

      if (configuration.requestPermissionOnInitialize) {
        final bool permissionsGranted = await _fcmService.requestPermissions(
          options: configuration.permissionOptions,
        );
        if (!permissionsGranted) {
          _logMessage(
            '[NotificationManager] Notification permission was not granted; non-system surfaces remain available.',
          );
        }
      }

      // Configure iOS foreground notification presentation options
      // Enable automatic notifications for iOS since flutter_local_notifications
      // doesn't show notifications when app is in foreground on iOS
      await _fcmService.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      // Handle FCM token
      if (configuration.synchronizeTokenOnInitialize) {
        await synchronizeToken(
          force: configuration.resynchronizeUnchangedToken,
        );
      }

      if (configuration.updateTokenCallback != null) {
        _listenForTokenRefresh(configuration.updateTokenCallback!);
      } else {
        await _tokenRefreshSubscription?.cancel();
        _tokenRefreshSubscription = null;
      }

      if (configuration.enableDefaultDataOnlyBridge) {
        enableDefaultDataOnlyBridge(
          channelId: configuration.dataOnlyBridgeChannelId,
          titleKey: configuration.dataOnlyBridgeTitleKey,
          bodyKey: configuration.dataOnlyBridgeBodyKey,
        );
      }

      // Set up notification listeners
      if (configuration.enableForegroundMessageHandling) {
        _setupNotificationListeners(
          effectiveChannels,
          configuration.androidNotificationIconPath,
        );
      } else {
        await _foregroundMessageSubscription?.cancel();
        _foregroundMessageSubscription = null;
      }

      // Handle background notifications
      if (configuration.enableBackgroundMessageHandling) {
        _setupBackgroundNotifications();
      } else {
        await _openedMessageSubscription?.cancel();
        _openedMessageSubscription = null;
      }

      await _replayPendingInteractions();

      /*
       * Why: Pending in-app payloads could have been staged while the app was closed,
       * so we hydrate them once initialization finishes to keep campaigns consistent.
       */
      await _inAppMessageManager.flushPendingInAppMessages();

      // Check for initial notification
      final Stream<NotificationData?>? initialStream =
          await _handleInitialNotification(
            configuration.includeInitialNotificationInStream,
          );

      _runtimeInitialized = true;

      // Return appropriate stream
      return initialStream ?? getNotificationClickStream();
    } catch (error, stack) {
      _logMessage('[NotificationManager] Initialization error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      rethrow;
    }
  }

  /// Gets the notification click stream
  Stream<NotificationData?> getNotificationClickStream() {
    if (_clickStreamController == null || _clickStream == null) {
      _clickStreamController = StreamController<NotificationData?>.broadcast(
        onListen: () {
          if (_pendingClickEvents.isEmpty) {
            return;
          }
          for (final NotificationData? event in List<NotificationData?>.from(
            _pendingClickEvents,
          )) {
            _clickStreamController?.add(event);
          }
          _pendingClickEvents.clear();
        },
      );
      _clickStream = _clickStreamController!.stream;
    }
    return _clickStream!;
  }

  /// Installs the shared delivery policy and typed event sink.
  void configureDeliveryControls(
    NotificationDeliveryPolicyEngine engine,
    void Function(NotificationDeliveryEvent event) eventSink,
  ) {
    _deliveryPolicyEngine = engine;
    _deliveryEventSink = eventSink;
    _inAppMessageManager.configureDeliveryControls(engine, eventSink);
  }

  /// Emits an event originating in the local-notification service.
  void emitDeliveryEvent(NotificationDeliveryEvent event) {
    _deliveryEventSink?.call(event);
  }

  /// Exposes a way for tests to emit synthetic click events.
  void emitTestClick(NotificationData data) {
    getNotificationClickStream();
    _emitOrQueueClick(data);
  }

  /// Gets the initial notification data (instance wrapper)
  Future<NotificationData?> getInitialNotificationData() async {
    return await NotificationManager.getInitialNotificationDataStatic();
  }

  /// Gets the initial notification data (static, safe to call early)
  static Future<NotificationData?> getInitialNotificationDataStatic() async {
    try {
      // Check Firebase Messaging initial message
      final RemoteMessage? firebaseInitialMessage = await FCMService.instance
          .getInitialMessage();

      if (firebaseInitialMessage?.data != null) {
        return NotificationData(
          payload: firebaseInitialMessage!.data,
          title: firebaseInitialMessage.notification?.title,
          body: firebaseInitialMessage.notification?.body,
          timestamp: DateTime.now(),
          type: NotificationTypeEnum.terminated,
          isFromTerminated: true,
          messageId: firebaseInitialMessage.messageId,
        );
      }

      // Check flutter_local_notifications initial message
      final NotificationAppLaunchDetails? launchDetails =
          await FirebaseMessagingHandlerNotificationService.instance
              .getNotificationAppLaunchDetails();

      if (launchDetails?.didNotificationLaunchApp ?? false) {
        final payload = launchDetails?.notificationResponse?.payload != null
            ? jsonDecode(launchDetails!.notificationResponse!.payload!)
            : {};

        return NotificationData(
          payload: payload,
          timestamp: DateTime.now(),
          type: NotificationTypeEnum.terminated,
          isFromTerminated: true,
        );
      }

      return null;
    } catch (error, stack) {
      NotificationManager.instance._logMessage(
        '[NotificationManager] Get initial notification error: $error',
      );
      NotificationManager.instance._logMessage(
        '[NotificationManager] Stack trace: $stack',
      );
      return null;
    }
  }

  /// Processes a notification
  Future<void> processNotification(
    RemoteMessage message, {
    bool isFromTerminated = false,
    bool emitToClickStream = true,
  }) async {
    try {
      final String messageKey = _messageKey(message);
      final NotificationLifecycle lifecycle = isFromTerminated
          ? NotificationLifecycle.terminated
          : NotificationLifecycle.resume;
      final NotificationDeliveryRequest request = _requestForMessage(
        message,
        surface: NotificationDeliverySurface.push,
        lifecycle: lifecycle,
      );
      if (await _dedupeStore.checkAndRecord('opened:$messageKey')) {
        _emitEvent(
          NotificationDeliveryEventType.deduplicated,
          request,
          reason: 'Duplicate notification interaction ignored.',
        );
        return;
      }
      if (!_openedNotifications.contains(messageKey)) {
        _openedNotifications.add(messageKey);

        /*
         * Why: Even when the system renders the push, data-only payloads can embed
         * directives for in-app templates; we surface that before continuing so the UI layer
         * can react without waiting for the user to reopen the notification.
         */
        unawaited(_inAppMessageManager.handleRemoteMessage(message));

        // Track notification received
        _analyticsService.trackNotificationReceived(message);

        _emitEvent(NotificationDeliveryEventType.opened, request);

        unawaited(_persistInboxEntry(message, lifecycle));

        // Unified handler (resume/terminated)
        unawaited(_invokeUnifiedHandler(message, lifecycle));

        // Add to click stream
        if (emitToClickStream) {
          _addNotificationClickStreamEvent(
            message.data,
            message: message,
            isFromTerminated: isFromTerminated,
            type: isFromTerminated
                ? NotificationTypeEnum.terminated
                : NotificationTypeEnum.background,
          );
        }

        // Track notification clicked
        _analyticsService.trackNotificationClicked(message);
      }
    } catch (error, stack) {
      _logMessage('[NotificationManager] Process notification error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  /// Shows a notification with actions
  Future<bool> showNotificationWithActions({
    required String title,
    required String body,
    required List<NotificationAction> actions,
    Map<String, dynamic>? payload,
    String? channelId,
    int? notificationId,
    String? actionCategoryId,
  }) async {
    try {
      final id =
          notificationId ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final NotificationDeliveryRequest request = _requestForLocal(
        id: id,
        payload: payload,
      );
      final NotificationDeliveryDecision decision = _evaluate(request);
      if (!decision.isAllowed) return false;

      final bool shown = await _notificationService.showNotificationWithActions(
        id: id,
        title: title,
        body: body,
        actions: actions,
        payload: payload,
        channelId: channelId,
        actionCategoryId: actionCategoryId ?? payload?['category']?.toString(),
      );
      if (!shown) {
        _emitEvent(
          NotificationDeliveryEventType.failed,
          request,
          reason: 'Local notification presentation failed',
        );
        return false;
      }
      _registerDelivery(request);

      _logMessage(
        '[NotificationManager] Notification with actions shown: $title',
      );
      return true;
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Show notification with actions error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  /// Presents a typed local notification, including native detail overrides.
  Future<NotificationOperationResult<int>> showLocalNotification(
    LocalNotificationRequest notification,
  ) async {
    final NotificationDeliveryRequest request = _requestForLocal(
      id: notification.id,
      payload: notification.payload,
    );
    final NotificationDeliveryDecision decision = _evaluate(request);
    if (!decision.isAllowed) {
      return NotificationOperationResult<int>.failure(
        code: NotificationOperationErrorCode.disabled,
        message: decision.reason ?? 'Notification delivery was suppressed.',
      );
    }
    try {
      final bool shown = await _notificationService.showNotification(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        payload: notification.payload,
        channelId: notification.channelId,
        category: notification.category,
        threadIdentifier: notification.threadIdentifier,
        groupKey: notification.groupKey,
        isGroupSummary: notification.isGroupSummary,
        androidDetailsOverride: notification.androidDetails,
        iosDetailsOverride: notification.appleDetails,
        linuxDetailsOverride: notification.linuxDetails,
        windowsDetailsOverride: notification.windowsDetails,
      );
      if (!shown) {
        _emitEvent(
          NotificationDeliveryEventType.failed,
          request,
          reason: 'The platform rejected local presentation.',
        );
        return const NotificationOperationResult<int>.failure(
          code: NotificationOperationErrorCode.platformFailure,
          message: 'The platform rejected local presentation.',
        );
      }
      _registerDelivery(request);
      return NotificationOperationResult<int>.success(notification.id);
    } catch (error) {
      _emitEvent(
        NotificationDeliveryEventType.failed,
        request,
        reason: error.toString(),
      );
      return NotificationOperationResult<int>.failure(
        code: NotificationOperationErrorCode.platformFailure,
        message: 'Local presentation failed.',
        error: error,
      );
    }
  }

  /// Schedules a notification
  Future<bool> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? channelId,
    Map<String, dynamic>? payload,
    List<NotificationAction>? actions,
    bool allowWhileIdle = false,
    NotificationScheduleMode scheduleMode = NotificationScheduleMode.inexact,
    bool fallbackToInexact = true,
  }) async {
    try {
      if (!_configuration.enableNotificationScheduling) return false;
      final NotificationDeliveryRequest request = _requestForLocal(
        id: id,
        payload: payload,
        scheduledAt: scheduledDate,
      );
      final NotificationDeliveryDecision decision = _evaluate(request);
      if (decision.outcome == NotificationDeliveryOutcome.suppressed) {
        return false;
      }
      final DateTime effectiveDate = decision.nextEligibleAt ?? scheduledDate;
      NotificationScheduleMode effectiveMode = scheduleMode;
      if (allowWhileIdle && scheduleMode == NotificationScheduleMode.inexact) {
        effectiveMode = NotificationScheduleMode.inexactAllowWhileIdle;
      }
      final bool requestsExact =
          effectiveMode == NotificationScheduleMode.exact ||
          effectiveMode == NotificationScheduleMode.exactAllowWhileIdle;
      if (isAndroid && requestsExact) {
        final bool canScheduleExact =
            await _notificationService.canScheduleExactNotifications() == true;
        if (!canScheduleExact && !fallbackToInexact) {
          _emitEvent(
            NotificationDeliveryEventType.failed,
            request,
            reason: 'Android exact-alarm access is not granted.',
          );
          return false;
        }
        if (!canScheduleExact) {
          effectiveMode =
              effectiveMode == NotificationScheduleMode.exactAllowWhileIdle
              ? NotificationScheduleMode.inexactAllowWhileIdle
              : NotificationScheduleMode.inexact;
        }
      }
      final result = await _notificationService.scheduleNotification(
        id: id,
        title: title,
        body: body,
        scheduledDate: effectiveDate,
        payload: payload,
        channelId: channelId,
        actions: actions,
        actionCategoryId: payload?['category']?.toString(),
        scheduleMode: effectiveMode,
      );

      if (result) {
        _emitEvent(
          NotificationDeliveryEventType.scheduled,
          NotificationDeliveryRequest(
            surface: request.surface,
            lifecycle: request.lifecycle,
            messageId: request.messageId,
            categoryId: request.categoryId,
            scheduledAt: effectiveDate,
            data: request.data,
          ),
        );
        _analyticsService.trackEvent('notification_scheduled_one_time', {
          'notification_id': id,
          'title': title,
          'scheduled_for': effectiveDate.toIso8601String(),
          'schedule_mode': effectiveMode.name,
        });
      }

      return result;
    } catch (error, stack) {
      _logMessage('[NotificationManager] Schedule notification error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  /// Cancels a scheduled notification
  Future<bool> cancelScheduledNotification(int id) async {
    try {
      if (!_configuration.enableNotificationScheduling) return false;
      final bool cancelled = await _notificationService.cancelNotification(id);
      if (!cancelled) return false;
      _logMessage(
        '[NotificationManager] Scheduled notification cancelled: $id',
      );
      return true;
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Cancel scheduled notification error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  /// Cancels all scheduled notifications
  Future<bool> cancelAllScheduledNotifications() async {
    try {
      if (!_configuration.enableNotificationScheduling) return false;
      final bool cancelled = await _notificationService
          .cancelAllNotifications();
      if (!cancelled) return false;
      _logMessage(
        '[NotificationManager] All scheduled notifications cancelled',
      );
      return true;
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Cancel all scheduled notifications error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  /// Gets pending notifications
  Future<List<PendingNotificationSnapshot>> getPendingNotifications() async {
    try {
      return await _notificationService.getPendingNotifications();
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Get pending notifications error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
      return <PendingNotificationSnapshot>[];
    }
  }

  /// Returns notifications currently visible in the system notification UI.
  Future<List<ActiveNotificationSnapshot>> getActiveNotifications() {
    return _notificationService.getActiveNotifications();
  }

  /// Returns whether Android system notifications are enabled, when known.
  Future<bool?> areNotificationsEnabled() {
    return _notificationService.areNotificationsEnabled();
  }

  /// Deletes an Android notification channel.
  Future<bool> deleteNotificationChannel(String channelId) {
    return _notificationService.deleteNotificationChannel(channelId);
  }

  /// Refreshes the timezone used for local notification scheduling.
  Future<String?> refreshLocalTimezone() async {
    try {
      return await _notificationService.refreshLocalTimezone();
    } catch (error, stack) {
      _logMessage('[NotificationManager] Refresh timezone error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      return null;
    }
  }

  /// Returns the timezone currently configured for local scheduling.
  Future<String?> getConfiguredLocalTimezone() async {
    try {
      return await _notificationService.getConfiguredLocalTimezone();
    } catch (error, stack) {
      _logMessage('[NotificationManager] Get timezone error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      return null;
    }
  }

  /// Opens this app's notification settings when supported.
  Future<bool> openNotificationSettings() =>
      _notificationService.openAppNotificationSettings();

  /// Returns platform and runtime support for every v2 capability.
  Future<NotificationCapabilities> getCapabilities() async {
    final bool remotePush = _fcmService.isSupportedOnCurrentPlatform;
    final bool localPresentation = !isWindows || _configuration.windows != null;
    final bool scheduling =
        _configuration.enableNotificationScheduling &&
        (isAndroid || isIOS || isMacOS || isWindows);
    final bool recurringScheduling = scheduling && !isWindows;
    final bool badge =
        _configuration.enableBadgeManagement &&
        await _notificationService.isBadgeSupported();
    final bool? exactAlarm = await _notificationService
        .canScheduleExactNotifications();

    NotificationCapabilityStatus supported({
      String? reason,
      bool requiresSetup = false,
    }) => NotificationCapabilityStatus(
      supported: true,
      reason: reason,
      requiresSetup: requiresSetup,
    );
    NotificationCapabilityStatus unsupported(String reason) =>
        NotificationCapabilityStatus(supported: false, reason: reason);

    return NotificationCapabilities(
      platform: currentPlatformName,
      statuses: <NotificationCapability, NotificationCapabilityStatus>{
        NotificationCapability.remotePush: remotePush
            ? supported(requiresSetup: true)
            : unsupported(
                _fcmService.unsupportedPlatformReason ??
                    'Remote push is unavailable.',
              ),
        NotificationCapability.localPresentation: localPresentation
            ? supported()
            : unsupported(
                'Windows local notifications require WindowsNotificationOptions.',
              ),
        NotificationCapability.foregroundDelivery: remotePush
            ? supported()
            : supported(reason: 'Local notifications only on this platform.'),
        NotificationCapability.backgroundDelivery: remotePush
            ? supported(requiresSetup: true)
            : unsupported('Remote background delivery is unavailable.'),
        NotificationCapability.terminatedDelivery: remotePush
            ? supported(requiresSetup: true)
            : unsupported('Remote terminated delivery is unavailable.'),
        NotificationCapability.scheduling: scheduling
            ? supported(requiresSetup: isAndroid)
            : unsupported('Scheduling is unavailable or disabled.'),
        NotificationCapability.recurringScheduling: recurringScheduling
            ? supported()
            : unsupported('Recurring scheduling is unavailable.'),
        NotificationCapability.exactScheduling: isAndroid
            ? (exactAlarm == true
                  ? supported()
                  : unsupported(
                      'Android exact-alarm access is not currently granted.',
                    ))
            : (isIOS || isMacOS
                  ? supported(
                      reason: 'Managed by the Apple notification system.',
                    )
                  : unsupported('Exact scheduling is unavailable.')),
        NotificationCapability.appIconBadge: badge
            ? supported()
            : unsupported(
                'Direct app-icon badge mutation is not implemented on this platform.',
              ),
        NotificationCapability.topicSubscriptions:
            remotePush && _configuration.enableTopicSubscriptions
            ? supported()
            : unsupported(
                'FCM topic subscriptions are unavailable or disabled.',
              ),
        NotificationCapability.notificationActions: localPresentation
            ? supported(requiresSetup: isIOS || isMacOS)
            : unsupported('Notification actions are unavailable.'),
        NotificationCapability.inlineReply:
            isAndroid || isIOS || isMacOS || isWindows
            ? supported(requiresSetup: isIOS || isMacOS)
            : unsupported('Inline replies are unavailable.'),
        NotificationCapability.notificationInbox: supported(),
        NotificationCapability.inAppMessaging: supported(),
        NotificationCapability.webServiceWorker: unsupported(
          'Service workers are a web-only capability.',
        ),
        NotificationCapability.deliveryMetricsExport: isAndroid
            ? supported(
                reason: _configuration.exportDeliveryMetricsToBigQuery
                    ? 'Firebase Android delivery-metrics export is enabled.'
                    : 'Available but disabled by configuration.',
              )
            : unsupported(
                'Automatic client-side delivery-metrics export is Android-only; Apple requires an app delegate hook and web requires service-worker setup.',
              ),
      },
    );
  }

  /// Requests Android exact-alarm access when the platform supports it.
  Future<bool> requestExactAlarmPermission() {
    return _notificationService.requestExactAlarmPermission();
  }

  /// Requests notification permission without coupling it to initialization.
  Future<NotificationSettings> requestNotificationPermission(
    NotificationPermissionOptions options,
  ) {
    return _fcmService.requestPermissionSettings(options: options);
  }

  /// Sets badge count for iOS
  Future<void> setIOSBadgeCount(int count) async {
    if (!isIOS || !_configuration.enableBadgeManagement) return;
    await _badgeManager.setBadgeCount(count);
  }

  /// Gets iOS badge count
  Future<int?> getIOSBadgeCount() async {
    if (!isIOS || !await _badgeManager.isSupported()) return null;
    return await _badgeManager.getBadgeCount();
  }

  /// Legacy Android badge helper; applies only when native support is present.
  Future<void> setAndroidBadgeCount(int count) async {
    if (!isAndroid || !_configuration.enableBadgeManagement) return;
    await _badgeManager.setBadgeCount(count);
  }

  /// Gets Android badge count
  Future<int?> getAndroidBadgeCount() async {
    if (!isAndroid || !await _badgeManager.isSupported()) return null;
    return await _badgeManager.getBadgeCount();
  }

  /// Clears badge count
  Future<void> clearBadgeCount() async {
    if (!_configuration.enableBadgeManagement) return;
    await _badgeManager.removeBadge();
  }

  /// Subscribes to a topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      if (!_configuration.enableTopicSubscriptions) {
        throw StateError('Topic subscriptions are disabled by configuration.');
      }
      _validateTopic(topic);
      await _fcmService.subscribeToTopic(topic);
      final Set<String> topics = (await getSubscribedTopics()).toSet()
        ..add(topic);
      await _stateStore.write(
        'fmh_v2_subscribed_topics',
        topics.toList()..sort(),
      );
    } catch (error, stack) {
      _logMessage('[NotificationManager] Subscribe to topic error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      rethrow;
    }
  }

  /// Unsubscribes from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      if (!_configuration.enableTopicSubscriptions) {
        throw StateError('Topic subscriptions are disabled by configuration.');
      }
      _validateTopic(topic);
      await _fcmService.unsubscribeFromTopic(topic);
      final Set<String> topics = (await getSubscribedTopics()).toSet()
        ..remove(topic);
      await _stateStore.write(
        'fmh_v2_subscribed_topics',
        topics.toList()..sort(),
      );
    } catch (error, stack) {
      _logMessage('[NotificationManager] Unsubscribe from topic error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      rethrow;
    }
  }

  /// Unsubscribes from all topics
  Future<void> unsubscribeFromAllTopics() async {
    try {
      if (!_configuration.enableTopicSubscriptions) {
        throw StateError('Topic subscriptions are disabled by configuration.');
      }
      final List<String> topics = await getSubscribedTopics();
      for (final String topic in topics) {
        await _fcmService.unsubscribeFromTopic(topic);
      }
      await _stateStore.remove('fmh_v2_subscribed_topics');
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Unsubscribe from all topics error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
      rethrow;
    }
  }

  /// Topics successfully subscribed through this package on this installation.
  Future<List<String>> getSubscribedTopics() async {
    final Object? stored = await _stateStore.read('fmh_v2_subscribed_topics');
    if (stored is! List) return <String>[];
    return stored.map((dynamic value) => value.toString()).toList()..sort();
  }

  /// The reason the last FCM token fetch returned null, or null if it succeeded.
  /// Useful for surfacing actionable diagnostic messages in the UI.
  String? get lastTokenError => _fcmService.lastTokenError;

  /// Gets FCM token
  Future<String?> getFcmToken() async {
    try {
      return await _fcmService.getToken(
        vapidKey: kIsWeb ? _configuration.webVapidKey : null,
      );
    } catch (error, stack) {
      _logMessage('[NotificationManager] Get FCM token error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      return null;
    }
  }

  /// Clears FCM token
  Future<void> clearToken() async {
    try {
      await _fcmService.deleteToken();
      await _storageService.removeFcmToken();
    } catch (error, stack) {
      _logMessage('[NotificationManager] Clear token error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  void _validateTopic(String topic) {
    final bool valid = RegExp(r'^[a-zA-Z0-9-_.~%]{1,900}$').hasMatch(topic);
    if (!valid) {
      throw ArgumentError.value(topic, 'topic', 'Invalid FCM topic name.');
    }
  }

  Future<void> _hydrateGroupNotificationIds() async {
    if (_groupNotificationIds.isNotEmpty) return;
    final Object? raw = await _stateStore.read('fmh_v2_notification_groups');
    if (raw is! Map) return;
    for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
      final dynamic value = entry.value;
      if (value is List) {
        _groupNotificationIds[entry.key.toString()] = value
            .map((dynamic id) => int.tryParse(id.toString()))
            .whereType<int>()
            .toSet();
      }
    }
  }

  Future<void> _persistGroupNotificationIds() {
    return _stateStore.write('fmh_v2_notification_groups', <String, dynamic>{
      for (final MapEntry<String, Set<int>> entry
          in _groupNotificationIds.entries)
        entry.key: entry.value.toList(),
    });
  }

  /// Sets analytics callback
  void setAnalyticsCallback(
    void Function(String event, Map<String, dynamic> data) callback,
  ) {
    _analyticsService.setCallback(callback);
  }

  /// Tracks analytics event
  void trackAnalyticsEvent(String event, Map<String, dynamic> data) {
    _analyticsService.trackEvent(event, data);
  }

  /// Updates default foreground notification presentation options.
  void setForegroundNotificationOptions(ForegroundNotificationOptions options) {
    _foregroundOptions = options;
  }

  /// Registers in-app notification templates
  void registerInAppTemplates(
    Map<String, InAppNotificationTemplate> templates,
  ) {
    _inAppMessageManager.registerTemplates(templates);
  }

  /// Clears registered in-app templates
  void clearInAppTemplates() {
    _inAppMessageManager.clearTemplates();
  }

  /// Sets fallback display handler for unregistered templates
  void setInAppFallbackDisplayHandler(
    InAppNotificationDisplayCallback? fallback,
  ) {
    _inAppMessageManager.setFallbackDisplayHandler(fallback);
  }

  /// Sets the navigator key used for in-app template presentation.
  void setInAppNavigatorKey(GlobalKey<NavigatorState> navigatorKey) {
    _inAppMessageManager.setNavigatorKey(navigatorKey);
  }

  Future<void> setInAppDeliveryPolicy(InAppDeliveryPolicy policy) async {
    await _inAppMessageManager.setDeliveryPolicy(policy);
  }

  /// Provides stream of in-app messages triggered by data-only pushes
  Stream<InAppNotificationData> getInAppMessageStream({
    bool includePendingStorageItems = true,
  }) => _inAppMessageManager.getMessageStream(
    includePendingStorageItems: includePendingStorageItems,
  );

  /// Flushes any stored in-app messages so the host app can present them now
  Future<void> flushPendingInAppMessages() async {
    await _inAppMessageManager.flushPendingInAppMessages();
  }

  /// Clears pending in-app messages
  Future<void> clearPendingInAppMessages({String? id}) async {
    await _inAppMessageManager.clearPendingInAppMessages(id: id);
  }

  Future<void> setBackgroundProcessingCallback(
    BackgroundMessageCallback? callback,
  ) async {
    _backgroundMessageCallback = callback;
    if (callback != null) {
      await _replayQueuedBackgroundMessages();
    }
  }

  void setDataOnlyMessageBridge(DataOnlyMessageBridge? bridge) {
    _dataOnlyMessageBridge = bridge;
  }

  Future<void> setUnifiedMessageHandler(UnifiedMessageHandler? handler) async {
    _unifiedMessageHandler = handler;
    if (handler != null) {
      await _replayQueuedBackgroundMessages();
    }
  }

  void enableDefaultDataOnlyBridge({
    String? channelId,
    String titleKey = 'title',
    String bodyKey = 'body',
  }) {
    _configuration = _configuration.copyWith(
      enableDefaultDataOnlyBridge: true,
      dataOnlyBridgeChannelId: channelId,
      dataOnlyBridgeTitleKey: titleKey,
      dataOnlyBridgeBodyKey: bodyKey,
    );
    unawaited(
      _stateStore.write(
        'fmh_v2_background_configuration',
        _configuration.toMap(),
      ),
    );
    _dataOnlyMessageBridge = (RemoteMessage message) async {
      final Map<String, dynamic> data = BridgingPayloadValidator.normalize(
        message.data,
      );
      final String? title =
          data[titleKey] as String? ?? message.notification?.title;
      final String? body =
          data[bodyKey] as String? ?? message.notification?.body;

      if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
        return;
      }

      final int id = _notificationIdFor(message);
      final NotificationDeliveryRequest request = _requestForLocal(
        id: id,
        payload: data,
      );
      final NotificationDeliveryDecision decision = _evaluate(request);
      if (!decision.isAllowed) return;

      final bool shown = await _notificationService.showNotification(
        id: id,
        title: title ?? '',
        body: body ?? '',
        payload: data,
        channelId: channelId ?? message.notification?.android?.channelId,
      );
      if (shown) {
        _registerDelivery(request);
      } else {
        _emitEvent(
          NotificationDeliveryEventType.failed,
          request,
          reason: 'Data-only local presentation failed',
        );
      }
    };
  }

  /// Registers a background message handler. The handler must be a top-level or
  /// static function as required by Firebase Messaging.
  Future<void> setBackgroundMessageHandler(
    Future<void> Function(RemoteMessage message) handler,
  ) async {
    try {
      // Register the background handler directly.
      // Note: The handler must be a top-level or static function to work with FirebaseMessaging.
      // Do not wrap it in a closure here.
      await _fcmService.setBackgroundMessageHandler(handler);
      _backgroundHandlerRegistered = true;
      _logMessage('[NotificationManager] Background handler registered');
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Register background handler error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  /// Internal handler to leverage plugin services during background delivery.
  Future<void> handleBackgroundMessage(
    RemoteMessage message, {
    bool skipConfiguredBootstrap = false,
  }) async {
    try {
      await _prepareBackgroundRuntime(
        skipConfiguredBootstrap: skipConfiguredBootstrap,
      );
      _emitEvent(
        NotificationDeliveryEventType.received,
        _requestForMessage(
          message,
          surface: NotificationDeliverySurface.push,
          lifecycle: NotificationLifecycle.background,
        ),
      );
      if (await _shouldStopIncoming(
        message,
        lifecycle: NotificationLifecycle.background,
      )) {
        return;
      }
      await _storageService.saveNotification(message);
      await _persistInboxEntry(message, NotificationLifecycle.background);
      await _inAppMessageManager.handleRemoteMessage(message);
      _analyticsService.trackNotificationReceived(message);
      await _maybeBridgeDataOnlyMessage(message);

      bool handled = await _invokeUnifiedHandler(
        message,
        NotificationLifecycle.background,
      );

      if (_backgroundMessageCallback != null) {
        try {
          final bool callbackHandled = await _backgroundMessageCallback!(
            message,
          );
          handled = handled && callbackHandled;
        } catch (error, stack) {
          _logMessage(
            '[NotificationManager] Background callback error: $error',
          );
          _logMessage('[NotificationManager] Stack trace: $stack');
          handled = false;
        }
      }

      if (!handled) {
        await _queueBackgroundMessage(message);
      } else {
        await _storageService.clearQueuedBackgroundMessages(
          messageId: message.messageId,
        );
      }
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Handle background message error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  Future<void> _prepareBackgroundRuntime({
    bool skipConfiguredBootstrap = false,
  }) async {
    if (_runtimeInitialized) return;
    try {
      if (!skipConfiguredBootstrap) {
        await _configuration.backgroundBootstrap?.call();
      }
      final Object? raw = await _stateStore.read(
        'fmh_v2_background_configuration',
      );
      if (raw is Map) {
        _configuration = FCMConfiguration.fromMap(
          Map<String, dynamic>.from(raw),
        );
      }
      _storageService.configure(
        saveNotifications: _configuration.saveNotificationsToStorage,
        maxStoredNotifications: _configuration.maxStoredNotifications,
        enableDebugLogging: _configuration.enableDebugLogging,
      );
      _inboxStorage = InboxStorageService(
        maxItems: _configuration.maxStoredNotifications,
      );
      _analyticsService.configure(
        _configuration.analyticsOptions,
        enableDebugLogging: _configuration.enableDebugLogging,
      );
      _inAppMessageManager.setDebugLogging(_configuration.enableDebugLogging);
      await _notificationService.initialize(
        androidChannels: _effectiveChannels(_configuration),
        androidIconPath: _configuration.androidNotificationIconPath,
        actionCategories: _configuration.actionCategories,
        windows: _configuration.windows,
        enableDebugLogging: _configuration.enableDebugLogging,
      );
      if (_configuration.enableDefaultDataOnlyBridge) {
        enableDefaultDataOnlyBridge(
          channelId: _configuration.dataOnlyBridgeChannelId,
          titleKey: _configuration.dataOnlyBridgeTitleKey,
          bodyKey: _configuration.dataOnlyBridgeBodyKey,
        );
      }
      _runtimeInitialized = true;
    } catch (error, stack) {
      _logMessage('[NotificationManager] Background bootstrap error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  List<NotificationChannelData> _effectiveChannels(
    FCMConfiguration configuration,
  ) {
    final List<NotificationChannelData> channels = List.from(
      configuration.androidChannels,
    );
    final bool hasHighImportanceChannel = channels.any(
      (NotificationChannelData channel) =>
          channel.importance == NotificationImportanceEnum.high ||
          channel.importance == NotificationImportanceEnum.max,
    );
    if (!hasHighImportanceChannel) {
      channels.add(
        NotificationChannelData(
          id: configuration.defaultChannelId ?? 'default_channel',
          name: 'Default Notifications',
          description: 'Standard high-importance notifications',
          importance: configuration.defaultImportance,
          priority: configuration.defaultPriority,
          playSound: configuration.enableSoundByDefault,
          enableVibration: configuration.enableVibrationByDefault,
          enableLights: configuration.enableLightsByDefault,
          showBadge: configuration.showBadgeByDefault,
        ),
      );
    }
    return channels;
  }

  Future<void> _replayPendingInteractions() async {
    const String key = 'fmh_v2_pending_interactions';
    final NotificationStateStore store =
        SharedPreferencesNotificationStateStore();
    final Object? raw = await store.read(key);
    if (raw is! List) return;
    for (final dynamic item in raw) {
      if (item is! Map) continue;
      final Map<String, dynamic> interaction = Map<String, dynamic>.from(item);
      final Map<String, dynamic> payload = interaction['payload'] is Map
          ? Map<String, dynamic>.from(interaction['payload'] as Map)
          : <String, dynamic>{};
      final NotificationDeliveryEventType type = NotificationDeliveryEventType
          .values
          .firstWhere(
            (NotificationDeliveryEventType value) =>
                value.name == interaction['type'],
            orElse: () => NotificationDeliveryEventType.opened,
          );
      emitDeliveryEvent(
        NotificationDeliveryEvent(
          type: type,
          surface: NotificationDeliverySurface.local,
          messageId:
              interaction['messageId']?.toString() ?? 'local_notification',
          timestamp:
              DateTime.tryParse(interaction['timestamp']?.toString() ?? '') ??
              DateTime.now(),
          lifecycle: NotificationLifecycle.background,
          actionId: interaction['actionId']?.toString(),
          actionInput: interaction['actionInput']?.toString(),
          data: payload,
        ),
      );
      if (type != NotificationDeliveryEventType.dismissed) {
        _emitOrQueueClick(
          NotificationData(
            payload: payload,
            type: NotificationTypeEnum.background,
            messageId: interaction['messageId']?.toString(),
          ),
        );
      }
    }
    await store.remove(key);
  }

  /// Runs a best-effort diagnostics sweep and returns actionable hints.
  Future<NotificationDiagnosticsResult> runDiagnostics() async {
    try {
      final NotificationSettings settings = await _fcmService
          .getNotificationSettings();
      final bool fcmSupported = _fcmService.isSupportedOnCurrentPlatform;
      final bool permissionsGranted =
          !fcmSupported || _isAuthorized(settings.authorizationStatus);

      final String? storedToken = await _storageService.getFcmToken();
      final bool tokenAvailable = storedToken != null && storedToken.isNotEmpty;

      final bool badgeSupported = await _notificationService.isBadgeSupported();
      final bool? systemNotificationsEnabled = await _notificationService
          .areNotificationsEnabled();
      final List<PendingNotificationSnapshot> pendingNotifications =
          await _notificationService.getPendingNotifications();
      final String? configuredTimezone = await _notificationService
          .getConfiguredLocalTimezone();

      final String webPermission = await _notificationService
          .getWebNotificationPermissionStatus();
      final bool webAllowed = webPermission == 'granted';
      final Map<String, dynamic> webRuntimeDiagnostics =
          await _notificationService.getWebRuntimeDiagnostics();

      final Map<String, dynamic> deliveryDiagnostics = _inAppMessageManager
          .getDeliveryDiagnostics(DateTime.now());
      final int queuedBackgroundMessages =
          (await _storageService.getQueuedBackgroundMessages()).length;

      final List<String> recommendations = <String>[];

      if (!permissionsGranted) {
        recommendations.add(
          'Prompt the user for notification permissions; current status: '
          '${settings.authorizationStatus.name}.',
        );
      }

      if (systemNotificationsEnabled == false) {
        recommendations.add(
          'Android system notifications are disabled for this app. Open notification settings and enable them.',
        );
      }

      if (!fcmSupported) {
        recommendations.add(
          _fcmService.unsupportedPlatformReason ??
              'Firebase Cloud Messaging is unavailable on this platform.',
        );
        recommendations.add(
          'Use local notifications, scheduling, inbox, and in-app templates on desktop. For remote delivery, send through your own backend and handle desktop presentation locally.',
        );
      }

      if (fcmSupported && !tokenAvailable) {
        recommendations.add(
          'No stored FCM token found. Ensure init() completed and updateTokenCallback saved the token.',
        );
      }

      if (!badgeSupported) {
        recommendations.add(
          'App icon badges are not supported on $currentPlatformName or the current launcher.',
        );
      }

      if (isWeb && !webAllowed) {
        recommendations.add(
          'Browser notifications are currently "$webPermission". Trigger a permission prompt or guide the user to allow notifications.',
        );
      }

      if (isWeb && webRuntimeDiagnostics['notificationApiAvailable'] == false) {
        recommendations.add(
          'This browser does not expose the Notification API. Use a supported browser such as Chrome, Edge, or Safari with web notifications enabled.',
        );
      }

      if (isWeb && webRuntimeDiagnostics['isSecureContext'] == false) {
        recommendations.add(
          'Web notifications require a secure context. Serve the app from HTTPS or localhost before testing push delivery.',
        );
      }

      if (isWeb &&
          webRuntimeDiagnostics['serviceWorkerApiAvailable'] == false) {
        recommendations.add(
          'Service workers are unavailable in this browser context. Web push will not function until service worker support is available.',
        );
      }

      if (isWeb &&
          webRuntimeDiagnostics['serviceWorkerApiAvailable'] == true &&
          webRuntimeDiagnostics['serviceWorkerControllerPresent'] == false) {
        recommendations.add(
          'No active service worker is controlling this page. Verify the Firebase messaging service worker is registered at the expected scope.',
        );
      }

      if (pendingNotifications.length > 16) {
        recommendations.add(
          'There are ${pendingNotifications.length} pending notifications queued locally. Consider pruning scheduled notifications.',
        );
      }

      return NotificationDiagnosticsResult(
        success: true,
        permissionsGranted: permissionsGranted,
        authorizationStatus: settings.authorizationStatus.name,
        fcmTokenAvailable: tokenAvailable,
        badgeSupported: badgeSupported,
        webNotificationsAllowed: webAllowed,
        pendingNotificationCount: pendingNotifications.length,
        platform: currentPlatformName,
        recommendations: recommendations,
        metadata: {
          'alertSetting': settings.alert.name,
          'badgeSetting': settings.badge.name,
          'soundSetting': settings.sound.name,
          'showPreviews': settings.showPreviews.name,
          'providesAppNotificationSettings':
              settings.providesAppNotificationSettings.name,
          'fcmSupported': fcmSupported,
          'fcmUnsupportedReason': _fcmService.unsupportedPlatformReason,
          'webPermission': webPermission,
          'webDiagnostics': webRuntimeDiagnostics,
          'storedTokenPresent': tokenAvailable,
          'systemNotificationsEnabled': systemNotificationsEnabled,
          'configuredTimezone': configuredTimezone,
          'deliveryPolicy': deliveryDiagnostics,
          'queuedBackgroundMessages': queuedBackgroundMessages,
          'dataBridgeEnabled': _dataOnlyMessageBridge != null,
          'backgroundHandlerRegistered': _backgroundHandlerRegistered,
          'invalidPayloadCount': _invalidPayloadCount,
        },
      );
    } catch (error, stack) {
      _logMessage('[NotificationManager] Diagnostics error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      return NotificationDiagnosticsResult.failure(
        platform: currentPlatformName,
        error: error.toString(),
      );
    }
  }

  bool _isAuthorized(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  Future<void> _maybeBridgeDataOnlyMessage(RemoteMessage message) async {
    if (_dataOnlyMessageBridge == null) {
      return;
    }
    if (message.notification != null) {
      return;
    }
    try {
      final Map<String, dynamic> data = BridgingPayloadValidator.normalize(
        message.data,
      );
      if (!_validateBridgingPayload(data)) {
        return;
      }
      final String? command = data['command']?.toString();
      if (command == NotificationEnvelopeCommand.silent.name ||
          command == NotificationEnvelopeCommand.cancel.name ||
          command == NotificationEnvelopeCommand.markRead.name) {
        return;
      }
      final Map<String, dynamic> messageMap = message.toMap();
      messageMap['data'] = data;
      await _dataOnlyMessageBridge!(RemoteMessage.fromMap(messageMap));
    } catch (error, stack) {
      _logMessage('[NotificationManager] Data-only bridge error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  bool _validateBridgingPayload(Map<String, dynamic> data) {
    return BridgingPayloadValidator.validate(
      data,
      onError: (String reason) {
        _invalidPayloadCount++;
        _logMessage('[UnifiedHandler] invalid payload: $reason');
      },
    );
  }

  Future<void> _queueBackgroundMessage(RemoteMessage message) async {
    try {
      await _storageService.saveQueuedBackgroundMessage(
        _serializeRemoteMessage(message),
      );
    } catch (error, stack) {
      _logMessage('[NotificationManager] Queue background error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  Future<void> _replayQueuedBackgroundMessages() async {
    if (_backgroundMessageCallback == null || _isReplayingBackgroundQueue) {
      return;
    }
    _isReplayingBackgroundQueue = true;
    try {
      final List<Map<String, dynamic>> queued = await _storageService
          .getQueuedBackgroundMessages();
      if (queued.isEmpty) {
        return;
      }

      for (final Map<String, dynamic> item in queued) {
        try {
          final RemoteMessage message = RemoteMessage.fromMap(item);
          final bool handled = await _backgroundMessageCallback!(message);
          if (handled) {
            await _storageService.clearQueuedBackgroundMessages(
              messageId: message.messageId,
            );
          }
        } catch (error, stack) {
          _logMessage('[NotificationManager] Replay background error: $error');
          _logMessage('[NotificationManager] Stack trace: $stack');
        }
      }
    } finally {
      _isReplayingBackgroundQueue = false;
    }
  }

  Map<String, dynamic> _serializeRemoteMessage(RemoteMessage message) {
    final Map<String, dynamic> map = <String, dynamic>{
      'messageId':
          message.messageId ??
          'queued_${DateTime.now().millisecondsSinceEpoch}',
      'data': message.data,
      'sentTime': message.sentTime?.millisecondsSinceEpoch,
      'category': message.category,
      'collapseKey': message.collapseKey,
      'senderId': message.senderId,
      'ttl': message.ttl,
      'notification': message.notification == null
          ? null
          : {
              'title': message.notification?.title,
              'body': message.notification?.body,
            },
    };

    map.removeWhere((String key, dynamic value) => value == null);
    return map;
  }

  /// Disposes of resources
  Future<void> dispose() async {
    try {
      _openedNotifications.clear();
      _foregroundShownNotifications.clear();
      await _foregroundMessageSubscription?.cancel();
      await _openedMessageSubscription?.cancel();
      await _clickStreamController?.close();
      _clickStreamController = null;
      _clickStream = null;
      await _inAppMessageManager.dispose();
      await _tokenRefreshSubscription?.cancel();
      _foregroundMessageSubscription = null;
      _openedMessageSubscription = null;
      _tokenRefreshSubscription = null;
      _backgroundHandlerRegistered = false;
      _backgroundMessageCallback = null;
      _dataOnlyMessageBridge = null;
      _logMessage('[NotificationManager] Disposed');
    } catch (error, stack) {
      _logMessage('[NotificationManager] Dispose error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  /// Fetches the current Firebase token and synchronizes it with the host app.
  Future<bool> synchronizeToken({bool force = false}) async {
    try {
      final String? currentToken = await _fcmService.getToken(
        vapidKey: kIsWeb ? _configuration.webVapidKey : null,
      );

      if (currentToken == null) {
        _logMessage('[NotificationManager] Error fetching FCM Token!');
        _analyticsService.trackTokenEvent('error', null);
        return false;
      }

      final String? storedToken = await _storageService.getFcmToken();
      if (!force && storedToken == currentToken) {
        _logMessage('[NotificationManager] FCM token unchanged');
        return true;
      }

      _analyticsService.trackTokenEvent(
        storedToken == null ? 'fetched' : 'refreshed',
        currentToken,
      );

      if (_configuration.updateTokenCallback != null) {
        final bool updateSuccessful = await _configuration.updateTokenCallback!(
          currentToken,
        );
        if (!updateSuccessful) {
          _logMessage(
            '[NotificationManager] updateTokenCallback returned false; token not persisted',
          );
          return false;
        }
      }

      await _storageService.saveFcmToken(currentToken);
      _analyticsService.trackTokenEvent('updated', currentToken);
      return true;
    } catch (error, stack) {
      _logMessage('[NotificationManager] Handle FCM token error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  void _listenForTokenRefresh(
    Future<bool> Function(String fcmToken) updateTokenCallback,
  ) {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _fcmService.onTokenRefresh.listen(
      (String refreshedToken) async {
        try {
          _analyticsService.trackTokenEvent('refreshed', refreshedToken);
          final bool updateSuccessful = await updateTokenCallback(
            refreshedToken,
          );
          if (updateSuccessful) {
            await _storageService.saveFcmToken(refreshedToken);
            _analyticsService.trackTokenEvent('updated', refreshedToken);
          } else {
            _logMessage(
              '[NotificationManager] Token refresh callback returned false; pending retry next refresh',
            );
          }
        } catch (error, stack) {
          _logMessage(
            '[NotificationManager] Token refresh handling error: $error',
          );
          _logMessage('[NotificationManager] Stack trace: $stack');
        }
      },
      onError: (Object error, StackTrace stack) {
        _logMessage('[NotificationManager] Token refresh stream error: $error');
        _logMessage('[NotificationManager] Stack trace: $stack');
      },
    );
  }

  void _setupNotificationListeners(
    List<NotificationChannelData> androidChannels,
    String androidNotificationIconPath,
  ) {
    _foregroundMessageSubscription?.cancel();
    _foregroundMessageSubscription = _fcmService.onMessage.listen((
      RemoteMessage message,
    ) async {
      await _handleForegroundMessage(
        message,
        androidChannels,
        androidNotificationIconPath,
      );
    });
  }

  Future<void> _handleForegroundMessage(
    RemoteMessage message,
    List<NotificationChannelData> androidChannels,
    String androidNotificationIconPath,
  ) async {
    try {
      _emitEvent(
        NotificationDeliveryEventType.received,
        _requestForMessage(
          message,
          surface: NotificationDeliverySurface.push,
          lifecycle: NotificationLifecycle.foreground,
        ),
      );
      if (await _shouldStopIncoming(
        message,
        lifecycle: NotificationLifecycle.foreground,
      )) {
        return;
      }
      /*
       * Why: Silent pushes rely on the same onMessage entry point; handling them first lets
       * us honor template triggers even when the system decides not to present a banner.
       */
      await _inAppMessageManager.handleRemoteMessage(message);

      final RemoteNotification? notification = message.notification;

      await _storageService.saveNotification(message);
      await _persistInboxEntry(message, NotificationLifecycle.foreground);
      if (notification == null) {
        await _maybeBridgeDataOnlyMessage(message);
      }

      await _invokeUnifiedHandler(message, NotificationLifecycle.foreground);

      if (!_foregroundOptions.enabled) {
        return;
      }

      final String messageKey = _messageKey(message);
      if (notification != null &&
          !_foregroundShownNotifications.contains(messageKey)) {
        _foregroundShownNotifications.add(messageKey);

        if (isAndroid) {
          await _showAndroidNotification(
            message,
            androidChannels,
            androidNotificationIconPath,
          );
        } else if (isIOS) {
          await _showIOSNotification(message);
        } else {
          // Web platform
          await _showWebNotification(message);
        }
      }
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Handle foreground message error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  Future<void> _showIOSNotification(RemoteMessage message) async {
    final NotificationDeliveryRequest request = _requestForMessage(
      message,
      surface: NotificationDeliverySurface.local,
      lifecycle: NotificationLifecycle.foreground,
    );
    final NotificationDeliveryDecision decision = _evaluate(request);
    if (!decision.isAllowed) return;

    DarwinNotificationDetails? details;
    if (_foregroundOptions.iosBuilder != null) {
      details = await Future<DarwinNotificationDetails?>.value(
        _foregroundOptions.iosBuilder!(_buildForegroundContext(message)),
      );
    }
    details ??= _foregroundOptions.iosDefaults;
    if (_foregroundOptions.iosSoundFileName != null) {
      details = DarwinNotificationDetails(
        presentAlert: details?.presentAlert ?? true,
        presentBadge: details?.presentBadge ?? true,
        presentSound: details?.presentSound ?? true,
        sound: _foregroundOptions.iosSoundFileName,
        categoryIdentifier: details?.categoryIdentifier ?? message.category,
        threadIdentifier: details?.threadIdentifier,
      );
    }

    final bool shown = await _notificationService.showNotification(
      id: _notificationIdFor(message),
      title: message.notification?.title ?? '',
      body: message.notification?.body ?? '',
      payload: message.data,
      category: message.category ?? message.data['category']?.toString(),
      iosDetailsOverride: details,
    );
    if (shown) {
      _registerDelivery(request);
    } else {
      _emitEvent(
        NotificationDeliveryEventType.failed,
        request,
        reason: 'Local iOS presentation failed',
      );
    }
  }

  Future<void> _showAndroidNotification(
    RemoteMessage message,
    List<NotificationChannelData> androidChannels,
    String androidNotificationIconPath,
  ) async {
    try {
      final NotificationDeliveryRequest request = _requestForMessage(
        message,
        surface: NotificationDeliverySurface.local,
        lifecycle: NotificationLifecycle.foreground,
      );
      final NotificationDeliveryDecision decision = _evaluate(request);
      if (!decision.isAllowed) return;

      final AndroidNotificationDetails? androidOverride =
          await _resolveAndroidForegroundDetails(message);

      // Determine channel ID - use provided one or fall back to first available channel
      String? channelId =
          message.notification?.android?.channelId ??
          message.data['channelId']?.toString() ??
          _configuration.defaultChannelId;
      AndroidNotificationChannel? selectedChannel;

      if (channelId != null) {
        // Look for the specified channel
        for (final NotificationChannelData channelData in androidChannels) {
          if (channelData.id == channelId) {
            selectedChannel = channelData.toAndroidNotificationChannel();
            break;
          }
        }

        if (selectedChannel == null) {
          _logMessage(
            '[NotificationManager] Channel ID not found: $channelId, falling back to default',
          );
          channelId = null; // Will fall back to default
        }
      }

      // Fall back to first available channel if no channel specified or found
      if (channelId == null && androidChannels.isNotEmpty) {
        channelId = androidChannels.first.id;
        selectedChannel = androidChannels.first.toAndroidNotificationChannel();
        _logMessage('[NotificationManager] Using default channel: $channelId');
      }

      // Show notification if we have a valid channel
      if (channelId != null) {
        final bool shown = await _notificationService.showNotification(
          id: _notificationIdFor(message),
          title: message.notification?.title ?? '',
          body: message.notification?.body ?? '',
          payload: message.data,
          channelId: channelId,
          androidDetailsOverride: androidOverride,
        );
        if (shown) {
          _registerDelivery(request);
        } else {
          _emitEvent(
            NotificationDeliveryEventType.failed,
            request,
            reason: 'Local Android presentation failed',
          );
        }
      } else {
        _logMessage(
          '[NotificationManager] No Android channels available for notification',
        );
      }
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Show Android notification error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  Future<AndroidNotificationDetails?> _resolveAndroidForegroundDetails(
    RemoteMessage message,
  ) async {
    final ForegroundNotificationContext context = _buildForegroundContext(
      message,
    );
    if (_foregroundOptions.androidBuilder != null) {
      final AndroidNotificationDetails? builtDetails =
          await Future<AndroidNotificationDetails?>.value(
            _foregroundOptions.androidBuilder!(context),
          );
      if (builtDetails != null) {
        return builtDetails;
      }
    }

    // Apply default sound if configured
    AndroidNotificationDetails? defaults = _foregroundOptions.androidDefaults;
    if (_foregroundOptions.androidSoundFileName != null && defaults != null) {
      return AndroidNotificationDetails(
        defaults.channelId,
        defaults.channelName,
        channelDescription: defaults.channelDescription,
        importance: defaults.importance,
        priority: defaults.priority,
        showWhen: defaults.showWhen,
        enableVibration: defaults.enableVibration,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(
          _foregroundOptions.androidSoundFileName!,
        ),
      );
    }

    return defaults;
  }

  ForegroundNotificationContext _buildForegroundContext(RemoteMessage message) {
    return ForegroundNotificationContext(message: message);
  }

  String _messageKey(RemoteMessage message) {
    return message.messageId ??
        message.data['idempotencyKey']?.toString() ??
        message.data['dedupeKey']?.toString() ??
        message.data['messageId']?.toString() ??
        'derived:${_stableHash(jsonEncode(<String, dynamic>{'data': message.data, 'title': message.notification?.title, 'body': message.notification?.body, 'sentTime': message.sentTime?.toUtc().toIso8601String()}))}';
  }

  Future<bool> _shouldStopIncoming(
    RemoteMessage message, {
    required NotificationLifecycle lifecycle,
  }) async {
    final Map<String, dynamic> data = BridgingPayloadValidator.normalize(
      message.data,
    );
    final NotificationDeliveryRequest request = _requestForMessage(
      message,
      surface: NotificationDeliverySurface.push,
      lifecycle: lifecycle,
    );
    NotificationEnvelope? envelope;
    if (data.containsKey('schemaVersion')) {
      final Map<String, dynamic> merged = <String, dynamic>{
        ...data,
        if (data['id'] == null && message.messageId != null)
          'id': message.messageId,
        if (data['title'] == null && message.notification?.title != null)
          'title': message.notification?.title,
        if (data['body'] == null && message.notification?.body != null)
          'body': message.notification?.body,
      };
      envelope = NotificationEnvelope.fromMap(merged);
      final NotificationEnvelopeValidationResult validation = envelope
          .validate();
      if (!validation.isValid) {
        _invalidPayloadCount++;
        _emitEvent(
          NotificationDeliveryEventType.failed,
          request,
          reason: validation.errors.join('; '),
        );
        return true;
      }
      if (envelope.isExpired()) {
        _emitEvent(
          NotificationDeliveryEventType.expired,
          request,
          reason: 'Notification envelope expired before processing.',
        );
        return true;
      }
    }

    final String dedupeKey =
        envelope?.effectiveIdempotencyKey ?? _messageKey(message);
    final bool duplicate = await _dedupeStore.checkAndRecord(
      'received:$dedupeKey',
      expiresAt: envelope?.expiresAt,
    );
    if (duplicate) {
      _emitEvent(
        NotificationDeliveryEventType.deduplicated,
        request,
        reason: 'Duplicate notification payload ignored.',
      );
      return true;
    }

    switch (envelope?.command) {
      case NotificationEnvelopeCommand.cancel:
        final bool cancelled = await _notificationService.cancelNotification(
          _stableHash(envelope!.id) & 0x7fffffff,
        );
        await _inboxStorage.delete(<String>[envelope.id]);
        _emitEvent(
          cancelled
              ? NotificationDeliveryEventType.cancelled
              : NotificationDeliveryEventType.failed,
          request,
          reason: cancelled
              ? 'Remote cancellation completed.'
              : 'Remote cancellation could not reach the platform.',
        );
        return true;
      case NotificationEnvelopeCommand.markRead:
        await _inboxStorage.markRead(<String>[envelope!.id]);
        _emitEvent(
          NotificationDeliveryEventType.commandProcessed,
          request,
          reason: 'Inbox item marked read.',
        );
        return true;
      case NotificationEnvelopeCommand.silent:
      case NotificationEnvelopeCommand.display:
      case NotificationEnvelopeCommand.replace:
      case null:
        return false;
    }
  }

  int _notificationIdFor(RemoteMessage message) {
    return _stableHash(_messageKey(message)) & 0x7fffffff;
  }

  int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final int byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  Future<void> _showWebNotification(RemoteMessage message) async {
    try {
      final RemoteNotification? notification = message.notification;

      if (notification != null) {
        await _notificationService.showWebNotification(
          title: notification.title ?? 'Notification',
          body: notification.body ?? '',
          icon: '/icons/Icon-192.png',
          data: message.data,
        );
      }
    } catch (error, stack) {
      _logMessage('[NotificationManager] Show web notification error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  void _setupBackgroundNotifications() {
    _openedMessageSubscription?.cancel();
    _openedMessageSubscription = _fcmService.onMessageOpenedApp.listen(
      (message) => unawaited(processNotification(message)),
    );
  }

  Future<Stream<NotificationData?>?> _handleInitialNotification(
    bool includeInitialNotificationInStream,
  ) async {
    try {
      // Check Firebase Messaging initial message
      final RemoteMessage? firebaseInitialMessage = await _fcmService
          .getInitialMessage();
      if (firebaseInitialMessage?.data != null &&
          !_hasFetchedInitialNotification) {
        await processNotification(
          firebaseInitialMessage!,
          isFromTerminated: true,
          emitToClickStream: includeInitialNotificationInStream,
        );
        _hasFetchedInitialNotification = true;

        if (includeInitialNotificationInStream) {
          return getNotificationClickStream();
        }
      }

      // Check flutter_local_notifications initial message
      final NotificationAppLaunchDetails? launchDetails =
          await _notificationService.getNotificationAppLaunchDetails();

      if ((launchDetails?.didNotificationLaunchApp ?? false) &&
          !_hasFetchedInitialNotification) {
        final payload = launchDetails?.notificationResponse?.payload != null
            ? jsonDecode(launchDetails!.notificationResponse!.payload!)
            : {};

        await processNotification(
          RemoteMessage.fromMap({'data': payload}),
          isFromTerminated: true,
          emitToClickStream: includeInitialNotificationInStream,
        );

        _hasFetchedInitialNotification = true;

        if (includeInitialNotificationInStream) {
          return getNotificationClickStream();
        }
      }

      return null;
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Handle initial notification error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
      return null;
    }
  }

  void _addNotificationClickStreamEvent(
    Map<String, dynamic> payload, {
    RemoteMessage? message,
    bool isFromTerminated = false,
    NotificationTypeEnum type = NotificationTypeEnum.foreground,
  }) {
    try {
      final NotificationData event = NotificationData(
        payload: payload,
        title: message?.notification?.title,
        body: message?.notification?.body,
        imageUrl:
            message?.notification?.android?.imageUrl ??
            message?.notification?.apple?.imageUrl,
        icon:
            message?.notification?.android?.smallIcon ??
            message?.notification?.apple?.badge,
        category: message?.category,
        timestamp: DateTime.now(),
        type: type,
        isFromTerminated: isFromTerminated,
        messageId: message?.messageId,
        senderId: message?.senderId,
        badgeCount: message?.notification?.apple?.badge != null
            ? int.tryParse(message!.notification!.apple!.badge.toString())
            : null,
        isSilent:
            message?.notification?.android?.channelId?.contains('silent') ??
            false,
        sound:
            message?.notification?.android?.sound ??
            message?.notification?.apple?.sound?.name,
        tag: message?.notification?.android?.tag,
        metadata: {
          'ttl': message?.ttl,
          'collapseKey': message?.collapseKey,
          'contentAvailable': message?.contentAvailable,
        },
      );
      _emitOrQueueClick(event);
    } catch (error, stack) {
      _logMessage('[NotificationManager] Add click stream event error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  void _emitOrQueueClick(NotificationData? event) {
    if (event == null) {
      return;
    }
    if (_clickStreamController != null && _clickStreamController!.hasListener) {
      _clickStreamController!.add(event);
    } else {
      _pendingClickEvents.add(event);
    }
  }

  NormalizedMessage _normalizeMessage(
    RemoteMessage message,
    NotificationLifecycle lifecycle,
  ) {
    final Map<String, dynamic> data = BridgingPayloadValidator.normalize(
      message.data,
    );
    Map<String, dynamic>? analytics;
    final dynamic analyticsRaw = data['analytics'];
    if (analyticsRaw is Map<String, dynamic>) {
      analytics = Map<String, dynamic>.from(analyticsRaw);
    } else if (analyticsRaw is String) {
      try {
        final decoded = jsonDecode(analyticsRaw);
        if (decoded is Map<String, dynamic>) {
          analytics = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // ignore parsing errors; fallback to null
      }
    }

    final String? imageUrl =
        message.notification?.android?.imageUrl ??
        message.notification?.apple?.imageUrl ??
        data['image'] as String?;

    return NormalizedMessage(
      id:
          data['id']?.toString() ??
          message.messageId ??
          data['messageId']?.toString() ??
          '${DateTime.now().millisecondsSinceEpoch}',
      title: message.notification?.title ?? data['title'] as String?,
      body: message.notification?.body ?? data['body'] as String?,
      imageUrl: imageUrl,
      data: data,
      actions: _parseActions(data['actions']),
      receivedAt: DateTime.now(),
      origin: 'remote',
      channelId: message.notification?.android?.channelId,
      analytics: analytics,
      rawMessage: message,
      lifecycle: lifecycle,
    );
  }

  Future<bool> _invokeUnifiedHandler(
    RemoteMessage message,
    NotificationLifecycle lifecycle,
  ) async {
    if (_unifiedMessageHandler == null) {
      return true;
    }
    try {
      final normalized = _normalizeMessage(message, lifecycle);
      return await _unifiedMessageHandler!(normalized, lifecycle);
    } catch (error, stack) {
      _logMessage('[NotificationManager] Unified handler error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  NotificationDeliveryRequest _requestForMessage(
    RemoteMessage message, {
    required NotificationDeliverySurface surface,
    required NotificationLifecycle lifecycle,
    DateTime? scheduledAt,
  }) {
    final Map<String, dynamic> data = BridgingPayloadValidator.normalize(
      message.data,
    );
    return NotificationDeliveryRequest(
      surface: surface,
      lifecycle: lifecycle,
      messageId:
          data['idempotencyKey']?.toString() ??
          data['id']?.toString() ??
          message.messageId ??
          data['messageId']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      categoryId: data['category']?.toString() ?? message.category,
      scheduledAt: scheduledAt,
      data: data,
    );
  }

  NotificationDeliveryRequest _requestForLocal({
    required int id,
    Map<String, dynamic>? payload,
    DateTime? scheduledAt,
  }) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(
      payload ?? const <String, dynamic>{},
    );
    return NotificationDeliveryRequest(
      surface: NotificationDeliverySurface.local,
      lifecycle: NotificationLifecycle.foreground,
      messageId: data['messageId']?.toString() ?? id.toString(),
      categoryId: data['category']?.toString(),
      scheduledAt: scheduledAt,
      data: data,
    );
  }

  NotificationDeliveryDecision _evaluate(NotificationDeliveryRequest request) {
    _emitEvent(NotificationDeliveryEventType.received, request);
    final NotificationDeliveryDecision decision =
        _deliveryPolicyEngine?.evaluate(request) ??
        NotificationDeliveryDecision.allow;
    switch (decision.outcome) {
      case NotificationDeliveryOutcome.allowed:
        break;
      case NotificationDeliveryOutcome.suppressed:
        _emitEvent(
          NotificationDeliveryEventType.suppressed,
          request,
          reason: decision.reason,
        );
        break;
      case NotificationDeliveryOutcome.deferred:
        _emitEvent(
          NotificationDeliveryEventType.deferred,
          request,
          reason: decision.reason,
          nextEligibleAt: decision.nextEligibleAt,
        );
        break;
    }
    return decision;
  }

  void _registerDelivery(NotificationDeliveryRequest request) {
    _deliveryPolicyEngine?.registerDelivery(request);
    _emitEvent(NotificationDeliveryEventType.delivered, request);
  }

  void _emitEvent(
    NotificationDeliveryEventType type,
    NotificationDeliveryRequest request, {
    String? actionId,
    String? reason,
    DateTime? nextEligibleAt,
  }) {
    _deliveryEventSink?.call(
      NotificationDeliveryEvent(
        type: type,
        surface: request.surface,
        messageId: request.messageId,
        timestamp: DateTime.now(),
        lifecycle: request.lifecycle,
        categoryId: request.categoryId,
        actionId: actionId,
        reason: reason,
        nextEligibleAt: nextEligibleAt,
        data: request.data,
      ),
    );
  }

  void _logMessage(String message) {
    if (kDebugMode && _configuration.enableDebugLogging) {
      print(message);
    }
  }

  // ========== ADDITIONAL METHODS FOR BACKWARD COMPATIBILITY ==========

  /// Creates a custom notification channel with sound (Android)
  Future<void> createCustomSoundChannel({
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String soundFileName,
    NotificationImportanceEnum importance = NotificationImportanceEnum.high,
    NotificationPriorityEnum priority = NotificationPriorityEnum.high,
    bool enableVibration = true,
    bool enableLights = true,
  }) async {
    try {
      final channel = NotificationChannelData(
        id: channelId,
        name: channelName,
        description: channelDescription,
        importance: importance,
        priority: priority,
        playSound: true,
        enableVibration: enableVibration,
        enableLights: enableLights,
        soundFileName: soundFileName,
      );

      await _notificationService.createNotificationChannel(channel);
      _logMessage(
        '[NotificationManager] Custom sound channel created: $channelId',
      );
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Create custom sound channel error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  /// Gets available system notification sounds (iOS)
  Future<List<String>?> getAvailableSounds() async {
    try {
      // This would typically involve platform-specific implementation
      // For now, return a basic list of common sounds
      return ['default', 'glass.caf', 'horn.caf', 'bell.caf', 'electronic.caf'];
    } catch (error, stack) {
      _logMessage('[NotificationManager] Get available sounds error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      return null;
    }
  }

  /// Schedules a recurring notification
  Future<bool> scheduleRecurringNotification({
    required int id,
    required String title,
    required String body,
    required RepeatIntervalEnum repeatInterval,
    required int hour,
    required int minute,
    String? channelId,
    Map<String, dynamic>? payload,
    List<NotificationAction>? actions,
  }) async {
    try {
      if (!_configuration.enableNotificationScheduling) return false;
      final DateTime now = DateTime.now();
      DateTime initial = DateTime(now.year, now.month, now.day, hour, minute);

      if (initial.isBefore(now)) {
        initial = initial.add(const Duration(days: 1));
      }

      final NotificationDeliveryRequest request = _requestForLocal(
        id: id,
        payload: payload,
        scheduledAt: initial,
      );
      final NotificationDeliveryDecision decision = _evaluate(request);
      if (decision.outcome == NotificationDeliveryOutcome.suppressed) {
        return false;
      }
      initial = decision.nextEligibleAt ?? initial;

      final bool scheduled = await _notificationService
          .scheduleRecurringNotification(
            id: id,
            title: title,
            body: body,
            repeatInterval: repeatInterval,
            initialScheduleDate: initial,
            channelId: channelId,
            payload: payload,
            actions: actions,
          );

      if (scheduled) {
        _emitEvent(
          NotificationDeliveryEventType.scheduled,
          NotificationDeliveryRequest(
            surface: request.surface,
            lifecycle: request.lifecycle,
            messageId: request.messageId,
            categoryId: request.categoryId,
            scheduledAt: initial,
            data: request.data,
          ),
        );
        _analyticsService.trackEvent('notification_scheduled_recurring', {
          'notification_id': id,
          'title': title,
          'repeat_interval': repeatInterval.name,
          'scheduled_start': initial.toIso8601String(),
        });
        _logMessage(
          '[NotificationManager] Recurring notification scheduled: $id (${repeatInterval.name})',
        );
      }
      return scheduled;
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Schedule recurring notification error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  /// Schedules a weekly notification on a specific weekday.
  Future<bool> scheduleWeeklyNotification({
    required int id,
    required String title,
    required String body,
    required int weekday,
    required int hour,
    required int minute,
    String? channelId,
    Map<String, dynamic>? payload,
    List<NotificationAction>? actions,
  }) async {
    try {
      if (!_configuration.enableNotificationScheduling) return false;
      DateTime initial = _nextWeeklyDate(
        weekday: weekday,
        hour: hour,
        minute: minute,
      );
      final NotificationDeliveryRequest request = _requestForLocal(
        id: id,
        payload: payload,
        scheduledAt: initial,
      );
      final NotificationDeliveryDecision decision = _evaluate(request);
      if (decision.outcome == NotificationDeliveryOutcome.suppressed) {
        return false;
      }
      initial = decision.nextEligibleAt ?? initial;

      final bool scheduled = await _notificationService
          .scheduleRecurringNotification(
            id: id,
            title: title,
            body: body,
            repeatInterval: RepeatIntervalEnum.weekly,
            initialScheduleDate: initial,
            channelId: channelId,
            payload: payload,
            actions: actions,
          );

      if (scheduled) {
        _emitEvent(
          NotificationDeliveryEventType.scheduled,
          NotificationDeliveryRequest(
            surface: request.surface,
            lifecycle: request.lifecycle,
            messageId: request.messageId,
            categoryId: request.categoryId,
            scheduledAt: initial,
            data: request.data,
          ),
        );
        _analyticsService.trackEvent('notification_scheduled_weekly', {
          'notification_id': id,
          'title': title,
          'weekday': weekday,
          'scheduled_start': initial.toIso8601String(),
        });
        _logMessage(
          '[NotificationManager] Weekly notification scheduled: $id (weekday: $weekday)',
        );
      }
      return scheduled;
    } catch (error, stack) {
      _logMessage('[NotificationManager] Schedule weekly error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  /// Shows a grouped notification (Android)
  Future<bool> showGroupedNotification({
    required String title,
    required String body,
    required String groupKey,
    required String groupTitle,
    String? channelId,
    Map<String, dynamic>? payload,
    bool isSummary = false,
    int? notificationId,
  }) async {
    try {
      final int id =
          notificationId ??
          (isSummary
              ? _stableHash('group:$groupKey:summary') & 0x7fffffff
              : DateTime.now().microsecondsSinceEpoch & 0x7fffffff);
      final NotificationDeliveryRequest request = _requestForLocal(
        id: id,
        payload: payload,
      );
      final NotificationDeliveryDecision decision = _evaluate(request);
      if (!decision.isAllowed) return false;

      final bool shown = await _notificationService.showNotification(
        id: id,
        title: title,
        body: body,
        channelId: channelId,
        payload: payload,
        groupKey: groupKey,
        sortKey: isSummary ? 'summary' : 'notification',
        isGroupSummary: isSummary,
        groupAlertSummary: groupTitle,
      );
      if (!shown) {
        _emitEvent(
          NotificationDeliveryEventType.failed,
          request,
          reason: 'Grouped notification presentation failed.',
        );
        return false;
      }
      _groupNotificationIds.putIfAbsent(groupKey, () => <int>{}).add(id);
      await _persistGroupNotificationIds();
      _registerDelivery(request);

      _logMessage(
        '[NotificationManager] Grouped notification shown: $groupKey',
      );
      return true;
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Show grouped notification error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  /// Creates a notification group with multiple notifications
  Future<bool> createNotificationGroup({
    required String groupKey,
    required String groupTitle,
    required List<NotificationData> notifications,
    String? channelId,
  }) async {
    try {
      // Show summary notification first
      var allShown = await showGroupedNotification(
        title: groupTitle,
        body: '${notifications.length} notifications',
        groupKey: groupKey,
        groupTitle: groupTitle,
        channelId: channelId,
        isSummary: true,
      );

      // Show individual notifications
      for (int i = 0; i < notifications.length; i++) {
        final notification = notifications[i];
        allShown =
            await showGroupedNotification(
              title: notification.title ?? 'Notification',
              body: notification.body ?? '',
              groupKey: groupKey,
              groupTitle: groupTitle,
              channelId: channelId,
              payload: notification.payload,
              notificationId:
                  _stableHash(
                    notification.messageId ??
                        notification.payload['id']?.toString() ??
                        '$groupKey:$i',
                  ) &
                  0x7fffffff,
            ) &&
            allShown;
      }

      _logMessage(
        '[NotificationManager] Notification group created: $groupKey',
      );
      return allShown;
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Create notification group error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  /// Dismisses a notification group (Android)
  Future<bool> dismissNotificationGroup(String groupKey) async {
    try {
      await _hydrateGroupNotificationIds();
      final Set<int> ids = _groupNotificationIds.remove(groupKey) ?? <int>{};
      var allCancelled = true;
      for (final int id in ids) {
        allCancelled =
            await _notificationService.cancelNotification(id) && allCancelled;
      }
      await _persistGroupNotificationIds();
      _logMessage(
        '[NotificationManager] Notification group dismissed: $groupKey',
      );
      return allCancelled;
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Dismiss notification group error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  /// Shows a threaded notification (iOS conversation threads)
  Future<bool> showThreadedNotification({
    required String title,
    required String body,
    required String threadIdentifier,
    String? channelId,
    Map<String, dynamic>? payload,
    int? notificationId,
  }) async {
    try {
      final int id =
          notificationId ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final NotificationDeliveryRequest request = _requestForLocal(
        id: id,
        payload: payload,
      );
      final NotificationDeliveryDecision decision = _evaluate(request);
      if (!decision.isAllowed) return false;

      final bool shown = await _notificationService.showNotification(
        id: id,
        title: title,
        body: body,
        channelId: channelId,
        payload: payload,
        threadIdentifier: threadIdentifier,
      );
      if (shown) {
        _registerDelivery(request);
      } else {
        _emitEvent(
          NotificationDeliveryEventType.failed,
          request,
          reason: 'Threaded notification presentation failed.',
        );
      }

      _logMessage(
        '[NotificationManager] Threaded notification shown: $threadIdentifier',
      );
      return shown;
    } catch (error, stack) {
      _logMessage(
        '[NotificationManager] Show threaded notification error: $error',
      );
      _logMessage('[NotificationManager] Stack trace: $stack');
      return false;
    }
  }

  Future<void> _persistInboxEntry(
    RemoteMessage message,
    NotificationLifecycle lifecycle,
  ) async {
    try {
      final Map<String, dynamic> data = BridgingPayloadValidator.normalize(
        message.data,
      );
      if (data['storeInInbox']?.toString() == 'false') return;
      final String id =
          data['id']?.toString() ??
          message.messageId ??
          '${DateTime.now().millisecondsSinceEpoch}';

      if (_persistedInboxIds.contains(id)) {
        return;
      }

      final String? title =
          message.notification?.title ?? data['title'] as String?;
      final String? body =
          message.notification?.body ?? data['body'] as String?;

      if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
        return;
      }

      final NotificationDeliveryRequest request = _requestForMessage(
        message,
        surface: NotificationDeliverySurface.inbox,
        lifecycle: lifecycle,
      );
      final NotificationDeliveryDecision decision = _evaluate(request);
      if (!decision.isAllowed) return;

      final NotificationInboxItem item = NotificationInboxItem(
        id: id,
        title: title ?? '',
        body: body ?? '',
        subtitle: data['subtitle'] as String?,
        timestamp: DateTime.now(),
        isRead: false,
        imageUrl:
            message.notification?.android?.imageUrl ??
            message.notification?.apple?.imageUrl ??
            data['image'] as String?,
        actions: _parseActions(data['actions']),
        category: data['category'] as String?,
        data: data,
      );

      _persistedInboxIds.add(id);
      await _inboxStorage.upsert(item);
      _registerDelivery(request);

      _analyticsService.trackEvent('inbox_item_persisted', <String, dynamic>{
        'id': id,
        'lifecycle': lifecycle.name,
        'has_actions': item.actions.isNotEmpty,
      });
    } catch (error, stack) {
      _logMessage('[NotificationManager] Inbox persist error: $error');
      _logMessage('[NotificationManager] Stack trace: $stack');
    }
  }

  List<NotificationAction> _parseActions(dynamic rawActions) {
    dynamic actions = rawActions;
    if (actions is String) {
      try {
        actions = jsonDecode(actions);
      } catch (_) {
        return const <NotificationAction>[];
      }
    }
    if (actions is! List) {
      return const <NotificationAction>[];
    }

    return actions
        .map((dynamic action) {
          if (action is! Map) {
            return null;
          }
          final Map<String, dynamic> parsed = Map<String, dynamic>.from(action);
          final String? id = parsed['id']?.toString();
          final String? title = parsed['title']?.toString();
          if (id == null || title == null) {
            return null;
          }
          return NotificationAction.fromMap(parsed);
        })
        .whereType<NotificationAction>()
        .toList();
  }

  DateTime _nextWeeklyDate({
    required int weekday,
    required int hour,
    required int minute,
  }) {
    final int normalizedWeekday = weekday.clamp(
      DateTime.monday,
      DateTime.sunday,
    );
    final DateTime now = DateTime.now();
    var initial = DateTime(now.year, now.month, now.day, hour, minute);
    final int daysUntilTarget =
        (normalizedWeekday - initial.weekday + DateTime.daysPerWeek) %
        DateTime.daysPerWeek;
    initial = initial.add(Duration(days: daysUntilTarget));
    if (initial.isBefore(now) || initial.isAtSameMomentAs(now)) {
      initial = initial.add(const Duration(days: DateTime.daysPerWeek));
    }
    return initial;
  }
}
