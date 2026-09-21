import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../providers/notification_provider.dart';
import '../screens/scenario_screen.dart';

/// Example service demonstrating the new Firebase Messaging Handler architecture
///
/// This service showcases how to use the refactored plugin with:
/// - Modular architecture with clear separation of concerns
/// - Comprehensive error handling and logging
/// - Analytics integration
/// - Cross-platform notification management
/// - Backward compatibility with existing APIs
class FirebaseMessagingHandlerExampleService {
  final FirebaseMessagingHandler _messagingHandler =
      FirebaseMessagingHandler.instance;
  final NotificationProvider _notificationProvider;
  final GlobalKey<NavigatorState> _navigatorKey;
  final InAppMessageManager _inAppMessageManager = InAppMessageManager.instance;

  FirebaseMessagingHandlerExampleService(
    this._notificationProvider,
    this._navigatorKey,
  );

  Future<void> initialize() async {
    try {
      // Initialize channels, preferences, policy, analytics, and token handling
      // from one immutable configuration.
      final Stream<NotificationData?>?
      clickStream = await _messagingHandler.initialize(
        FCMConfiguration(
          senderId: DefaultFirebaseOptions.currentPlatform.messagingSenderId,
          androidChannels: <NotificationChannelData>[
            NotificationChannelData(
              id: 'default_channel',
              name: 'Default Notifications',
              description: 'Default notification channel',
              importance: NotificationImportanceEnum.high,
              priority: NotificationPriorityEnum.high,
              playSound: true,
              enableVibration: true,
              enableLights: true,
            ),
            NotificationChannelData(
              id: 'actions_channel',
              name: 'Action Notifications',
              description: 'Notifications with interactive buttons',
              importance: NotificationImportanceEnum.max,
              priority: NotificationPriorityEnum.max,
              playSound: true,
              enableVibration: true,
              enableLights: true,
            ),
            NotificationChannelData(
              id: 'scheduled_channel',
              name: 'Scheduled Notifications',
              description: 'Scheduled notification channel',
              importance: NotificationImportanceEnum.high,
              priority: NotificationPriorityEnum.high,
              playSound: true,
              enableVibration: false,
            ),
          ],
          androidNotificationIconPath: '@drawable/ic_notification',
          // Web: pass your VAPID key from Firebase Console → Project Settings →
          // Cloud Messaging → Web Push certificates → Key pair.
          // null uses the project's default key pair (works for most setups).
          webVapidKey: kIsWeb ? null : null,
          notificationCategories: const <NotificationCategory>[
            NotificationCategory(
              id: 'orders',
              name: 'Order updates',
              description: 'Shipping and delivery alerts',
            ),
            NotificationCategory(
              id: 'promotion',
              name: 'Promotions',
              defaultEnabled: false,
            ),
            NotificationCategory(id: 'message', name: 'Messages'),
          ],
          deliveryPolicy: const NotificationDeliveryPolicy(
            perCategoryDailyCap: 50,
          ),
          updateTokenCallback: (String fcmToken) async {
            debugPrint('FCM Token: $fcmToken');
            _notificationProvider.setFcmToken(fcmToken);

            // In a real app, send this token to your backend.
            return true;
          },
          analyticsCallback: (String event, Map<String, dynamic> data) {
            debugPrint('Analytics Event: $event - $data');
          },
        ),
      );

      await _messagingHandler.setUnifiedMessageHandler(_handleUnifiedMessage);

      // Listen to notification clicks
      clickStream?.listen((NotificationData? data) {
        if (data != null) {
          _handleNotificationClick(data);
        }
      });

      _messagingHandler.deliveryEvents.listen((
        NotificationDeliveryEvent event,
      ) {
        _notificationProvider.addActivity(
          '${event.type.name}: ${event.messageId}'
          '${event.reason == null ? '' : ' (${event.reason})'}',
        );
      });

      _notificationProvider.setInitialized(true);
      debugPrint('Firebase Messaging Handler initialized successfully');
      _notificationProvider.addActivity('Handler initialized');

      await _messagingHandler.setInAppDeliveryPolicy(
        const InAppDeliveryPolicy(
          globalInterval: Duration(seconds: 20),
          perTemplateInterval: Duration(minutes: 1),
          perTemplateDailyCap: 8,
          quietHours: InAppQuietHours(startHour: 22, endHour: 7),
        ),
      );

      await _messagingHandler.configureBackgroundProcessingCallback((
        RemoteMessage message,
      ) async {
        _notificationProvider.addActivity(
          'Background callback processed ${message.messageId ?? 'unknown'}',
        );
        return true;
      });

      _messagingHandler.enableDefaultDataOnlyBridge(
        channelId: 'actions_channel',
      );
    } catch (e) {
      debugPrint('Error initializing Firebase Messaging Handler: $e');
      _notificationProvider.setInitialized(false);
      _notificationProvider.addActivity('Initialization error: $e');
    }
  }

