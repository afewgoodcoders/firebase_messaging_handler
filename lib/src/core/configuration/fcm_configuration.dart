import 'dart:typed_data';
import 'dart:ui';

import '../../models/export.dart';
import '../../enums/export.dart';
import '../interfaces/notification_preferences_repository.dart';
import '../interfaces/notification_state_store.dart';

/// Immutable configuration object describing how the handler should initialize
/// Firebase Messaging, local notifications, analytics, and storage behavior.
class FCMConfiguration {
  /// Sender ID for FCM
  final String senderId;

  /// Optional Web Push VAPID key.
  final String? webVapidKey;

  /// Android notification channels
  final List<NotificationChannelData> androidChannels;

  /// Android notification icon path
  final String androidNotificationIconPath;

  /// Callback for updating FCM token
  final Future<bool> Function(String fcmToken)? updateTokenCallback;

  /// Whether initialization should prompt for notification permission.
  ///
  /// Defaults to false so applications can show their own pre-permission UI
  /// and, on web, request permission from a user gesture.
  final bool requestPermissionOnInitialize;

  /// Fine-grained options used when permission is requested.
  final NotificationPermissionOptions permissionOptions;

  /// Whether initialization should fetch and synchronize the FCM token.
  ///
  /// Defaults to false because web token creation may require a user gesture.
  final bool synchronizeTokenOnInitialize;

  /// Uploads the current token during every requested synchronization, even
  /// when it matches the locally cached token.
  final bool resynchronizeUnchangedToken;

  /// Application bootstrap invoked before background handlers when the
  /// configured manager is retained by the current isolate.
  ///
  /// Android creates a new background isolate and callbacks cannot be
  /// serialized into it. Apps that need custom dependency injection there
  /// must pass the same top-level callback to
  /// `FirebaseMessagingHandler.handleBackgroundMessage(bootstrap: ...)` from
  /// their own top-level Firebase background handler. The package's default
  /// dispatcher always initializes the default Firebase app.
  final Future<void> Function()? backgroundBootstrap;

  /// Whether to include initial notification in stream
  final bool includeInitialNotificationInStream;

  /// Analytics callback
  final void Function(String event, Map<String, dynamic> data)?
  analyticsCallback;

  /// Privacy level applied before analytics data reaches [analyticsCallback].
  final NotificationAnalyticsOptions analyticsOptions;

  /// Whether to enable debug logging
  final bool enableDebugLogging;

  /// Enables Firebase delivery-metrics export to BigQuery on Android.
  ///
  /// Apple and web require their platform-specific Firebase setup in addition
  /// to this client configuration.
  final bool exportDeliveryMetricsToBigQuery;

  /// Whether to save notifications to storage
  final bool saveNotificationsToStorage;

  /// Maximum number of notifications to store
  final int maxStoredNotifications;

  /// Whether to enable background message handling
  final bool enableBackgroundMessageHandling;

  /// Whether to enable foreground message handling
  final bool enableForegroundMessageHandling;

  /// Whether to enable notification scheduling
  final bool enableNotificationScheduling;

  /// Whether to enable badge management
  final bool enableBadgeManagement;

  /// Whether to enable topic subscriptions
  final bool enableTopicSubscriptions;

  /// Enables package-managed local presentation for valid data-only messages.
  final bool enableDefaultDataOnlyBridge;

  /// Optional channel used by the data-only bridge.
  final String? dataOnlyBridgeChannelId;

  /// Data key containing the bridged title.
  final String dataOnlyBridgeTitleKey;

  /// Data key containing the bridged body.
  final String dataOnlyBridgeBodyKey;

  /// Default notification channel ID
  final String? defaultChannelId;

  /// Default notification importance
  final NotificationImportanceEnum defaultImportance;

  /// Default notification priority
  final NotificationPriorityEnum defaultPriority;

  /// Whether to enable sound by default
  final bool enableSoundByDefault;

  /// Whether to enable vibration by default
  final bool enableVibrationByDefault;

