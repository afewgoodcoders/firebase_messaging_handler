import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../../enums/export.dart';
import '../../models/export.dart';
import '../services/fcm_service.dart';
import '../services/notification_dedupe_store.dart';
import '../services/notification_delivery_policy_engine.dart';
import '../services/inbox_storage_service.dart';
import '../services/storage_service.dart';
import '../services/fmh_analytics_service.dart';
import '../interfaces/notification_inbox_storage_interface.dart';
import '../interfaces/notification_state_store.dart';
import 'in_app_message_manager.dart';
import '../utils/bridging_payload_validator.dart';
import '../utils/platform_utils.dart';
import '../utils/web_interop.dart' as web_interop;
import '../configuration/fcm_configuration.dart';

typedef BackgroundMessageCallback =
    Future<bool> Function(RemoteMessage message);
typedef DataOnlyMessageBridge = Future<void> Function(RemoteMessage message);
typedef UnifiedMessageHandler =
    Future<bool> Function(
      NormalizedMessage message,
      NotificationLifecycle lifecycle,
    );

/// Web/WASM-safe notification manager.
///
/// Browser notifications, actions, inbox storage, and in-app messages are
/// supported. Native detail overrides, local scheduling, app-icon badges, and
/// notification-channel APIs report unsupported because
/// `flutter_local_notifications` is not WASM-compatible.
class NotificationManager {
  static NotificationManager? _instance;

  /// Singleton instance.
  static NotificationManager get instance {
    _instance ??= NotificationManager._internal();
    return _instance!;
  }

  NotificationManager._internal();

  final FCMService _fcmService = FCMService.instance;
  final InAppMessageManager _inAppMessageManager = InAppMessageManager.instance;
  StreamController<NotificationData?>? _clickStreamController;
  NotificationInboxStorageInterface _inboxStorage = InboxStorageService();

  UnifiedMessageHandler? _unifiedMessageHandler;
  Future<bool> Function(RemoteMessage message)? _backgroundCallback;
  DataOnlyMessageBridge? _dataOnlyMessageBridge;
  void Function(String event, Map<String, dynamic> data)? _analyticsCallback;
  NotificationDeliveryPolicyEngine? _deliveryPolicyEngine;
  void Function(NotificationDeliveryEvent event)? _deliveryEventSink;
  String? _configuredTimezone;
  FCMConfiguration _configuration = const FCMConfiguration();
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  final Set<String> _subscribedTopics = <String>{};
  NotificationStateStore _stateStore =
      SharedPreferencesNotificationStateStore();
  late NotificationDedupeStore _dedupeStore = NotificationDedupeStore(
    stateStore: _stateStore,
  );

  /// The reason the last FCM token fetch failed, or null after success.
  String? get lastTokenError => _fcmService.lastTokenError;