  Future<bool> _handleUnifiedMessage(
    NormalizedMessage message,
    NotificationLifecycle lifecycle,
  ) async {
    _notificationProvider.addActivity(
      'Unified (${lifecycle.name}): ${message.title ?? message.id}',
    );

    // Avoid UI work when running in background isolate
    if (lifecycle == NotificationLifecycle.background) {
      return true;
    }

    if (_navigatorKey.currentState != null) {
      _navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => ScenarioScreen(
            notification: NotificationData(
              title: message.title,
              body: message.body,
              payload: message.data,
              timestamp: message.receivedAt,
              type: lifecycle == NotificationLifecycle.terminated
                  ? NotificationTypeEnum.terminated
                  : NotificationTypeEnum.background,
              messageId: message.id,
            ),
          ),
        ),
      );
    }

    return true;
  }

  void _handleNotificationClick(
    NotificationData data, {
    bool isInitial = false,
  }) {
    // Add to notifications list
    _notificationProvider.addNotification(data);
    _notificationProvider.setActiveNotification(data);

    // Handle notification actions
    if (data.payload['is_action'] == true) {
      final actionId = data.payload['action_id'];
      final actionPayload = data.payload['action_payload'];

      switch (actionId) {
        case 'reply':
          _showReplyDialog(actionPayload);
          _notificationProvider.addActivity('Reply action tapped');
          break;
        case 'view':
          _navigateToProfile(actionPayload);
          _notificationProvider.addActivity('View details action tapped');
          break;
        case 'call':
          _makePhoneCall(actionPayload);
          _notificationProvider.addActivity('Call action tapped');
          break;
        case 'dismiss':
          // Just dismiss, no action needed
          _notificationProvider.addActivity('Dismiss action tapped');
          break;
      }
      return;
    }

    // Handle regular notification clicks based on type
    switch (data.type) {
      case NotificationTypeEnum.foreground:
        _showInAppNotification(data);
        break;
      case NotificationTypeEnum.background:
      case NotificationTypeEnum.terminated:
        if (!isInitial) {
          _navigateToScreen(data);
        }
        break;
    }

    // Handle in-app notification templates
    if (data.payload['in_app'] == 'true' || data.payload['in_app'] == true) {
      final template = data.payload['template'] as String?;
      _showInAppTemplate(data, template);
      return;
    }

    // Handle specific notification categories
    if (data.category == 'promotion') {
      _showPromotionDialog(data);
    } else if (data.category == 'message') {
      _showMessageDialog(data);
    }
  }

  void _showInAppNotification(NotificationData data) {
    debugPrint('Showing in-app notification: ${data.title}');
    // In a real app, you might show a snackbar or overlay
  }

  void _navigateToScreen(NotificationData data) {
    debugPrint('Navigating to screen for notification: ${data.title}');
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => ScenarioScreen(notification: data)),
    );
  }

  void _showReplyDialog(Map<String, dynamic>? payload) {
    debugPrint('Showing reply dialog for payload: $payload');
    // In a real app, show a dialog for replying
  }

  void _navigateToProfile(Map<String, dynamic>? payload) {
    debugPrint('Navigating to profile for payload: $payload');
    // In a real app, navigate to user profile
  }

  void _makePhoneCall(Map<String, dynamic>? payload) async {
    final phoneNumber = payload?['phone_number'];
    if (phoneNumber != null) {
      final Uri url = Uri.parse('tel:$phoneNumber');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    }
  }

  void _showPromotionDialog(NotificationData data) {
    debugPrint('Showing promotion dialog: ${data.title}');
    // In a real app, show promotion details
  }

  void _showMessageDialog(NotificationData data) {
    debugPrint('Showing message dialog: ${data.title}');
    // In a real app, show message details
  }

  void _showInAppTemplate(NotificationData data, String? template) {
    debugPrint('Showing in-app template: $template for ${data.title}');

    // Show different templates based on the template type
    switch (template) {
      case 'welcome':
        _showWelcomeTemplate(data);
        break;
      case 'promotion':
        _showPromotionTemplate(data);
        break;
      case 'alert':
        _showAlertTemplate(data);
        break;
      case 'success':
        _showSuccessTemplate(data);
        break;
      case 'info':
        _showInfoTemplate(data);
        break;
      default:
        _showDefaultTemplate(data);
        break;
    }

    _notificationProvider.addActivity('In-app template shown: $template');
  }

  void _showWelcomeTemplate(NotificationData data) {
    // In a real app, show a welcome banner or modal
    debugPrint('Welcome template: ${data.title} - ${data.body}');
  }

  void _showPromotionTemplate(NotificationData data) {
    // In a real app, show a promotion banner with CTA
    debugPrint('Promotion template: ${data.title} - ${data.body}');
  }

  void _showAlertTemplate(NotificationData data) {
    // In a real app, show an alert banner
    debugPrint('Alert template: ${data.title} - ${data.body}');
  }

  void _showSuccessTemplate(NotificationData data) {
    // In a real app, show a success banner
    debugPrint('Success template: ${data.title} - ${data.body}');
  }

  void _showInfoTemplate(NotificationData data) {
    // In a real app, show an info banner
    debugPrint('Info template: ${data.title} - ${data.body}');
  }

  void _showDefaultTemplate(NotificationData data) {
    // In a real app, show a default banner
    debugPrint('Default template: ${data.title} - ${data.body}');
  }

  // ===== DEMO METHODS FOR SHOWCASING FEATURES =====

  Future<void> sendTestNotification() async {
    await _messagingHandler.showNotificationWithActions(
      title: 'Test Notification',
      body: 'This is a test notification with actions',
      actions: [
        NotificationAction(
          id: 'reply',
          title: 'Reply',
          payload: {'action': 'reply', 'message_id': 'test_123'},
        ),
        NotificationAction(
          id: 'view',
          title: 'View Details',
          destructive: false,
        ),
      ],
      payload: {'test': true, 'timestamp': DateTime.now().toIso8601String()},
      channelId: 'actions_channel',
    );
    _notificationProvider.addActivity('Sent interactive notification');
  }

  Future<void> scheduleTestNotification() async {
    final scheduledTime = DateTime.now().add(const Duration(minutes: 1));
    await _messagingHandler.scheduleNotification(
      id: 1,
      title: 'Scheduled Notification',
      body: 'This notification was scheduled 1 minute ago',
      scheduledDate: scheduledTime,
      channelId: 'scheduled_channel',
      payload: {
        'scheduled': true,
        'scheduled_time': scheduledTime.toIso8601String(),
      },
    );
    _notificationProvider.addActivity('Scheduled one-time notification');
  }

  Future<void> scheduleRecurringNotification() async {
    await _messagingHandler.scheduleRecurringNotification(
      id: 2,
      title: 'Daily Reminder',
      body: 'This is your daily reminder',
      repeatInterval: 'daily',
      hour: 9,
      minute: 0,
      channelId: 'scheduled_channel',
      payload: {'recurring': true, 'type': 'daily_reminder'},
    );
    _notificationProvider.addActivity('Scheduled recurring notification');
  }

  Future<void> createNotificationGroup() async {
    final notifications = [
      NotificationData(
        title: 'Message 1',
        body: 'Hello from user 1',
        payload: {'message_id': '1', 'user': 'user1'},
      ),
      NotificationData(
        title: 'Message 2',
        body: 'Hello from user 2',
        payload: {'message_id': '2', 'user': 'user2'},
      ),
      NotificationData(
        title: 'Message 3',
        body: 'Hello from user 3',
        payload: {'message_id': '3', 'user': 'user3'},
      ),
    ];

    await _messagingHandler.createNotificationGroup(
      groupKey: 'messages_demo',
      groupTitle: 'Demo Messages',
      notifications: notifications,
      channelId: 'default_channel',
    );
    _notificationProvider.addActivity('Created notification group demo');
  }

  Future<void> triggerDataOnlyBridge() async {
    final RemoteMessage mockMessage =
        FirebaseMessagingHandler.createMockRemoteMessage(
          messageId: 'data_bridge_${DateTime.now().millisecondsSinceEpoch}',
          data: {
            'title': 'Data-only Promotion',
            'body': 'This data payload was promoted to a local notification.',
            'deep_link': 'app://notifications/data-only',
          },
        );

    await FirebaseMessagingHandler.handleBackgroundMessage(mockMessage);
    _notificationProvider.addActivity(
      'Triggered data-only message bridge and local notification',
    );
  }

  Future<void> updateBadges() async {
    final NotificationCapabilities capabilities = await _messagingHandler
        .getCapabilities();
    if (!capabilities.supports(NotificationCapability.appIconBadge)) {
      _notificationProvider.addActivity(
        'App-icon badge mutation is unsupported on this platform',
      );
      return;
    }
    await _messagingHandler.setIOSBadgeCount(5);
    _notificationProvider.setIOSBadgeCount(5);
    _notificationProvider.addActivity('Updated the supported app-icon badge');
  }

  Future<void> clearAllNotifications() async {
    await _messagingHandler.cancelAllScheduledNotifications();
    _notificationProvider.clearAll();
    await _messagingHandler.clearBadgeCount();
    _notificationProvider.addActivity('Cleared scheduled notifications');
  }

  Future<void> triggerFeatureAnnouncementDemo() async {
    final now = DateTime.now();
    final content = {
      'layout': 'dialog',
      'title': 'New Feature Available',
      'subtitle': 'Enhanced notification controls',
      'body': 'We\'ve added smart scheduling and quiet hours. Try them out!',
      'imageUrl':
          'https://via.placeholder.com/600x320/059669/ffffff?text=New+Feature',
      'buttons': [
        {'id': 'try_now', 'label': 'Try Now', 'style': 'filled'},
        {'id': 'learn_more', 'label': 'Learn More', 'style': 'outlined'},
        {
          'id': 'dismiss',
          'label': 'Not now',
          'style': 'text',
          'dismissOnly': true,
        },
      ],
      'blurSigma': 12,
      'barrierColor': '#22000000',
    };

    final data = InAppNotificationData(
      id: 'feature_announcement_${now.millisecondsSinceEpoch}',
      templateId: 'builtin_generic',
      triggerType: InAppTriggerTypeEnum.immediate,
      content: content,
      analytics: {
        'source': 'example_demo',
        'campaign': 'showcase_feature_announcement',
      },
      rawPayload: {'templateId': 'builtin_generic', 'content': content},
      receivedAt: now,
    );

    await _inAppMessageManager.triggerInAppNotification(data);
    _notificationProvider.addActivity(
      'Triggered feature announcement template',
    );
  }

  Future<void> triggerUserFeedbackDemo() async {
    final now = DateTime.now();
    final content = {
      'layout': 'bottom_sheet',
      'title': 'How are we doing?',
      'body': 'We\'d love to hear your thoughts on our notification features.',
      'buttons': [
        {'id': 'rate_5', 'label': '⭐⭐⭐⭐⭐', 'style': 'filled'},
        {'id': 'rate_4', 'label': '⭐⭐⭐⭐', 'style': 'outlined'},
        {'id': 'rate_3', 'label': '⭐⭐⭐', 'style': 'outlined'},
        {'id': 'skip', 'label': 'Skip', 'style': 'text', 'dismissOnly': true},
      ],
    };

    final data = InAppNotificationData(
      id: 'user_feedback_${now.millisecondsSinceEpoch}',
      templateId: 'builtin_generic',
      triggerType: InAppTriggerTypeEnum.immediate,
      content: content,
      analytics: {
        'source': 'example_demo',
        'campaign': 'showcase_user_feedback',
      },
      rawPayload: {'templateId': 'builtin_generic', 'content': content},
      receivedAt: now,
    );

    await _inAppMessageManager.triggerInAppNotification(data);
    _notificationProvider.addActivity('Triggered user feedback template');
  }

  void openScenarioFromTimeline(NotificationData data) {
    _navigateToScreen(data);
  }

  Future<void> triggerTemplateFromJson(String source) async {
    try {
      final decoded = jsonDecode(source) as Map<String, dynamic>;
      final data = _mapToInAppData(decoded);
      await _inAppMessageManager.triggerInAppNotification(data);
      _notificationProvider.addActivity(
        'Triggered ${data.templateId} template manually',
      );
    } catch (error, stack) {
      debugPrint('Error triggering template: $error');
      debugPrint('$stack');
      rethrow;
    }
  }

  InAppNotificationData _mapToInAppData(Map<String, dynamic> map) {
    if (map.containsKey('message')) {
      // FCM message format
      final data = Map<String, dynamic>.from(
        map['message']['data'] as Map? ?? <String, dynamic>{},
      );
      if (data.containsKey('fcmh_inapp')) {
        final payloadString = data['fcmh_inapp'] as String;
        try {
          final payload = jsonDecode(payloadString) as Map<String, dynamic>;
          return _mapToInAppData(payload);
        } catch (e) {
          debugPrint('Failed to decode fcmh_inapp payload: $e');
        }
      }
      map = data;
    }

    final content = Map<String, dynamic>.from(
      map['content'] as Map? ?? <String, dynamic>{},
    );
    final analytics = Map<String, dynamic>.from(
      map['analytics'] as Map? ?? <String, dynamic>{},
    );
    final rawPayload = Map<String, dynamic>.from(
      map['rawPayload'] as Map? ?? <String, dynamic>{},
    );

    final triggerString = (map['trigger'] ?? map['triggerType']) as String?;
    final trigger = InAppTriggerTypeEnum.fromString(triggerString);

    final id =
        (map['id'] ??
                map['messageId'] ??
                'template_${DateTime.now().millisecondsSinceEpoch}')
            .toString();
    final templateId =
        (map['templateId'] ?? map['template'] ?? 'builtin_generic').toString();

    final receivedAtString = map['receivedAt'] as String?;
    final receivedAt = receivedAtString != null
        ? DateTime.tryParse(receivedAtString)
        : null;

    return InAppNotificationData(
      id: id,
      templateId: templateId,
      triggerType: trigger,
      content: content,
      analytics: analytics,
      rawPayload: rawPayload,
      receivedAt: receivedAt ?? DateTime.now(),
    );
  }

  Future<String?> getCurrentFcmToken() async {
    return await _messagingHandler.getFcmToken();
  }

  Future<void> dispose() async {
    await _messagingHandler.dispose();
  }

  // Public accessor for messaging handler (for advanced usage)
  FirebaseMessagingHandler get messagingHandler => _messagingHandler;

  // ===== IN-APP TEMPLATE DEMO METHODS =====

  Future<void> triggerWelcomeTemplate() async {
    await _messagingHandler.showNotificationWithActions(
      title: 'Welcome to Our Notification Testing App',
      body: 'This is a welcome template triggered from the app',
      actions: [],
      payload: {
        'in_app': true,
        'template': 'welcome',
        'campaign': 'demo',
        'source': 'manual_trigger',
      },
      channelId: 'default_channel',
    );
    _notificationProvider.addActivity('Triggered welcome template');
  }

  Future<void> triggerPromotionTemplate() async {
    await _messagingHandler.showNotificationWithActions(
      title: 'Special Offer Available!',
      body: 'Get 50% off on all premium features',
      actions: [],
      payload: {
        'in_app': true,
        'template': 'promotion',
        'campaign': 'demo',
        'source': 'manual_trigger',
        'offer_code': 'DEMO50',
      },
      channelId: 'default_channel',
    );
    _notificationProvider.addActivity('Triggered promotion template');
  }

  Future<void> triggerAlertTemplate() async {
    await _messagingHandler.showNotificationWithActions(
      title: 'Important Alert',
      body: 'Please update your app to the latest version',
      actions: [],
      payload: {
        'in_app': true,
        'template': 'alert',
        'campaign': 'demo',
        'source': 'manual_trigger',
        'priority': 'high',
      },
      channelId: 'default_channel',
    );
    _notificationProvider.addActivity('Triggered alert template');
  }

  Future<void> triggerSuccessTemplate() async {
    await _messagingHandler.showNotificationWithActions(
      title: 'Success!',
      body: 'Your notification settings have been updated',
      actions: [],
      payload: {
        'in_app': true,
        'template': 'success',
        'campaign': 'demo',
        'source': 'manual_trigger',
        'action': 'settings_updated',
      },
      channelId: 'default_channel',
    );
    _notificationProvider.addActivity('Triggered success template');
  }

  Future<void> triggerInfoTemplate() async {
    await _messagingHandler.showNotificationWithActions(
      title: 'Did you know?',
      body: 'You can customize notification channels in Android settings',
      actions: [],
      payload: {
        'in_app': true,
        'template': 'info',
        'campaign': 'demo',
        'source': 'manual_trigger',
        'tip': 'notification_channels',
      },
      channelId: 'default_channel',
    );
    _notificationProvider.addActivity('Triggered info template');
  }
}