  /// Whether to enable lights by default
  final bool enableLightsByDefault;

  /// Whether to show badge by default
  final bool showBadgeByDefault;

  /// User-facing categories managed by the built-in preference center.
  final List<NotificationCategory> notificationCategories;

  /// Shared policy applied to push, local, in-app, and inbox delivery.
  final NotificationDeliveryPolicy deliveryPolicy;

  /// Optional custom persistence implementation for user preferences.
  final NotificationPreferencesRepository? preferencesRepository;

  /// Apple action categories registered during notification initialization.
  final List<NotificationActionCategory> actionCategories;

  /// Windows toast identity. Required for local notifications on Windows.
  final WindowsNotificationOptions? windows;

  /// Optional durable runtime-state store for dedupe and subscription state.
  final NotificationStateStore? stateStore;

  /// Creates a configuration for initializing the handler.
  const FCMConfiguration({
    this.senderId = '',
    this.webVapidKey,
    this.androidChannels = const <NotificationChannelData>[],
    this.androidNotificationIconPath = '@mipmap/ic_launcher',
    this.updateTokenCallback,
    this.requestPermissionOnInitialize = false,
    this.permissionOptions = const NotificationPermissionOptions(),
    this.synchronizeTokenOnInitialize = false,
    this.resynchronizeUnchangedToken = true,
    this.backgroundBootstrap,
    this.includeInitialNotificationInStream = true,
    this.analyticsCallback,
    this.analyticsOptions = const NotificationAnalyticsOptions(),
    this.enableDebugLogging = false,
    this.exportDeliveryMetricsToBigQuery = false,
    this.saveNotificationsToStorage = true,
    this.maxStoredNotifications = 100,
    this.enableBackgroundMessageHandling = true,
    this.enableForegroundMessageHandling = true,
    this.enableNotificationScheduling = true,
    this.enableBadgeManagement = true,
    this.enableTopicSubscriptions = true,
    this.enableDefaultDataOnlyBridge = false,
    this.dataOnlyBridgeChannelId,
    this.dataOnlyBridgeTitleKey = 'title',
    this.dataOnlyBridgeBodyKey = 'body',
    this.defaultChannelId,
    this.defaultImportance = NotificationImportanceEnum.high,
    this.defaultPriority = NotificationPriorityEnum.high,
    this.enableSoundByDefault = true,
    this.enableVibrationByDefault = true,
    this.enableLightsByDefault = false,
    this.showBadgeByDefault = true,
    this.notificationCategories = const <NotificationCategory>[],
    this.deliveryPolicy = const NotificationDeliveryPolicy(),
    this.preferencesRepository,
    this.actionCategories = const <NotificationActionCategory>[],
    this.windows,
    this.stateStore,
  });

