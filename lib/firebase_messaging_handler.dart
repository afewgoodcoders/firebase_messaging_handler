import 'dart:async';
import 'src/export.dart';
import 'src/core/services/permission_wizard_service.dart';
import 'src/core/managers/notification_manager.dart';
import 'src/core/managers/notification_preferences_controller.dart';
import 'src/core/services/notification_delivery_policy_engine.dart';
import 'src/core/services/notification_preferences_service.dart';
import 'src/core/interfaces/notification_state_store.dart';
import 'src/core/configuration/fcm_configuration.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
export 'src/enums/export.dart';
export 'src/models/export.dart';
export 'src/core/managers/notification_manager.dart';
export 'src/core/managers/in_app_message_manager.dart';
export 'src/core/services/inbox_storage_service.dart';
export 'src/core/interfaces/notification_inbox_storage_interface.dart';
export 'src/core/utils/bridging_payload_validator.dart';
export 'src/in_app/export.dart';
export 'src/inbox/export.dart';
export 'src/preferences/export.dart';
export 'src/core/configuration/export.dart';
export 'src/core/interfaces/notification_preferences_repository.dart';
export 'src/core/interfaces/notification_state_store.dart';
export 'src/core/managers/notification_preferences_controller.dart';
export 'src/core/services/notification_preferences_service.dart';
export 'src/core/services/notification_delivery_policy_engine.dart';

// Platform registration stubs — exported so Flutter's generated
// dart_plugin_registrant.dart can resolve them via the main library import.
export 'firebase_messaging_handler_macos.dart';
export 'firebase_messaging_handler_linux.dart';
export 'firebase_messaging_handler_windows.dart';

@pragma('vm:entry-point')
/// Default background dispatcher entry point that forwards work into the
/// package-managed background handler pipeline.
Future<void> firebaseMessagingHandlerBackgroundDispatcher(
  RemoteMessage message,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  await FirebaseMessagingHandler.handleBackgroundMessage(message);
}

/// A comprehensive Firebase Cloud Messaging handler for Flutter applications.
///
/// This class provides a one-stop solution for all FCM operations including:
/// - Notification handling (foreground, background, terminated)
/// - Token management and topic subscriptions
/// - Notification scheduling and actions
/// - Badge management and analytics
/// - Cross-platform support (Android, iOS, Web)
///
/// The handler uses a modular architecture with clear separation of concerns
/// for better maintainability, testability, and extensibility.
class FirebaseMessagingHandler {
  // Singleton instance
  /// Shared singleton used by host apps.
  static final FirebaseMessagingHandler instance =
      FirebaseMessagingHandler._internal();

  // Private constructor for internal use
  FirebaseMessagingHandler._internal();

  // Core manager for notification operations
  final NotificationManager _notificationManager = NotificationManager.instance;
  final StreamController<NotificationDeliveryEvent> _deliveryEventController =
      StreamController<NotificationDeliveryEvent>.broadcast();
  NotificationPreferencesController? _preferencesController;
  NotificationDeliveryPolicyEngine? _deliveryPolicyEngine;

  static bool _testModeEnabled = false;
  static StreamController<RemoteMessage>? _mockRemoteMessageController;
  static StreamController<NotificationData>? _mockClickController;

  /// Initializes the Firebase Cloud Messaging handler with necessary configurations.
  ///
  /// This method sets up all FCM services including:
  /// - Firebase Messaging initialization
  /// - Local notification service setup
  /// - Permission requests
  /// - Token management
  /// - Notification listeners
  ///
  /// Returns a stream of notification click events that can be listened to
  /// for handling user interactions with notifications.
  Future<Stream<NotificationData?>?> init({
    required final String senderId,
    required final List<NotificationChannelData> androidChannelList,
    required final String androidNotificationIconPath,
    final String? webVapidKey,
    final Future<bool> Function(String fcmToken)? updateTokenCallback,
    final bool includeInitialNotificationInStream = true,
  }) async {
    return initialize(
      FCMConfiguration(
        senderId: senderId,
        androidChannels: androidChannelList,
        androidNotificationIconPath: androidNotificationIconPath,
        updateTokenCallback: updateTokenCallback,
        includeInitialNotificationInStream: includeInitialNotificationInStream,
        webVapidKey: webVapidKey,
        requestPermissionOnInitialize: true,
        synchronizeTokenOnInitialize: true,
      ),
    );
  }