  Future<Stream<NotificationData?>?> initialize(
    FCMConfiguration configuration,
  ) async {
    _ensureControllers();
    _configuration = configuration;
    _stateStore =
        configuration.stateStore ?? SharedPreferencesNotificationStateStore();
    _dedupeStore = NotificationDedupeStore(stateStore: _stateStore);
    _inboxStorage = InboxStorageService(
      maxItems: configuration.maxStoredNotifications,
    );
    StorageService.instance.configure(
      saveNotifications: configuration.saveNotificationsToStorage,
      maxStoredNotifications: configuration.maxStoredNotifications,
      enableDebugLogging: configuration.enableDebugLogging,
    );
    FmhAnalyticsService.instance.configure(
      configuration.analyticsOptions,
      enableDebugLogging: configuration.enableDebugLogging,
    );
    _inAppMessageManager.setDebugLogging(configuration.enableDebugLogging);
    await _restoreTopics();
    _fcmService.setDebugLogging(configuration.enableDebugLogging);
    await _fcmService.initialize();
    if (configuration.requestPermissionOnInitialize) {
      await _fcmService.requestPermissions(
        options: configuration.permissionOptions,
      );
    }
    if (configuration.synchronizeTokenOnInitialize) {
      await synchronizeToken(force: configuration.resynchronizeUnchangedToken);
    }
    await _foregroundMessageSubscription?.cancel();
    await _openedMessageSubscription?.cancel();
    if (configuration.enableForegroundMessageHandling) {
      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
        processNotification,
      );
    }
    if (configuration.enableBackgroundMessageHandling) {
      _openedMessageSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _emitMessageClick,
      );
    }
    if (configuration.updateTokenCallback != null) {
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = _fcmService.onTokenRefresh.listen(
        (String token) => unawaited(_handleTokenRefresh(token)),
      );
    } else {
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
    }
    if (configuration.includeInitialNotificationInStream) {
      final initial = await _fcmService.getInitialMessage();
      if (initial != null) {
        _emitMessageClick(initial, isFromTerminated: true);
      }
    }
    web_interop.setWebNotificationEventHandler(_handleServiceWorkerEvent);
    return _clickStreamController!.stream;
  }

  Stream<NotificationData?> getNotificationClickStream() {
    _ensureControllers();
    return _clickStreamController!.stream;
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

  /// Emits a delivery event from another package subsystem.
  void emitDeliveryEvent(NotificationDeliveryEvent event) {
    _deliveryEventSink?.call(event);
  }

  void emitTestClick(NotificationData data) {
    _ensureControllers();
    _clickStreamController!.add(data);
  }

  Future<NotificationData?> getInitialNotificationData() async {
    return getInitialNotificationDataStatic();
  }

  static Future<NotificationData?> getInitialNotificationDataStatic() async {
    final message = await FCMService.instance.getInitialMessage();
    if (message == null) return null;
    return _notificationDataFromMessage(message, isFromTerminated: true);
  }

  Future<void> processNotification(
    RemoteMessage message, {
    NotificationLifecycle lifecycle = NotificationLifecycle.foreground,
  }) async {
    if (await _shouldStopIncoming(message, lifecycle: lifecycle)) return;
    final NotificationDeliveryRequest request = _requestForMessage(
      message,
      lifecycle: lifecycle,
    );
    final NotificationDeliveryDecision decision =
        _deliveryPolicyEngine?.evaluate(request) ??
        NotificationDeliveryDecision.allow;
    _emitEvent(NotificationDeliveryEventType.received, request);
    if (!decision.isAllowed) {
      _emitEvent(
        decision.outcome == NotificationDeliveryOutcome.suppressed
            ? NotificationDeliveryEventType.suppressed
            : NotificationDeliveryEventType.deferred,
        request,
        reason: decision.reason,
        nextEligibleAt: decision.nextEligibleAt,
      );
      return;
    }
    await _persistInboxEntry(message, lifecycle);
    await _inAppMessageManager.handleRemoteMessage(message);
    await _invokeUnifiedHandler(message, lifecycle);
    if (message.notification == null &&
        message.data['command']?.toString() != 'silent' &&
        _dataOnlyMessageBridge != null) {
      await _dataOnlyMessageBridge!(message);
    }
    final String? title =
        message.notification?.title ?? message.data['title']?.toString();
    final String? body =
        message.notification?.body ?? message.data['body']?.toString();
    final bool silent =
        message.data['command']?.toString() ==
        NotificationEnvelopeCommand.silent.name;
    if (!silent &&
        _configuration.enableForegroundMessageHandling &&
        (title?.isNotEmpty == true || body?.isNotEmpty == true)) {
      final bool shown = await web_interop.showWebNotification(
        title: title ?? 'Notification',
        body: body ?? '',
        icon: message.data['icon']?.toString() ?? '/icons/Icon-192.png',
        badge: message.data['badge']?.toString(),
        image:
            message.notification?.web?.image ??
            message.data['image']?.toString(),
        tag: message.data['tag']?.toString() ?? message.messageId,
        renotify: message.data['renotify']?.toString() == 'true',
        requireInteraction:
            message.data['requireInteraction']?.toString() == 'true',
        silent: message.data['silent']?.toString() == 'true',
        data: message.data,
      );
      if (!shown) {
        _emitEvent(
          NotificationDeliveryEventType.failed,
          request,
          reason:
              'Browser notification was not shown. Permission must be granted from a user gesture.',
        );
        return;
      }
    }
    _deliveryPolicyEngine?.registerDelivery(request);
    _emitEvent(NotificationDeliveryEventType.delivered, request);
  }

  Future<bool> showNotificationWithActions({
    required String title,
    required String body,
    required List<NotificationAction> actions,
    Map<String, dynamic>? payload,
    String? channelId,
    int? notificationId,
    String? actionCategoryId,
  }) async {
    final int id =
        notificationId ?? DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    final NotificationDeliveryRequest request = NotificationDeliveryRequest(
      surface: NotificationDeliverySurface.local,
      lifecycle: NotificationLifecycle.foreground,
      messageId: id.toString(),
      categoryId: payload?['category']?.toString(),
      data: payload ?? const <String, dynamic>{},
    );
    final NotificationDeliveryDecision decision =
        _deliveryPolicyEngine?.evaluate(request) ??
        NotificationDeliveryDecision.allow;
    if (!decision.isAllowed) {
      _emitEvent(
        decision.outcome == NotificationDeliveryOutcome.suppressed
            ? NotificationDeliveryEventType.suppressed
            : NotificationDeliveryEventType.deferred,
        request,
        reason: decision.reason,
        nextEligibleAt: decision.nextEligibleAt,
      );
      return false;
    }
    final Map<String, dynamic> data = <String, dynamic>{
      ...?payload,
      'id': id.toString(),
      'title': title,
      'body': body,
      'category': ?actionCategoryId,
    };
    final bool shown = await web_interop.showWebNotification(
      title: title,
      body: body,
      icon: payload?['icon']?.toString() ?? '/icons/Icon-192.png',
      tag: id.toString(),
      data: data,
      actions: actions
          .where((NotificationAction action) => !action.textInput)
          .map(
            (NotificationAction action) => <String, dynamic>{
              'action': action.id,
              'title': action.title,
            },
          )
          .toList(),
    );
    if (!shown) {
      _emitEvent(
        NotificationDeliveryEventType.failed,
        request,
        reason:
            'Browser notification actions require permission and an active service worker.',
      );
      return false;
    }
    _deliveryPolicyEngine?.registerDelivery(request);
    _emitEvent(NotificationDeliveryEventType.delivered, request);
    return true;
  }

  Future<NotificationOperationResult<int>> showLocalNotification(
    LocalNotificationRequest notification,
  ) async {
    return const NotificationOperationResult<int>.failure(
      code: NotificationOperationErrorCode.unsupported,
      message:
          'Native local-notification detail overrides are unavailable on web.',
    );
  }

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
    return false;
  }

  Future<bool> cancelScheduledNotification(int id) async => true;

  Future<bool> cancelAllScheduledNotifications() async => true;

  Future<List<PendingNotificationSnapshot>> getPendingNotifications() async =>
      const <PendingNotificationSnapshot>[];

  Future<List<ActiveNotificationSnapshot>> getActiveNotifications() async =>
      const <ActiveNotificationSnapshot>[];

  Future<bool?> areNotificationsEnabled() async =>
      web_interop.getWebNotificationPermission() == 'granted';

  Future<bool> deleteNotificationChannel(String channelId) async => false;

  Future<String?> refreshLocalTimezone() async => _configuredTimezone;

  Future<String?> getConfiguredLocalTimezone() async => _configuredTimezone;

  Future<bool> openNotificationSettings() async => false;

  Future<NotificationCapabilities> getCapabilities() async {
    final bool topics = _configuration.enableTopicSubscriptions;
    NotificationCapabilityStatus yes({
      String? reason,
      bool requiresSetup = false,
    }) => NotificationCapabilityStatus(
      supported: true,
      reason: reason,
      requiresSetup: requiresSetup,
    );
    NotificationCapabilityStatus no(String reason) =>
        NotificationCapabilityStatus(supported: false, reason: reason);
    return NotificationCapabilities(
      platform: currentPlatformName,
      statuses: <NotificationCapability, NotificationCapabilityStatus>{
        NotificationCapability.remotePush: yes(requiresSetup: true),
        NotificationCapability.localPresentation: yes(
          reason:
              'Browser notification API and service worker restrictions apply.',
          requiresSetup: true,
        ),
        NotificationCapability.foregroundDelivery: yes(),
        NotificationCapability.backgroundDelivery: yes(requiresSetup: true),
        NotificationCapability.terminatedDelivery: yes(requiresSetup: true),
        NotificationCapability.scheduling: no(
          'Browsers do not provide durable local notification scheduling.',
        ),
        NotificationCapability.recurringScheduling: no(
          'Browsers do not provide recurring local scheduling.',
        ),
        NotificationCapability.exactScheduling: no(
          'Exact alarms are unavailable on web.',
        ),
        NotificationCapability.appIconBadge: no(
          'The Badging API is not uniformly available and is not mutated by this package.',
        ),
        NotificationCapability.topicSubscriptions: topics
            ? yes()
            : no('FCM topic subscriptions are disabled.'),
        NotificationCapability.notificationActions: yes(
          reason: 'Browser and service-worker support varies.',
          requiresSetup: true,
        ),
        NotificationCapability.inlineReply: no(
          'Inline notification replies are unavailable on web.',
        ),
        NotificationCapability.notificationInbox: yes(),
        NotificationCapability.inAppMessaging: yes(),
        NotificationCapability.webServiceWorker: yes(requiresSetup: true),
        NotificationCapability.deliveryMetricsExport: no(
          'Enable Firebase delivery-metrics export in the web service worker.',
        ),
      },
    );
  }

  Future<bool> requestExactAlarmPermission() async => false;

  Future<NotificationSettings> requestNotificationPermission(
    NotificationPermissionOptions options,
  ) {
    return _fcmService.requestPermissionSettings(options: options);
  }

  Future<void> setIOSBadgeCount(int count) async {}

  Future<int?> getIOSBadgeCount() async => null;

  Future<void> setAndroidBadgeCount(int count) async {}

  Future<int?> getAndroidBadgeCount() async => null;

  Future<void> clearBadgeCount() async {}

  Future<void> subscribeToTopic(String topic) async {
    if (!_configuration.enableTopicSubscriptions) {
      throw StateError('Topic subscriptions are disabled by configuration.');
    }
    await _fcmService.subscribeToTopic(topic);
    _subscribedTopics.add(topic);
    await _persistTopics();
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _fcmService.unsubscribeFromTopic(topic);
    _subscribedTopics.remove(topic);
    await _persistTopics();
  }

  Future<void> unsubscribeFromAllTopics() async {
    for (final String topic in _subscribedTopics.toList()) {
      await _fcmService.unsubscribeFromTopic(topic);
    }
    _subscribedTopics.clear();
    await _persistTopics();
  }

  Future<List<String>> getSubscribedTopics() async {
    return _subscribedTopics.toList()..sort();
  }

  Future<String?> getFcmToken() async =>
      _fcmService.getToken(vapidKey: _configuration.webVapidKey);

  Future<void> clearToken() async {
    await _fcmService.deleteToken();
    await _stateStore.remove('fmh_v2_fcm_token');
  }

  Future<bool> synchronizeToken({bool force = false}) async {
    final String? token = await getFcmToken();
    if (token == null) return false;
    final String? stored = (await _stateStore.read(
      'fmh_v2_fcm_token',
    ))?.toString();
    if (!force && stored == token) return true;
    final callback = _configuration.updateTokenCallback;
    final bool accepted = callback == null ? true : await callback(token);
    if (accepted) await _stateStore.write('fmh_v2_fcm_token', token);
    return accepted;
  }

  Future<void> _handleTokenRefresh(String token) async {
    final Future<bool> Function(String token)? callback =
        _configuration.updateTokenCallback;
    if (callback == null || await callback(token)) {
      await _stateStore.write('fmh_v2_fcm_token', token);
    }
  }

  void setAnalyticsCallback(
    void Function(String event, Map<String, dynamic> data) callback,
  ) {
    _analyticsCallback = callback;
    FmhAnalyticsService.instance.setCallback(callback);
  }

  void trackAnalyticsEvent(String event, Map<String, dynamic> data) {
    _analyticsCallback?.call(event, data);
  }

  void setForegroundNotificationOptions(
    ForegroundNotificationOptions options,
  ) {}

  void registerInAppTemplates(
    Map<String, InAppNotificationTemplate> templates,
  ) {
    _inAppMessageManager.registerTemplates(templates);
  }

  void clearInAppTemplates() {
    _inAppMessageManager.clearTemplates();
  }

  void setInAppFallbackDisplayHandler(
    InAppNotificationDisplayCallback? fallbackHandler,
  ) {
    _inAppMessageManager.setFallbackDisplayHandler(fallbackHandler);
  }

  void setInAppNavigatorKey(GlobalKey<NavigatorState> navigatorKey) {
    _inAppMessageManager.setNavigatorKey(navigatorKey);
  }

  Future<void> setInAppDeliveryPolicy(InAppDeliveryPolicy policy) {
    return _inAppMessageManager.setDeliveryPolicy(policy);
  }

  Stream<InAppNotificationData> getInAppMessageStream({
    bool includePendingStorageItems = true,
  }) {
    return _inAppMessageManager.getMessageStream(
      includePendingStorageItems: includePendingStorageItems,
    );
  }

  Future<void> flushPendingInAppMessages() {
    return _inAppMessageManager.flushPendingInAppMessages();
  }

  Future<void> clearPendingInAppMessages({String? id}) {
    return _inAppMessageManager.clearPendingInAppMessages(id: id);
  }

  Future<void> setBackgroundProcessingCallback(
    Future<bool> Function(RemoteMessage message)? callback,
  ) async {
    _backgroundCallback = callback;
  }

  void setDataOnlyMessageBridge(DataOnlyMessageBridge? bridge) {
    _dataOnlyMessageBridge = bridge;
  }

  Future<void> setUnifiedMessageHandler(UnifiedMessageHandler? handler) async {
    _unifiedMessageHandler = handler;
  }

  void enableDefaultDataOnlyBridge({
    String? channelId,
    String titleKey = 'title',
    String bodyKey = 'body',
  }) {
    _dataOnlyMessageBridge = (message) async {
      _emitMessageClick(message);
    };
  }

  Future<void> setBackgroundMessageHandler(
    Future<void> Function(RemoteMessage message) handler,
  ) async {
    FirebaseMessaging.onBackgroundMessage(handler);
  }

  Future<void> handleBackgroundMessage(
    RemoteMessage message, {
    bool skipConfiguredBootstrap = false,
  }) async {
    if (!skipConfiguredBootstrap) {
      await _configuration.backgroundBootstrap?.call();
    }
    await _backgroundCallback?.call(message);
    await processNotification(
      message,
      lifecycle: NotificationLifecycle.background,
    );
  }

  Future<NotificationDiagnosticsResult> runDiagnostics() async {
    final String permission = web_interop.getWebNotificationPermission();
    final Map<String, dynamic> runtime = web_interop.getWebRuntimeDiagnostics();
    final bool tokenAvailable =
        (await _stateStore.read('fmh_v2_fcm_token'))?.toString().isNotEmpty ==
        true;
    final List<String> recommendations = <String>[];
    if (permission != 'granted') {
      recommendations.add(
        'Browser notification permission is "$permission". Request it from a user gesture.',
      );
    }
    if (runtime['serviceWorkerControllerPresent'] != true) {
      recommendations.add(
        'No active service worker controls this page. Install the v2 worker template at the app scope.',
      );
    }
    if (!tokenAvailable) {
      recommendations.add(
        'No synchronized FCM token is stored. Call synchronizeToken() after permission is granted.',
      );
    }
    return NotificationDiagnosticsResult(
      success: true,
      permissionsGranted: permission == 'granted',
      authorizationStatus: permission,
      fcmTokenAvailable: tokenAvailable,
      badgeSupported: false,
      webNotificationsAllowed: permission == 'granted',
      pendingNotificationCount: await _inboxStorage.count(),
      platform: currentPlatformName,
      recommendations: recommendations,
      metadata: <String, dynamic>{
        'lastTokenError': _fcmService.lastTokenError,
        'webDiagnostics': runtime,
        'storedTokenPresent': tokenAvailable,
      },
    );
  }

  Future<void> dispose() async {
    web_interop.setWebNotificationEventHandler(null);
    await _foregroundMessageSubscription?.cancel();
    await _openedMessageSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _clickStreamController?.close();
    await _inAppMessageManager.dispose();
    _clickStreamController = null;
    _foregroundMessageSubscription = null;
    _openedMessageSubscription = null;
    _tokenRefreshSubscription = null;
  }

  Future<void> createCustomSoundChannel({
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String soundFileName,
    NotificationImportanceEnum importance = NotificationImportanceEnum.high,
    NotificationPriorityEnum priority = NotificationPriorityEnum.high,
    bool enableVibration = true,
    bool enableLights = true,
  }) async {}

  Future<List<String>?> getAvailableSounds() async => const [];

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
    return false;
  }

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
    return false;
  }

  Future<bool> showGroupedNotification({
    required String title,
    required String body,
    required String groupKey,
    required String groupTitle,
    String? channelId,
    Map<String, dynamic>? payload,
    bool isSummary = false,
    int? notificationId,
  }) async => false;

  Future<bool> createNotificationGroup({
    required String groupKey,
    required String groupTitle,
    required List<NotificationData> notifications,
    String? channelId,
  }) async => false;

  Future<bool> dismissNotificationGroup(String groupKey) async => false;

  Future<bool> showThreadedNotification({
    required String title,
    required String body,
    required String threadIdentifier,
    String? channelId,
    Map<String, dynamic>? payload,
    int? notificationId,
  }) async => false;

  Future<bool> _invokeUnifiedHandler(
    RemoteMessage message,
    NotificationLifecycle lifecycle,
  ) async {
    final handler = _unifiedMessageHandler;
    if (handler == null) return false;
    return handler(
      _normalizedMessageFromMessage(message, lifecycle),
      lifecycle,
    );
  }

  void _emitMessageClick(
    RemoteMessage message, {
    bool isFromTerminated = false,
  }) {
    final NotificationDeliveryRequest request = _requestForMessage(
      message,
      lifecycle: isFromTerminated
          ? NotificationLifecycle.terminated
          : NotificationLifecycle.resume,
    );
    _emitEvent(NotificationDeliveryEventType.opened, request);
    _ensureControllers();
    _clickStreamController!.add(
      _notificationDataFromMessage(message, isFromTerminated: isFromTerminated),
    );
  }

  void _handleServiceWorkerEvent(Map<String, dynamic> event) {
    final String type = event['type']?.toString() ?? '';
    if (type != 'firebase_messaging_handler_click' &&
        type != 'firebase_messaging_handler_close') {
      return;
    }
    final Map<String, dynamic> data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : <String, dynamic>{};
    final String messageId =
        data['messageId']?.toString() ??
        data['id']?.toString() ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final String? actionId = event['actionId']?.toString();
    final NotificationDeliveryRequest request = NotificationDeliveryRequest(
      surface: NotificationDeliverySurface.push,
      lifecycle: NotificationLifecycle.resume,
      messageId: messageId,
      categoryId: data['category']?.toString(),
      data: data,
    );
    if (type == 'firebase_messaging_handler_close') {
      _emitEvent(NotificationDeliveryEventType.dismissed, request);
      return;
    }
    _deliveryEventSink?.call(
      NotificationDeliveryEvent(
        type: actionId == null || actionId.isEmpty
            ? NotificationDeliveryEventType.opened
            : NotificationDeliveryEventType.actionSelected,
        surface: NotificationDeliverySurface.push,
        messageId: messageId,
        timestamp: DateTime.now(),
        lifecycle: NotificationLifecycle.resume,
        categoryId: data['category']?.toString(),
        actionId: actionId,
        data: data,
      ),
    );
    _ensureControllers();
    _clickStreamController!.add(
      NotificationData(
        payload: data,
        title: data['title']?.toString(),
        body: data['body']?.toString(),
        imageUrl: data['image']?.toString(),
        category: data['category']?.toString(),
        timestamp: DateTime.now(),
        type: NotificationTypeEnum.background,
        messageId: messageId,
        metadata: <String, dynamic>{
          if (actionId != null && actionId.isNotEmpty) 'actionId': actionId,
          'source': 'web_service_worker',
        },
      ),
    );
  }

  void _ensureControllers() {
    _clickStreamController ??= StreamController<NotificationData?>.broadcast();
  }

  Future<void> _restoreTopics() async {
    final Object? raw = await _stateStore.read('fmh_v2_subscribed_topics');
    _subscribedTopics
      ..clear()
      ..addAll(
        raw is List
            ? raw.map((dynamic topic) => topic.toString())
            : const <String>[],
      );
  }

  Future<void> _persistTopics() {
    final List<String> topics = _subscribedTopics.toList()..sort();
    return _stateStore.write('fmh_v2_subscribed_topics', topics);
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
      lifecycle: lifecycle,
    );
    NotificationEnvelope? envelope;
    if (data.containsKey('schemaVersion')) {
      envelope = NotificationEnvelope.fromMap(<String, dynamic>{
        ...data,
        if (data['id'] == null && message.messageId != null)
          'id': message.messageId,
        if (data['title'] == null && message.notification?.title != null)
          'title': message.notification?.title,
        if (data['body'] == null && message.notification?.body != null)
          'body': message.notification?.body,
      });
      final NotificationEnvelopeValidationResult validation = envelope
          .validate();
      if (!validation.isValid) {
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
        envelope?.effectiveIdempotencyKey ??
        message.messageId ??
        data['idempotencyKey']?.toString() ??
        data['dedupeKey']?.toString() ??
        data['id']?.toString() ??
        data.toString();
    if (await _dedupeStore.checkAndRecord(
      'received:$dedupeKey',
      expiresAt: envelope?.expiresAt,
    )) {
      _emitEvent(
        NotificationDeliveryEventType.deduplicated,
        request,
        reason: 'Duplicate notification payload ignored.',
      );
      return true;
    }
    switch (envelope?.command) {
      case NotificationEnvelopeCommand.cancel:
        await _inboxStorage.delete(<String>[envelope!.id]);
        _emitEvent(
          NotificationDeliveryEventType.cancelled,
          request,
          reason:
              'Foreground presentation suppressed. The v2 service worker closes matching background notifications.',
        );
        return true;
      case NotificationEnvelopeCommand.markRead:
        await _inboxStorage.markRead(<String>[envelope!.id]);
        _emitEvent(
          NotificationDeliveryEventType.commandProcessed,
          request,
          reason: 'markRead command received on web.',
        );
        return true;
      case NotificationEnvelopeCommand.silent:
      case NotificationEnvelopeCommand.display:
      case NotificationEnvelopeCommand.replace:
      case null:
        return false;
    }
  }

  NotificationDeliveryRequest _requestForMessage(
    RemoteMessage message, {
    required NotificationLifecycle lifecycle,
  }) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(message.data);
    return NotificationDeliveryRequest(
      surface: NotificationDeliverySurface.push,
      lifecycle: lifecycle,
      messageId:
          message.messageId ??
          data['messageId']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      categoryId: data['category']?.toString() ?? message.category,
      data: data,
    );
  }

  Future<void> _persistInboxEntry(
    RemoteMessage message,
    NotificationLifecycle lifecycle,
  ) async {
    final Map<String, dynamic> data = BridgingPayloadValidator.normalize(
      message.data,
    );
    if (data['storeInInbox']?.toString() == 'false') return;
    final String? title =
        message.notification?.title ?? data['title']?.toString();
    final String? body = message.notification?.body ?? data['body']?.toString();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }
    final String id =
        data['id']?.toString() ??
        message.messageId ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final NotificationDeliveryRequest request = NotificationDeliveryRequest(
      surface: NotificationDeliverySurface.inbox,
      lifecycle: lifecycle,
      messageId: id,
      categoryId: data['category']?.toString(),
      data: data,
    );
    final NotificationDeliveryDecision decision =
        _deliveryPolicyEngine?.evaluate(request) ??
        NotificationDeliveryDecision.allow;
    if (!decision.isAllowed) return;
    await _inboxStorage.upsert(
      NotificationInboxItem(
        id: id,
        title: title ?? '',
        body: body ?? '',
        subtitle: data['subtitle']?.toString(),
        timestamp: message.sentTime ?? DateTime.now(),
        imageUrl: message.notification?.web?.image ?? data['image']?.toString(),
        actions: _parseActions(data['actions']),
        category: data['category']?.toString(),
        data: data,
      ),
    );
    _deliveryPolicyEngine?.registerDelivery(request);
    _emitEvent(NotificationDeliveryEventType.delivered, request);
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
    if (actions is! List) return const <NotificationAction>[];
    return actions
        .whereType<Map>()
        .map(
          (Map<dynamic, dynamic> action) =>
              NotificationAction.fromMap(Map<String, dynamic>.from(action)),
        )
        .where(
          (NotificationAction action) =>
              action.id.isNotEmpty && action.title.isNotEmpty,
        )
        .toList();
  }

  void _emitEvent(
    NotificationDeliveryEventType type,
    NotificationDeliveryRequest request, {
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
        reason: reason,
        nextEligibleAt: nextEligibleAt,
        data: request.data,
      ),
    );
  }

  static NotificationData _notificationDataFromMessage(
    RemoteMessage message, {
    bool isFromTerminated = false,
  }) {
    return NotificationData(
      payload: message.data,
      title: message.notification?.title ?? message.data['title'] as String?,
      body: message.notification?.body ?? message.data['body'] as String?,
      imageUrl:
          message.notification?.web?.image ?? message.data['image'] as String?,
      type: isFromTerminated
          ? NotificationTypeEnum.terminated
          : NotificationTypeEnum.foreground,
      isFromTerminated: isFromTerminated,
      messageId: message.messageId,
      senderId: message.senderId,
      timestamp: DateTime.now(),
    );
  }

  static NormalizedMessage _normalizedMessageFromMessage(
    RemoteMessage message,
    NotificationLifecycle lifecycle,
  ) {
    return NormalizedMessage(
      id:
          message.data['id']?.toString() ??
          message.messageId ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: message.notification?.title ?? message.data['title'] as String?,
      body: message.notification?.body ?? message.data['body'] as String?,
      imageUrl:
          message.notification?.web?.image ?? message.data['image'] as String?,
      data: message.data,
      receivedAt: DateTime.now(),
      lifecycle: lifecycle,
      origin: 'web',
      rawMessage: message,
    );
  }
}