  /// Creates a copy of this configuration with selected fields replaced.
  FCMConfiguration copyWith({
    String? senderId,
    String? webVapidKey,
    List<NotificationChannelData>? androidChannels,
    String? androidNotificationIconPath,
    Future<bool> Function(String fcmToken)? updateTokenCallback,
    bool? requestPermissionOnInitialize,
    NotificationPermissionOptions? permissionOptions,
    bool? synchronizeTokenOnInitialize,
    bool? resynchronizeUnchangedToken,
    Future<void> Function()? backgroundBootstrap,
    bool? includeInitialNotificationInStream,
    void Function(String event, Map<String, dynamic> data)? analyticsCallback,
    NotificationAnalyticsOptions? analyticsOptions,
    bool? enableDebugLogging,
    bool? exportDeliveryMetricsToBigQuery,
    bool? saveNotificationsToStorage,
    int? maxStoredNotifications,
    bool? enableBackgroundMessageHandling,
    bool? enableForegroundMessageHandling,
    bool? enableNotificationScheduling,
    bool? enableBadgeManagement,
    bool? enableTopicSubscriptions,
    bool? enableDefaultDataOnlyBridge,
    String? dataOnlyBridgeChannelId,
    String? dataOnlyBridgeTitleKey,
    String? dataOnlyBridgeBodyKey,
    String? defaultChannelId,
    NotificationImportanceEnum? defaultImportance,
    NotificationPriorityEnum? defaultPriority,
    bool? enableSoundByDefault,
    bool? enableVibrationByDefault,
    bool? enableLightsByDefault,
    bool? showBadgeByDefault,
    List<NotificationCategory>? notificationCategories,
    NotificationDeliveryPolicy? deliveryPolicy,
    NotificationPreferencesRepository? preferencesRepository,
    List<NotificationActionCategory>? actionCategories,
    WindowsNotificationOptions? windows,
    NotificationStateStore? stateStore,
  }) {
    return FCMConfiguration(
      senderId: senderId ?? this.senderId,
      webVapidKey: webVapidKey ?? this.webVapidKey,
      androidChannels: androidChannels ?? this.androidChannels,
      androidNotificationIconPath:
          androidNotificationIconPath ?? this.androidNotificationIconPath,
      updateTokenCallback: updateTokenCallback ?? this.updateTokenCallback,
      requestPermissionOnInitialize:
          requestPermissionOnInitialize ?? this.requestPermissionOnInitialize,
      permissionOptions: permissionOptions ?? this.permissionOptions,
      synchronizeTokenOnInitialize:
          synchronizeTokenOnInitialize ?? this.synchronizeTokenOnInitialize,
      resynchronizeUnchangedToken:
          resynchronizeUnchangedToken ?? this.resynchronizeUnchangedToken,
      backgroundBootstrap: backgroundBootstrap ?? this.backgroundBootstrap,
      includeInitialNotificationInStream:
          includeInitialNotificationInStream ??
          this.includeInitialNotificationInStream,
      analyticsCallback: analyticsCallback ?? this.analyticsCallback,
      analyticsOptions: analyticsOptions ?? this.analyticsOptions,
      enableDebugLogging: enableDebugLogging ?? this.enableDebugLogging,
      exportDeliveryMetricsToBigQuery:
          exportDeliveryMetricsToBigQuery ??
          this.exportDeliveryMetricsToBigQuery,
      saveNotificationsToStorage:
          saveNotificationsToStorage ?? this.saveNotificationsToStorage,
      maxStoredNotifications:
          maxStoredNotifications ?? this.maxStoredNotifications,
      enableBackgroundMessageHandling:
          enableBackgroundMessageHandling ??
          this.enableBackgroundMessageHandling,
      enableForegroundMessageHandling:
          enableForegroundMessageHandling ??
          this.enableForegroundMessageHandling,
      enableNotificationScheduling:
          enableNotificationScheduling ?? this.enableNotificationScheduling,
      enableBadgeManagement:
          enableBadgeManagement ?? this.enableBadgeManagement,
      enableTopicSubscriptions:
          enableTopicSubscriptions ?? this.enableTopicSubscriptions,
      enableDefaultDataOnlyBridge:
          enableDefaultDataOnlyBridge ?? this.enableDefaultDataOnlyBridge,
      dataOnlyBridgeChannelId:
          dataOnlyBridgeChannelId ?? this.dataOnlyBridgeChannelId,
      dataOnlyBridgeTitleKey:
          dataOnlyBridgeTitleKey ?? this.dataOnlyBridgeTitleKey,
      dataOnlyBridgeBodyKey:
          dataOnlyBridgeBodyKey ?? this.dataOnlyBridgeBodyKey,
      defaultChannelId: defaultChannelId ?? this.defaultChannelId,
      defaultImportance: defaultImportance ?? this.defaultImportance,
      defaultPriority: defaultPriority ?? this.defaultPriority,
      enableSoundByDefault: enableSoundByDefault ?? this.enableSoundByDefault,
      enableVibrationByDefault:
          enableVibrationByDefault ?? this.enableVibrationByDefault,
      enableLightsByDefault:
          enableLightsByDefault ?? this.enableLightsByDefault,
      showBadgeByDefault: showBadgeByDefault ?? this.showBadgeByDefault,
      notificationCategories:
          notificationCategories ?? this.notificationCategories,
      deliveryPolicy: deliveryPolicy ?? this.deliveryPolicy,
      preferencesRepository:
          preferencesRepository ?? this.preferencesRepository,
      actionCategories: actionCategories ?? this.actionCategories,
      windows: windows ?? this.windows,
      stateStore: stateStore ?? this.stateStore,
    );
  }