  /// Initializes every package subsystem from one immutable configuration.
  ///
  /// Android apps may omit channels to use the built-in high-importance
  /// `default_channel`. The default icon is `@mipmap/ic_launcher`.
  Future<Stream<NotificationData?>?> initialize(
    FCMConfiguration configuration,
  ) async {
    if (!configuration.isValid) {
      throw ArgumentError.value(
        configuration,
        'configuration',
        configuration.validationErrors.join('; '),
      );
    }

    final NotificationPreferencesController preferencesController =
        NotificationPreferencesController(
          repository:
              configuration.preferencesRepository ??
              SharedPreferencesNotificationPreferencesRepository(),
          categories: configuration.notificationCategories,
          openSystemSettings: _notificationManager.openNotificationSettings,
        );
    await preferencesController.load();
    _preferencesController = preferencesController;

    final NotificationDeliveryPolicyEngine deliveryPolicyEngine =
        NotificationDeliveryPolicyEngine(
          preferencesController: preferencesController,
          policy: configuration.deliveryPolicy,
          stateStore:
              configuration.stateStore ??
              SharedPreferencesNotificationStateStore(),
        );
    await deliveryPolicyEngine.restore();
    _deliveryPolicyEngine = deliveryPolicyEngine;
    _notificationManager.configureDeliveryControls(
      deliveryPolicyEngine,
      _deliveryEventController.add,
    );
    if (configuration.analyticsCallback != null) {
      _notificationManager.setAnalyticsCallback(
        configuration.analyticsCallback!,
      );
    }

    return _notificationManager.initialize(configuration);
  }

  /// Live preferences used by the delivery engine and preference-center UI.
  ///
  /// Call [initialize] before reading this value.
  NotificationPreferencesController get notificationPreferences {
    final NotificationPreferencesController? controller =
        _preferencesController;
    if (controller == null) {
      throw StateError('Call initialize() before reading preferences.');
    }
    return controller;
  }

  /// Typed events for receipt, delivery, suppression, interaction, and errors.
  Stream<NotificationDeliveryEvent> get deliveryEvents =>
      _deliveryEventController.stream;

  /// Opens this app's notification settings when supported by the platform.
  Future<bool> openNotificationSettings() =>
      _notificationManager.openNotificationSettings();

  /// Returns a truthful runtime capability matrix for the current platform.
  Future<NotificationCapabilities> getCapabilities() {
    return _notificationManager.getCapabilities();
  }

  /// Requests Android exact-alarm access for exact scheduled notifications.
  Future<bool> requestExactAlarmPermission() {
    return _notificationManager.requestExactAlarmPermission();
  }

  /// Gets the initial notification data if the app was launched from a notification.
  ///
  /// This is useful when you want to handle initial notifications separately from the stream.
  /// Returns null if the app was not launched from a notification.
  static Future<NotificationData?> checkInitial() async {
    // Try immediately first
    var result = await NotificationManager.getInitialNotificationDataStatic();
    if (result != null) {
      return result;
    }

    // If not found immediately, wait a bit and try again (iOS timing issue)
    await Future.delayed(const Duration(milliseconds: 500));

    result = await NotificationManager.getInitialNotificationDataStatic();
    return result;
  }

  /// Disposes of the notification handler resources.
  ///
  /// This method should be called when the app is being disposed to clean up
  /// resources and prevent memory leaks.
  Future<void> dispose() async {
    await _deliveryPolicyEngine?.flush();
    await _notificationManager.dispose();
  }

  /// Removes the stored FCM token.
  ///
  /// This deletes the current Firebase registration token and its local cache.
  Future<void> clearToken() async {
    await _notificationManager.clearToken();
  }

  /// Requests notification permission using explicit, fine-grained options.
  ///
  /// Call this from a user gesture on web. Provisional Apple authorization is
  /// returned as a successful, usable permission state.
  Future<NotificationSettings> requestNotificationPermission({
    NotificationPermissionOptions options =
        const NotificationPermissionOptions(),
  }) {
    return _notificationManager.requestNotificationPermission(options);
  }