  /// Recreates a configuration from a serialized map.
  factory FCMConfiguration.fromMap(Map<String, dynamic> map) {
    return FCMConfiguration(
      senderId: map['senderId'] ?? '',
      webVapidKey: map['webVapidKey'] as String?,
      androidChannels: map['androidChannels'] != null
          ? (map['androidChannels'] as List<dynamic>)
                .map(
                  (channel) => NotificationChannelData(
                    id: channel['id'] ?? '',
                    name: channel['name'] ?? '',
                    description: channel['description'],
                    groupId: channel['groupId'],
                    importance: NotificationImportanceEnum.values.firstWhere(
                      (importance) => importance.name == channel['importance'],
                      orElse: () => NotificationImportanceEnum.high,
                    ),
                    playSound: channel['playSound'] ?? true,
                    soundPath: channel['soundPath'],
                    enableVibration: channel['enableVibration'] ?? true,
                    enableLights: channel['enableLights'] ?? false,
                    vibrationPattern: channel['vibrationPattern'] is List
                        ? Int64List.fromList(
                            (channel['vibrationPattern'] as List<dynamic>)
                                .map((dynamic value) => value as int)
                                .toList(),
                          )
                        : null,
                    ledColor: channel['ledColor'] is int
                        ? Color(channel['ledColor'] as int)
                        : null,
                    showBadge: channel['showBadge'] ?? true,
                    priority: NotificationPriorityEnum.values.firstWhere(
                      (priority) => priority.name == channel['priority'],
                      orElse: () => NotificationPriorityEnum.high,
                    ),
                    actions: (channel['actions'] as List<dynamic>?)
                        ?.whereType<Map>()
                        .map(
                          (Map<dynamic, dynamic> action) =>
                              NotificationAction.fromMap(
                                Map<String, dynamic>.from(action),
                              ),
                        )
                        .toList(),
                  ),
                )
                .toList()
          : [],
      androidNotificationIconPath:
          map['androidNotificationIconPath'] ?? '@mipmap/ic_launcher',
      requestPermissionOnInitialize:
          map['requestPermissionOnInitialize'] as bool? ?? false,
      permissionOptions: map['permissionOptions'] is Map
          ? NotificationPermissionOptions.fromMap(
              Map<String, dynamic>.from(map['permissionOptions'] as Map),
            )
          : const NotificationPermissionOptions(),
      synchronizeTokenOnInitialize:
          map['synchronizeTokenOnInitialize'] as bool? ?? false,
      resynchronizeUnchangedToken:
          map['resynchronizeUnchangedToken'] as bool? ?? true,
      includeInitialNotificationInStream:
          map['includeInitialNotificationInStream'] ?? true,
      enableDebugLogging: map['enableDebugLogging'] ?? false,
      exportDeliveryMetricsToBigQuery:
          map['exportDeliveryMetricsToBigQuery'] as bool? ?? false,
      analyticsOptions: map['analyticsOptions'] is Map
          ? NotificationAnalyticsOptions.fromMap(
              Map<String, dynamic>.from(map['analyticsOptions'] as Map),
            )
          : const NotificationAnalyticsOptions(),
      saveNotificationsToStorage: map['saveNotificationsToStorage'] ?? true,
      maxStoredNotifications: map['maxStoredNotifications'] ?? 100,
      enableBackgroundMessageHandling:
          map['enableBackgroundMessageHandling'] ?? true,
      enableForegroundMessageHandling:
          map['enableForegroundMessageHandling'] ?? true,
      enableNotificationScheduling: map['enableNotificationScheduling'] ?? true,
      enableBadgeManagement: map['enableBadgeManagement'] ?? true,
      enableTopicSubscriptions: map['enableTopicSubscriptions'] ?? true,
      enableDefaultDataOnlyBridge:
          map['enableDefaultDataOnlyBridge'] as bool? ?? false,
      dataOnlyBridgeChannelId: map['dataOnlyBridgeChannelId']?.toString(),
      dataOnlyBridgeTitleKey:
          map['dataOnlyBridgeTitleKey']?.toString() ?? 'title',
      dataOnlyBridgeBodyKey: map['dataOnlyBridgeBodyKey']?.toString() ?? 'body',
      defaultChannelId: map['defaultChannelId'],
      defaultImportance: NotificationImportanceEnum.values.firstWhere(
        (importance) => importance.name == map['defaultImportance'],
        orElse: () => NotificationImportanceEnum.high,
      ),
      defaultPriority: NotificationPriorityEnum.values.firstWhere(
        (priority) => priority.name == map['defaultPriority'],
        orElse: () => NotificationPriorityEnum.high,
      ),
      enableSoundByDefault: map['enableSoundByDefault'] ?? true,
      enableVibrationByDefault: map['enableVibrationByDefault'] ?? true,
      enableLightsByDefault: map['enableLightsByDefault'] ?? false,
      showBadgeByDefault: map['showBadgeByDefault'] ?? true,
      notificationCategories:
          (map['notificationCategories'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (Map<dynamic, dynamic> category) => NotificationCategory(
                  id: category['id']?.toString() ?? '',
                  name: category['name']?.toString() ?? '',
                  description: category['description']?.toString(),
                  defaultEnabled: category['defaultEnabled'] as bool? ?? true,
                  supportsSound: category['supportsSound'] as bool? ?? true,
                  supportsBadge: category['supportsBadge'] as bool? ?? true,
                ),
              )
              .toList() ??
          const <NotificationCategory>[],
      deliveryPolicy: map['deliveryPolicy'] is Map
          ? NotificationDeliveryPolicy.fromMap(
              Map<String, dynamic>.from(map['deliveryPolicy'] as Map),
            )
          : const NotificationDeliveryPolicy(),
      actionCategories:
          (map['actionCategories'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (Map<dynamic, dynamic> category) =>
                    NotificationActionCategory.fromMap(
                      Map<String, dynamic>.from(category),
                    ),
              )
              .toList() ??
          const <NotificationActionCategory>[],
      windows: map['windows'] is Map
          ? WindowsNotificationOptions.fromMap(
              Map<String, dynamic>.from(map['windows'] as Map),
            )
          : null,
    );
  }

  /// Converts the configuration to a serializable map.
  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'webVapidKey': webVapidKey,
      'androidChannels': androidChannels
          .map(
            (channel) => {
              'id': channel.id,
              'name': channel.name,
              'description': channel.description,
              'groupId': channel.groupId,
              'importance': channel.importance.name,
              'playSound': channel.playSound,
              'soundPath': channel.soundPath,
              'enableVibration': channel.enableVibration,
              'enableLights': channel.enableLights,
              'vibrationPattern': channel.vibrationPattern?.toList(),
              'ledColor': channel.ledColor?.toARGB32(),
              'showBadge': channel.showBadge,
              'priority': channel.priority.name,
              'actions': channel.actions
                  ?.map((NotificationAction action) => action.toMap())
                  .toList(),
            },
          )
          .toList(),
      'androidNotificationIconPath': androidNotificationIconPath,
      'requestPermissionOnInitialize': requestPermissionOnInitialize,
      'permissionOptions': permissionOptions.toMap(),
      'synchronizeTokenOnInitialize': synchronizeTokenOnInitialize,
      'resynchronizeUnchangedToken': resynchronizeUnchangedToken,
      'includeInitialNotificationInStream': includeInitialNotificationInStream,
      'analyticsOptions': analyticsOptions.toMap(),
      'enableDebugLogging': enableDebugLogging,
      'exportDeliveryMetricsToBigQuery': exportDeliveryMetricsToBigQuery,
      'saveNotificationsToStorage': saveNotificationsToStorage,
      'maxStoredNotifications': maxStoredNotifications,
      'enableBackgroundMessageHandling': enableBackgroundMessageHandling,
      'enableForegroundMessageHandling': enableForegroundMessageHandling,
      'enableNotificationScheduling': enableNotificationScheduling,
      'enableBadgeManagement': enableBadgeManagement,
      'enableTopicSubscriptions': enableTopicSubscriptions,
      'enableDefaultDataOnlyBridge': enableDefaultDataOnlyBridge,
      'dataOnlyBridgeChannelId': dataOnlyBridgeChannelId,
      'dataOnlyBridgeTitleKey': dataOnlyBridgeTitleKey,
      'dataOnlyBridgeBodyKey': dataOnlyBridgeBodyKey,
      'defaultChannelId': defaultChannelId,
      'defaultImportance': defaultImportance.name,
      'defaultPriority': defaultPriority.name,
      'enableSoundByDefault': enableSoundByDefault,
      'enableVibrationByDefault': enableVibrationByDefault,
      'enableLightsByDefault': enableLightsByDefault,
      'showBadgeByDefault': showBadgeByDefault,
      'notificationCategories': notificationCategories
          .map(
            (NotificationCategory category) => <String, dynamic>{
              'id': category.id,
              'name': category.name,
              'description': category.description,
              'defaultEnabled': category.defaultEnabled,
              'supportsSound': category.supportsSound,
              'supportsBadge': category.supportsBadge,
            },
          )
          .toList(),
      'deliveryPolicy': deliveryPolicy.toMap(),
      'actionCategories': actionCategories
          .map((NotificationActionCategory category) => category.toMap())
          .toList(),
      'windows': windows?.toMap(),
    };
  }

  /// Returns true when the minimum required initialization fields are present.
  bool get isValid {
    return validationErrors.isEmpty;
  }

  /// Returns a list of validation errors for missing required fields.
  List<String> get validationErrors {
    final List<String> errors = [];

    if (androidNotificationIconPath.isEmpty) {
      errors.add('Android notification icon path is required');
    }

    if (maxStoredNotifications <= 0) {
      errors.add('Maximum stored notifications must be greater than 0');
    }

    if (deliveryPolicy.globalInterval?.isNegative ?? false) {
      errors.add('Global delivery interval cannot be negative');
    }

    if (deliveryPolicy.perCategoryInterval?.isNegative ?? false) {
      errors.add('Per-category delivery interval cannot be negative');
    }

    final Set<String> categoryIds = <String>{};
    for (final NotificationCategory category in notificationCategories) {
      if (category.id.isEmpty || category.name.isEmpty) {
        errors.add('Notification category IDs and names cannot be empty');
      } else if (!categoryIds.add(category.id)) {
        errors.add('Notification category IDs must be unique: ${category.id}');
      }
    }

    final Set<String> actionCategoryIds = <String>{};
    for (final NotificationActionCategory category in actionCategories) {
      if (category.id.trim().isEmpty) {
        errors.add('Notification action category IDs cannot be empty');
      } else if (!actionCategoryIds.add(category.id)) {
        errors.add(
          'Notification action category IDs must be unique: ${category.id}',
        );
      }
      final Set<String> actionIds = <String>{};
      for (final NotificationAction action in category.actions) {
        if (action.id.trim().isEmpty || action.title.trim().isEmpty) {
          errors.add('Notification action IDs and titles cannot be empty');
        } else if (!actionIds.add(action.id)) {
          errors.add(
            'Notification action IDs must be unique in ${category.id}: ${action.id}',
          );
        }
      }
    }

    return errors;
  }
}