  /// Fetches the current FCM token and invokes the configured synchronization
  /// callback. Set [force] to re-upload an unchanged token.
  Future<bool> synchronizeToken({bool force = true}) {
    return _notificationManager.synchronizeToken(force: force);
  }

  /// Subscribes the device to the specified FCM topic.
  ///
  /// Topics allow you to send messages to multiple devices that have opted in
  /// to a particular topic. Use topics for user segments or interest-based messaging.
  Future<void> subscribeToTopic(String topic) async {
    await _notificationManager.subscribeToTopic(topic);
  }

  /// Unsubscribes the device from the specified FCM topic.
  ///
  /// This will stop the device from receiving messages sent to the specified topic.
  Future<void> unsubscribeFromTopic(String topic) async {
    await _notificationManager.unsubscribeFromTopic(topic);
  }

  /// Unsubscribes the device from every topic tracked by this package.
  ///
  /// Direct token-targeted push remains enabled. Call [clearToken] separately
  /// when signing out or intentionally rotating the installation token.
  Future<void> unsubscribeFromAllTopics() async {
    await _notificationManager.unsubscribeFromAllTopics();
  }

  /// Returns topics successfully subscribed through this package.
  Future<List<String>> getSubscribedTopics() {
    return _notificationManager.getSubscribedTopics();
  }

  /// Sets the badge count for iOS notifications.
  ///
  /// The badge count appears on the app icon and indicates the number of
  /// unread notifications or items requiring attention.
  Future<void> setIOSBadgeCount(int count) async {
    await _notificationManager.setIOSBadgeCount(count);
  }

  /// Gets the current badge count for iOS notifications.
  ///
  /// Returns the current badge count displayed on the app icon.
  Future<int?> getIOSBadgeCount() async {
    return await _notificationManager.getIOSBadgeCount();
  }

  /// Sets the badge count for Android notifications.
  ///
  /// Retained for source compatibility. The package does not currently expose
  /// a reliable Android launcher-badge mutation bridge, so query
  /// [getCapabilities] before offering this control.
  Future<void> setAndroidBadgeCount(int count) async {
    await _notificationManager.setAndroidBadgeCount(count);
  }

  /// Gets the current badge count for Android notifications.
  ///
  /// Returns null unless the current Android runtime reports direct badge
  /// mutation support.
  Future<int?> getAndroidBadgeCount() async {
    return await _notificationManager.getAndroidBadgeCount();
  }

  /// Clears the badge count when the current platform supports direct badge
  /// mutation.
  ///
  /// Currently this is implemented by the package's iOS native bridge.
  Future<void> clearBadgeCount() async {
    await _notificationManager.clearBadgeCount();
  }

  /// Creates an Android notification channel configured with a custom sound.
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
    await _notificationManager.createCustomSoundChannel(
      channelId: channelId,
      channelName: channelName,
      channelDescription: channelDescription,
      soundFileName: soundFileName,
      importance: importance,
      priority: priority,
      enableVibration: enableVibration,
      enableLights: enableLights,
    );
  }

  /// Returns the system sound identifiers available on iOS, when supported.
  Future<List<String>?> getAvailableSounds() async {
    return await _notificationManager.getAvailableSounds();
  }

  // ========== TESTING UTILITIES ==========
  //
  // These members are intended for use in host-app tests only.
  // They are NOT part of the production API and have no effect unless
  // [setTestMode] is called first.

  /// Enables or disables test mode.
  ///
  /// When enabled, a set of in-memory mock streams replace the real Firebase
  /// infrastructure so widget and integration tests can drive notification
  /// flows without a Firebase project or physical device.
  ///
  /// Call `setTestMode(false)` in `tearDown` to clean up stream controllers.
  @visibleForTesting
  static void setTestMode(bool enabled) {
    if (_testModeEnabled == enabled) {
      return;
    }

    _testModeEnabled = enabled;

    if (enabled) {
      _mockRemoteMessageController =
          StreamController<RemoteMessage>.broadcast();
      _mockClickController = StreamController<NotificationData>.broadcast();
    } else {
      unawaited(_mockRemoteMessageController?.close());
      unawaited(_mockClickController?.close());
      _mockRemoteMessageController = null;
      _mockClickController = null;
    }
  }

  /// Returns the raw [RemoteMessage] stream backed by an in-memory controller.
  /// Only non-null when [setTestMode] has been called with `true`.
  @visibleForTesting
  static Stream<RemoteMessage>? getMockNotificationStream() {
    return _mockRemoteMessageController?.stream;
  }

  /// Injects [message] into the mock pipeline and triggers the unified handler.
  ///
  /// Requires [setTestMode] to have been called first.
  @visibleForTesting
  static void addMockNotification(RemoteMessage message) {
    if (!_testModeEnabled) {
      throw StateError(
        'Test mode is not enabled. Call setTestMode(true) before adding mock notifications.',
      );
    }

    _mockRemoteMessageController?.add(message);
    unawaited(
      FirebaseMessagingHandler.instance._notificationManager
          .processNotification(message),
    );
  }

  /// Returns the click-event stream backed by an in-memory controller.
  /// Only non-null when [setTestMode] has been called with `true`.
  @visibleForTesting
  static Stream<NotificationData>? getMockClickStream() {
    return _mockClickController?.stream;
  }

  /// Emits [data] on the mock click stream and routes it through the
  /// notification manager's test sink.
  ///
  /// Use this to simulate the user tapping a notification in tests.
  @visibleForTesting
  static void addMockClickEvent(NotificationData data) {
    if (!_testModeEnabled) {
      throw StateError(
        'Test mode is not enabled. Call setTestMode(true) before adding mock click events.',
      );
    }
    _mockClickController?.add(data);
    FirebaseMessagingHandler.instance._notificationManager.emitTestClick(data);
  }

  /// Closes and replaces the mock stream controllers, giving each test a clean
  /// slate. Call this in `setUp` or `tearDown` to prevent event bleed-through.
  @visibleForTesting
  static void resetMockData() {
    if (!_testModeEnabled) {
      return;
    }

    unawaited(_mockRemoteMessageController?.close());
    unawaited(_mockClickController?.close());

    _mockRemoteMessageController = StreamController<RemoteMessage>.broadcast();
    _mockClickController = StreamController<NotificationData>.broadcast();
  }

  /// Constructs a [RemoteMessage] with the given fields, filling in sensible
  /// defaults for any omitted values. Useful for building synthetic payloads
  /// in tests and example apps without a real Firebase project.
  static RemoteMessage createMockRemoteMessage({
    String? messageId,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    String? category,
    String? collapseKey,
    String? senderId,
    int? ttl,
  }) {
    final Map<String, dynamic> map = {
      'messageId':
          messageId ?? 'mock_message_${DateTime.now().millisecondsSinceEpoch}',
      'data': data ?? <String, dynamic>{},
      'sentTime': DateTime.now().millisecondsSinceEpoch,
      'category': category,
      'collapseKey': collapseKey,
      'senderId': senderId,
      'ttl': ttl,
      'notification': {'title': title, 'body': body},
    };

    map.removeWhere((_, value) => value == null);
    final Map<String, dynamic> notification =
        map['notification'] as Map<String, dynamic>;
    notification.removeWhere((_, value) => value == null);

    if (notification.isEmpty) {
      map.remove('notification');
    }

    return RemoteMessage.fromMap(map);
  }

  /// Constructs a [NotificationData] object suitable for use in tests and
  /// example apps. Mirrors the shape of real click events emitted by the handler.
  static NotificationData createMockNotificationData({
    Map<String, dynamic>? payload,
    String? title,
    String? body,
    String? imageUrl,
    NotificationTypeEnum type = NotificationTypeEnum.foreground,
    bool isFromTerminated = false,
    String? messageId,
    String? category,
    List<NotificationAction>? actions,
  }) {
    return NotificationData(
      payload: payload ?? <String, dynamic>{},
      title: title,
      body: body,
      imageUrl: imageUrl,
      type: type,
      isFromTerminated: isFromTerminated,
      messageId: messageId,
      category: category,
      actions: actions,
      timestamp: DateTime.now(),
    );
  }

  /// Shows a local notification with interactive actions.
  ///
  /// This method displays a notification with action buttons that users can tap.
  /// Actions allow users to interact with notifications without opening the app.
  Future<bool> showNotificationWithActions({
    required String title,
    required String body,
    required List<NotificationAction> actions,
    Map<String, dynamic>? payload,
    String? channelId,
    int? notificationId,
    String? actionCategoryId,
  }) async {
    return _notificationManager.showNotificationWithActions(
      title: title,
      body: body,
      actions: actions,
      payload: payload,
      channelId: channelId,
      notificationId: notificationId,
      actionCategoryId: actionCategoryId,
    );
  }

  /// Presents a local notification with complete Android and Apple detail
  /// overrides and returns a typed success or failure result.
  Future<NotificationOperationResult<int>> showLocalNotification(
    LocalNotificationRequest notification,
  ) {
    return _notificationManager.showLocalNotification(notification);
  }

  /// Schedules a notification to be shown at a specific time.
  ///
  /// This method allows you to schedule a local notification to be displayed
  /// at a future date and time. The notification will be shown even if the
  /// app is not running.
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
    return await _notificationManager.scheduleNotification(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      channelId: channelId,
      payload: payload,
      actions: actions,
      allowWhileIdle: allowWhileIdle,
      scheduleMode: scheduleMode,
      fallbackToInexact: fallbackToInexact,
    );
  }

  /// Schedules a recurring notification (daily, weekly, etc.) - Simplified
  Future<bool> scheduleRecurringNotification({
    required int id,
    required String title,
    required String body,
    required String repeatInterval, // 'daily', 'weekly', etc.
    required int hour,
    required int minute,
    String? channelId,
    Map<String, dynamic>? payload,
    List<NotificationAction>? actions,
  }) async {
    try {
      // Convert string to enum
      RepeatIntervalEnum interval;
      switch (repeatInterval.toLowerCase()) {
        case 'daily':
          interval = RepeatIntervalEnum.daily;
          break;
        case 'weekly':
          interval = RepeatIntervalEnum.weekly;
          break;
        case 'monthly':
          interval = RepeatIntervalEnum.monthly;
          break;
        case 'yearly':
          interval = RepeatIntervalEnum.yearly;
          break;
        case 'hourly':
          interval = RepeatIntervalEnum.hourly;
          break;
        case 'minutely':
          interval = RepeatIntervalEnum.minutely;
          break;
        default:
          interval = RepeatIntervalEnum.daily;
      }

      return await _notificationManager.scheduleRecurringNotification(
        id: id,
        title: title,
        body: body,
        repeatInterval: interval,
        hour: hour,
        minute: minute,
        channelId: channelId,
        payload: payload,
        actions: actions,
      );
    } catch (e) {
      return false;
    }
  }

  /// Schedules a weekly notification on a specific weekday.
  ///
  /// [weekday] uses Dart's [DateTime] weekday constants:
  /// `DateTime.monday` through `DateTime.sunday`.
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
      return await _notificationManager.scheduleWeeklyNotification(
        id: id,
        title: title,
        body: body,
        weekday: weekday,
        hour: hour,
        minute: minute,
        channelId: channelId,
        payload: payload,
        actions: actions,
      );
    } catch (e) {
      return false;
    }
  }

  /// Cancels a scheduled notification.
  ///
  /// This method cancels a previously scheduled notification by its ID.
  /// If the notification has already been shown, this method has no effect.
  Future<bool> cancelScheduledNotification(int id) async {
    return await _notificationManager.cancelScheduledNotification(id);
  }

  /// Cancels all scheduled notifications.
  ///
  /// This method cancels all pending scheduled notifications.
  /// Use this method to clear all scheduled notifications at once.
  Future<bool> cancelAllScheduledNotifications() async {
    return await _notificationManager.cancelAllScheduledNotifications();
  }

  /// Gets all pending scheduled notifications.
  ///
  /// Returns a list of all notifications that are scheduled to be shown
  /// in the future. This is primarily supported on Android.
  Future<List<PendingNotificationSnapshot>> getPendingNotifications() async {
    return await _notificationManager.getPendingNotifications();
  }

  /// Gets notifications currently visible in the system notification UI.
  Future<List<ActiveNotificationSnapshot>> getActiveNotifications() {
    return _notificationManager.getActiveNotifications();
  }

  /// Returns whether the current platform reports notifications as enabled.
  ///
  /// A null result means that the platform has no equivalent runtime API.
  Future<bool?> areNotificationsEnabled() {
    return _notificationManager.areNotificationsEnabled();
  }

  /// Deletes an Android notification channel created by this application.
  Future<bool> deleteNotificationChannel(String channelId) {
    return _notificationManager.deleteNotificationChannel(channelId);
  }

  /// Refreshes the device timezone used by scheduled local notifications.
  ///
  /// Call this on app resume before rescheduling reminders if users may travel
  /// or change their system timezone while the app is backgrounded.
  Future<String?> refreshLocalTimezone() async {
    return await _notificationManager.refreshLocalTimezone();
  }

  /// Returns the timezone currently configured for scheduled notifications.
  Future<String?> getConfiguredLocalTimezone() async {
    return await _notificationManager.getConfiguredLocalTimezone();
  }

  /// Shows a grouped notification (Android notification groups)
  Future<bool> showGroupedNotification({
    required String title,
    required String body,
    required String groupKey,
    String? groupTitle,
    String? channelId,
    Map<String, dynamic>? payload,
    bool isSummary = false,
    int? notificationId,
  }) async {
    return _notificationManager.showGroupedNotification(
      title: title,
      body: body,
      groupKey: groupKey,
      groupTitle: groupTitle ?? 'Group',
      channelId: channelId,
      payload: payload,
      isSummary: isSummary,
      notificationId: notificationId,
    );
  }

  /// Creates a notification group with multiple notifications
  Future<bool> createNotificationGroup({
    required String groupKey,
    required String groupTitle,
    required List<NotificationData> notifications,
    String? channelId,
  }) async {
    return _notificationManager.createNotificationGroup(
      groupKey: groupKey,
      groupTitle: groupTitle,
      notifications: notifications,
      channelId: channelId,
    );
  }

  /// Dismisses a notification group (Android)
  Future<bool> dismissNotificationGroup(String groupKey) {
    return _notificationManager.dismissNotificationGroup(groupKey);
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
    return _notificationManager.showThreadedNotification(
      title: title,
      body: body,
      threadIdentifier: threadIdentifier,
      channelId: channelId,
      payload: payload,
      notificationId: notificationId,
    );
  }

  /// Gets the current FCM token.
  ///
  /// The FCM token is a unique identifier for the app instance on a device.
  /// This token is used by your server to send messages to this specific
  /// app instance.
  Future<String?> getFcmToken() async {
    return await _notificationManager.getFcmToken();
  }

  /// If the last FCM token fetch failed, returns a human-readable explanation
  /// of why (e.g. APNs not configured, running on simulator).
  /// Returns null when a token was successfully retrieved.
  String? get lastTokenError => _notificationManager.lastTokenError;

  /// Sets the analytics callback function to track notification events.
  ///
  /// This callback will be invoked whenever a notification event occurs,
  /// allowing you to integrate with your analytics service of choice.
  void setAnalyticsCallback(
    void Function(String event, Map<String, dynamic> data) callback,
  ) {
    _notificationManager.setAnalyticsCallback(callback);
  }

  /// Manually tracks an analytics event.
  ///
  /// Use this method to track custom events related to notifications
  /// or FCM operations.
  void trackAnalyticsEvent(String event, Map<String, dynamic> data) {
    _notificationManager.trackAnalyticsEvent(event, data);
  }

  /// Overrides default foreground notification presentation behavior.
  ///
  /// Use this to inject rich styles (images, large icons, attachments) or
  /// disable the automatic fallback notification entirely.
  void setForegroundNotificationOptions(ForegroundNotificationOptions options) {
    _notificationManager.setForegroundNotificationOptions(options);
  }

  /// Registers in-app notification templates that can be invoked by silent pushes.
  void registerInAppNotificationTemplates(
    Map<String, InAppNotificationTemplate> templates,
  ) {
    _notificationManager.registerInAppTemplates(templates);
  }

  /// Clears all registered in-app templates.
  void clearInAppNotificationTemplates() {
    _notificationManager.clearInAppTemplates();
  }

  /// Sets a fallback handler for in-app payloads that reference unknown templates.
  void setInAppFallbackDisplayHandler(
    InAppNotificationDisplayCallback? fallbackHandler,
  ) {
    _notificationManager.setInAppFallbackDisplayHandler(fallbackHandler);
  }

  /// Exposes stream of in-app notification payloads ready to be rendered.
  Stream<InAppNotificationData> getInAppNotificationStream({
    bool includePendingStorageItems = true,
  }) {
    return _notificationManager.getInAppMessageStream(
      includePendingStorageItems: includePendingStorageItems,
    );
  }

  /// Flushes any stored in-app notifications (e.g. delivered while app was backgrounded).
  Future<void> flushPendingInAppNotifications() async {
    await _notificationManager.flushPendingInAppMessages();
  }

  /// Clears stored in-app notifications. Optionally target a single message by ID.
  Future<void> clearPendingInAppNotifications({String? id}) async {
    await _notificationManager.clearPendingInAppMessages(id: id);
  }

  /// Configures the navigator key used for advanced in-app template presentation.
  void setInAppNavigatorKey(GlobalKey<NavigatorState> navigatorKey) {
    _notificationManager.setInAppNavigatorKey(navigatorKey);
  }

  /// Applies delivery throttling, quiet hours, and frequency caps for in-app templates.
  Future<void> setInAppDeliveryPolicy(InAppDeliveryPolicy policy) async {
    await _notificationManager.setInAppDeliveryPolicy(policy);
  }

  /// Registers a unified handler for all notification lifecycles (foreground, background, terminated).
  /// Returns `true` from the handler when fully handled; return `false` to allow default pipeline or queue.
  Future<void> setUnifiedMessageHandler(
    Future<bool> Function(
      NormalizedMessage message,
      NotificationLifecycle lifecycle,
    )?
    handler,
  ) async {
    await _notificationManager.setUnifiedMessageHandler(handler);
  }

  /// Registers a background message handler. The handler must be a top-level or
  /// static function as required by Firebase Messaging.
  Future<void> configureBackgroundMessageHandler(
    Future<void> Function(RemoteMessage message) handler,
  ) async {
    await _notificationManager.setBackgroundMessageHandler(handler);
  }

  /// Handles a background message using the plugin's internal pipeline. This can
  /// be invoked from your top-level handler before executing custom logic.
  static Future<void> handleBackgroundMessage(
    RemoteMessage message, {
    Future<void> Function()? bootstrap,
  }) async {
    await bootstrap?.call();
    await NotificationManager.instance.handleBackgroundMessage(
      message,
      skipConfiguredBootstrap: bootstrap != null,
    );
  }

  /// Registers a background processing callback that runs after the handler
  /// hydrates internal queues. Return `true` to mark the message handled, or
  /// `false` to enqueue it for retry when the app resumes.
  Future<void> configureBackgroundProcessingCallback(
    Future<bool> Function(RemoteMessage message)? callback,
  ) async {
    await _notificationManager.setBackgroundProcessingCallback(callback);
  }

  /// Sets a custom bridge for data-only messages (no notification payload).
  void setDataOnlyMessageBridge(
    Future<void> Function(RemoteMessage message)? bridge,
  ) {
    _notificationManager.setDataOnlyMessageBridge(bridge);
  }

  /// Enables the built-in bridge that promotes data-only messages to local
  /// notifications so users still see a banner.
  void enableDefaultDataOnlyBridge({
    String? channelId,
    String titleKey = 'title',
    String bodyKey = 'body',
  }) {
    _notificationManager.enableDefaultDataOnlyBridge(
      channelId: channelId,
      titleKey: titleKey,
      bodyKey: bodyKey,
    );
  }

  /// Generates a diagnostic snapshot summarizing permission status, token
  /// availability, badge support, and other platform readiness checks.
  Future<NotificationDiagnosticsResult> runDiagnostics() async {
    return await _notificationManager.runDiagnostics();
  }

  /// Guides users through notification permissions. On Android 13+ this requests
  /// POST_NOTIFICATIONS; on iOS it requests alert/badge/sound. For exact alarms
  /// and other platform quirks, see the returned notes.
  Future<PermissionWizardResult> requestPermissionsWizard() async {
    return await const PermissionWizardService().requestPermissions();
  }
}
