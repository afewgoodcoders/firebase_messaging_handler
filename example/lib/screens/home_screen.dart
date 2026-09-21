import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:clipboard/clipboard.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/notification_provider.dart';
import '../router/app_router.dart';
import '../services/firebase_messaging_handler_example_service.dart' as example;
import '../services/firebase_setup_service.dart';
import 'inbox_screen.dart';
import '../widgets/notification_card.dart';
import '../widgets/feature_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

const String _firebaseConsoleUrl = 'https://console.firebase.google.com/';

const String _sampleFcmPayload = '''
{
  "message": {
    "token": "<device-fcm-token>",
    "notification": {
      "title": "Welcome to FMH",
      "body": "Tap to open the Scenario screen"
    },
    "data": {
      "campaign": "showcase",
      "step": "console-push",
      "deep_link": "app://notifications/showcase",
      "fcmh_inapp": "{\\"id\\":\\"welcome_demo\\",\\"templateId\\":\\"builtin_generic\\",\\"trigger\\":\\"immediate\\",\\"content\\":{\\"layout\\":\\"dialog\\",\\"title\\":\\"Welcome!\\",\\"body\\":\\"Thanks for trying our notification testing app.\\",\\"buttons\\":[{\\"id\\":\\"explore\\",\\"label\\":\\"Explore Features\\",\\"style\\":\\"filled\\"}]}}"
    }
  }
}
''';

const Map<String, String> _templateSamples = {
  'Welcome Dialog': '''
{
  "id": "demo-welcome",
  "templateId": "builtin_generic",
  "trigger": "immediate",
  "content": {
    "layout": "dialog",
    "title": "Welcome to our app!",
    "subtitle": "Get started with these features",
    "body": "Discover powerful notification features and customize your experience.",
    "imageUrl": "https://via.placeholder.com/600x320/4F46E5/ffffff?text=Welcome",
    "buttons": [
      {"id": "explore", "label": "Explore Features", "style": "filled"},
      {"id": "later", "label": "Maybe later", "style": "outlined", "dismissOnly": true}
    ],
    "blurSigma": 18,
    "barrierColor": "#33000000"
  }
}
''',
  'Promo Banner': '''
{
  "id": "demo-banner",
  "templateId": "builtin_generic",
  "trigger": "immediate",
  "content": {
    "layout": "banner",
    "position": "top",
    "title": "Flash Sale",
    "body": "Upgrade to Pro in the next 30 minutes and save 50%.",
    "backgroundColor": "#111827",
    "textColor": "#F9FAFB",
    "autoDismissSeconds": 6,
    "buttons": [
      {"id": "cta", "label": "View offer", "style": "filled"}
    ]
  }
}
''',
  'Survey Bottom Sheet': '''
{
  "id": "demo-bottom-sheet",
  "templateId": "builtin_generic",
  "trigger": "immediate",
  "content": {
    "layout": "bottom_sheet",
    "title": "How are we doing?",
    "html": "<p>We are rolling out background delivery controls. Tell us how excited you are!</p>",
    "buttons": [
      {"id": "love_it", "label": "Love it", "style": "filled"},
      {"id": "needs_work", "label": "Needs work", "style": "text"}
    ]
  }
}
''',
  'Quick Snackbar': '''
{
  "id": "demo-snackbar",
  "templateId": "builtin_generic",
  "trigger": "immediate",
  "content": {
    "layout": "snackbar",
    "title": "Quick Tip",
    "body": "Long-press notifications in timeline for details",
    "backgroundColor": "#1E293B",
    "textColor": "#F9FAFB",
    "autoDismissSeconds": 3,
    "buttons": [
      {"id": "got_it", "label": "Got it", "style": "filled"}
    ]
  }
}
''',
  'Feature Announcement': '''
{
  "id": "demo-feature",
  "templateId": "builtin_generic",
  "trigger": "immediate",
  "content": {
    "layout": "dialog",
    "title": "New Feature Available",
    "subtitle": "Enhanced notification controls",
    "body": "We've added smart scheduling and quiet hours. Try them out!",
    "imageUrl": "https://via.placeholder.com/600x320/059669/ffffff?text=New+Feature",
    "buttons": [
      {"id": "try_now", "label": "Try Now", "style": "filled"},
      {"id": "learn_more", "label": "Learn More", "style": "outlined"},
      {"id": "dismiss", "label": "Not now", "style": "text", "dismissOnly": true}
    ],
    "blurSigma": 12,
    "barrierColor": "#22000000"
  }
}
''',
  'User Feedback Request': '''
{
  "id": "demo-feedback",
  "templateId": "builtin_generic",
  "trigger": "immediate",
  "content": {
    "layout": "bottom_sheet",
    "title": "How are we doing?",
    "body": "We'd love to hear your thoughts on our notification features.",
    "buttons": [
      {"id": "rate_5", "label": "⭐⭐⭐⭐⭐", "style": "filled"},
      {"id": "rate_4", "label": "⭐⭐⭐⭐", "style": "outlined"},
      {"id": "rate_3", "label": "⭐⭐⭐", "style": "outlined"},
      {"id": "skip", "label": "Skip", "style": "text", "dismissOnly": true}
    ]
  }
}
''',
  'HTML Spotlight': '''
{
  "id": "demo-html-modal",
  "templateId": "builtin_generic",
  "trigger": "immediate",
  "content": {
    "layout": "html_modal",
    "title": "Release Notes",
    "html": "<h2>What's new</h2><ul><li>Data-only bridging</li><li>Quiet hours</li><li>Notification doctor</li></ul>",
    "imageUrl": "https://via.placeholder.com/1200x500/0F172A/FFFFFF?text=Release",
    "buttons": [
      {"id": "dismiss", "label": "Close", "style": "filled", "dismissOnly": true}
    ],
    "backgroundColor": "#111827",
    "textColor": "#F8FAFC",
    "autoDismissSeconds": 0
  }
}
''',
};

class _HomeScreenState extends State<HomeScreen> {
  late example.FirebaseMessagingHandlerExampleService _notificationService;
  bool _templatesRegistered = false;
  late TextEditingController _templateController;
  String _selectedTemplate = _templateSamples.keys.first;
  NotificationDiagnosticsResult? _latestDiagnostics;
  bool _diagnosticsLoading = false;

  @override
  void initState() {
    super.initState();
    _notificationService = example.FirebaseMessagingHandlerExampleService(
      Provider.of<NotificationProvider>(context, listen: false),
      rootNavigatorKey,
    );
    _templateController = TextEditingController(
      text: _templateSamples[_selectedTemplate],
    );
    _initializeNotifications();
    _registerInAppTemplates();
  }

  Future<void> _initializeNotifications() async {
    await _notificationService.initialize();

    // Load cached timeline data
    if (mounted) {
      final provider = Provider.of<NotificationProvider>(
        context,
        listen: false,
      );
      await provider.loadCachedData();

      // Fetch FCM token directly if not set by callback.
      // On failure, store the exact reason so the UI can surface it.
      if (provider.fcmToken == null) {
        try {
          final token = await FirebaseMessagingHandler.instance.getFcmToken();
          if (mounted) {
            final error = FirebaseMessagingHandler.instance.lastTokenError;
            provider.setFcmToken(token, error: error);
          }
        } catch (e) {
          debugPrint('[HomeScreen] Error fetching FCM token: $e');
          if (mounted) {
            provider.setFcmToken(
              null,
              error: 'Unexpected error fetching token: $e',
            );
          }
        }
      }
    }
  }

  void _registerInAppTemplates() {
    if (_templatesRegistered) {
      return;
    }

    FirebaseMessagingHandler.instance.registerInAppNotificationTemplates({
      'builtin_generic': BuiltInInAppTemplates.generic(
        onAction: (actionId, data) {
          Provider.of<NotificationProvider>(
            context,
            listen: false,
          ).addActivity('Template action: $actionId');
        },
      ),
    });

    _templatesRegistered = true;
  }

  Future<void> _runDiagnostics() async {
    if (_diagnosticsLoading) return;
    setState(() => _diagnosticsLoading = true);

    try {
      final result = await FirebaseMessagingHandler.instance.runDiagnostics();
      if (!mounted) return;
      setState(() {
        _diagnosticsLoading = false;
        _latestDiagnostics = result;
      });
      _showDiagnosticsSheet(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _diagnosticsLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Diagnostics failed: $error')));
    }
  }

  void _showDiagnosticsSheet(NotificationDiagnosticsResult result) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final metadata = result.metadata;
        final webDiagnostics =
            metadata['webDiagnostics'] is Map<String, dynamic>
            ? metadata['webDiagnostics'] as Map<String, dynamic>
            : null;

        final entries = [
          _buildDiagnosticsRow(
            'Permissions',
            '${result.permissionsGranted ? 'Granted' : 'Not granted'} '
                '(${result.authorizationStatus})',
            result.permissionsGranted,
          ),
          _buildDiagnosticsRow(
            'Stored FCM token',
            metadata['fcmSupported'] == false
                ? 'FCM unavailable on ${result.platform}; local desktop mode active'
                : result.fcmTokenAvailable
                ? 'Token cached locally'
                : 'No token saved',
            metadata['fcmSupported'] == false || result.fcmTokenAvailable,
          ),
          _buildDiagnosticsRow(
            'Badge support',
            result.badgeSupported
                ? 'App icon badges available on ${result.platform}'
                : 'Badges unsupported on this platform/launcher',
            result.badgeSupported,
          ),
          _buildDiagnosticsRow(
            'Background handler',
            metadata['fcmSupported'] == false
                ? 'FCM background handling is unavailable on ${result.platform}'
                : metadata['backgroundHandlerRegistered'] == true
                ? 'Registered via configureBackgroundMessageHandler'
                : 'No background handler registered',
            metadata['fcmSupported'] == false ||
                metadata['backgroundHandlerRegistered'] == true,
          ),
          _buildDiagnosticsRow(
            'Pending notifications',
            '${result.pendingNotificationCount} scheduled locally',
            result.pendingNotificationCount < 16,
          ),
          if (metadata['webPermission'] != null)
            _buildDiagnosticsRow(
              'Web notification permission',
              metadata['webPermission'] as String,
              metadata['webPermission'] == 'granted',
            ),
          if (webDiagnostics != null)
            _buildDiagnosticsRow(
              'Secure context',
              webDiagnostics['isSecureContext'] == true
                  ? 'Running in a secure browser context'
                  : 'HTTPS/localhost required for web push',
              webDiagnostics['isSecureContext'] == true,
            ),
          if (webDiagnostics != null)
            _buildDiagnosticsRow(
              'Service worker',
              webDiagnostics['serviceWorkerControllerPresent'] == true
                  ? 'A service worker is controlling this page'
                  : webDiagnostics['serviceWorkerApiAvailable'] == true
                  ? 'API available, but no active controller found'
                  : 'Service workers unavailable in this browser context',
              webDiagnostics['serviceWorkerControllerPresent'] == true,
            ),
          if (webDiagnostics != null)
            _buildDiagnosticsRow(
              'Browser notification API',
              webDiagnostics['notificationApiAvailable'] == true
                  ? 'Notification API detected'
                  : 'Notification API unavailable',
              webDiagnostics['notificationApiAvailable'] == true,
            ),
        ];

        final recommendations = result.recommendations;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notification Doctor', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Platform: ${result.platform}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                ...entries,
                if (webDiagnostics != null &&
                    (webDiagnostics['locationProtocol'] != null ||
                        webDiagnostics['locationHost'] != null)) ...[
                  const SizedBox(height: 8),
                  Text('Web runtime', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SelectableText(
                    'Origin: ${webDiagnostics['locationProtocol'] ?? 'unknown'}//'
                    '${webDiagnostics['locationHost'] ?? 'unknown'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (recommendations.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Recommendations', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...recommendations.map(
                    (item) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.arrow_right, size: 20),
                      title: Text(item),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDiagnosticsRow(String label, String description, bool status) {
    final color = status ? Colors.green : Colors.orange;
    final icon = status ? Icons.check_circle_outline : Icons.error_outline;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(description),
    );
  }

  @override
  void dispose() {
    _notificationService.dispose();
    _templateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Firebase Messaging Handler Showcase',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'View analytics events',
            onPressed: () => _showAnalyticsDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.lightbulb_outline),
            tooltip: 'About the handler',
            onPressed: () => _showAboutDialog(context),
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, child) {
          return Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildShowcaseBanner(context, provider),
                    const SizedBox(height: 20),
                    _buildApnsWarningBanner(context),
                    const SizedBox(height: 20),
                    _buildStatusStrip(provider),
                    const SizedBox(height: 28),
                    if (provider.fcmToken != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () =>
                              _copyFcmToken(context, provider.fcmToken),
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy FCM token'),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    _buildFeatureSection(
                      title: 'Quick Start Scenarios',
                      subtitle:
                          'Run these to validate setup in under a minute.',
                      features: [
                        FeatureCard(
                          title: 'Send Interactive Push',
                          description:
                              'Triggers a foreground notification with action buttons.',
                          icon: Icons.send,
                          color: Colors.blue,
                          onTap: _notificationService.sendTestNotification,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Send Interactive Push',
                            body:
                                'Calls FirebaseMessagingHandler.showNotificationWithActions with a demo payload '
                                'to demonstrate interactive notifications and analytics events.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Schedule in 60 Seconds',
                          description:
                              'Demonstrates time-based delivery with analytics hooks.',
                          icon: Icons.schedule_send,
                          color: Colors.green,
                          onTap: _notificationService.scheduleTestNotification,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Schedule Notification',
                            body:
                                'Uses FirebaseMessagingHandler.scheduleNotification with a DateTime 60 seconds in the future. '
                                'We automatically manage timezone-safe delivery via flutter_local_notifications.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Daily Reminder Demo',
                          description:
                              'Configures a recurring daily notification at 09:00.',
                          icon: Icons.repeat,
                          color: Colors.orange,
                          onTap: _notificationService
                              .scheduleRecurringNotification,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Recurring Notification',
                            body:
                                'Wraps scheduleRecurringNotification with daily cadence. The handler persists the cadence '
                                'and analytics logs each repetition under notification_scheduled.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Grouped Inbox',
                          description:
                              'Creates an Android notification group with three messages.',
                          icon: Icons.group_work,
                          color: Colors.purple,
                          onTap: _notificationService.createNotificationGroup,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Notification Groups',
                            body:
                                'Calls createNotificationGroup with three NotificationData instances so you can inspect '
                                'group summaries and taps inside the Scenario screen.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Data-Only Bridge',
                          description:
                              'Converts a data-only payload into a local notification using the bridge.',
                          icon: Icons.wifi_tethering,
                          color: Colors.indigo,
                          onTap: _notificationService.triggerDataOnlyBridge,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Data-Only Bridge',
                            body:
                                'Invokes enableDefaultDataOnlyBridge and simulates a background data payload. The handler '
                                'promotes it into a local notification so users still see a banner.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Inbox Widget Demo',
                          description:
                              'Opens a storage-backed inbox with swipe-to-delete and theming.',
                          icon: Icons.inbox_outlined,
                          color: Colors.deepPurple,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const InboxScreen(),
                              ),
                            );
                          },
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Inbox Widget Demo',
                            body:
                                'Shows NotificationInboxView backed by InboxStorageService with mark-as-read, delete, and theming knobs.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Notification Doctor',
                          description: _diagnosticsLoading
                              ? 'Running environment checks...'
                              : _latestDiagnostics == null
                              ? 'Runs diagnostics for permissions, token, badges & web capabilities.'
                              : _latestDiagnostics!.recommendations.isEmpty
                              ? 'Last run: All systems look good.'
                              : 'Last run highlighted ${_latestDiagnostics!.recommendations.length} improvement(s).',
                          icon: Icons.medical_information,
                          color: Colors.teal,
                          onTap: _diagnosticsLoading ? null : _runDiagnostics,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Notification Doctor',
                            body:
                                'Invokes FirebaseMessagingHandler.runDiagnostics to verify permissions, tokens, badges, '
                                'web capabilities, and background handler wiring. Helpful when validating production builds.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _buildFeatureSection(
                      title: 'In-App Notification Templates',
                      subtitle:
                          'Trigger custom in-app templates with different styles.',
                      features: [
                        FeatureCard(
                          title: 'Welcome Template',
                          description:
                              'Shows a welcome banner with onboarding content.',
                          icon: Icons.waving_hand,
                          color: Colors.green,
                          onTap: _notificationService.triggerWelcomeTemplate,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Welcome Template',
                            body:
                                'Triggers an in-app welcome template that can be used for onboarding flows and user greetings.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Promotion Template',
                          description:
                              'Displays promotional content with call-to-action.',
                          icon: Icons.local_offer,
                          color: Colors.orange,
                          onTap: _notificationService.triggerPromotionTemplate,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Promotion Template',
                            body:
                                'Shows promotional banners with special offers and discount codes for marketing campaigns.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Alert Template',
                          description:
                              'Highlights important alerts and urgent messages.',
                          icon: Icons.warning,
                          color: Colors.red,
                          onTap: _notificationService.triggerAlertTemplate,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Alert Template',
                            body:
                                'Displays urgent alerts and important notifications that require immediate attention.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Success Template',
                          description:
                              'Celebrates successful actions and confirmations.',
                          icon: Icons.check_circle,
                          color: Colors.lightGreen,
                          onTap: _notificationService.triggerSuccessTemplate,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Success Template',
                            body:
                                'Shows success messages and confirmation banners for completed actions.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Info Template',
                          description:
                              'Provides helpful tips and informational content.',
                          icon: Icons.info,
                          color: Colors.blue,
                          onTap: _notificationService.triggerInfoTemplate,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Info Template',
                            body:
                                'Displays informational content, tips, and helpful guidance for users.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Feature Announcement',
                          description:
                              'Announce new features and capabilities to users.',
                          icon: Icons.new_releases,
                          color: Colors.green,
                          onTap: _notificationService
                              .triggerFeatureAnnouncementDemo,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Feature Announcement Template',
                            body:
                                'Perfect for announcing new features, capabilities, or improvements. Uses a dialog layout with customizable content.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _buildFeatureSection(
                      title: 'Power Features & Utilities',
                      subtitle: 'Fine tune presentation, badges and sound.',
                      features: [
                        FeatureCard(
                          title: 'Update Badges',
                          description:
                              'Update the app-icon badge when the runtime supports it.',
                          icon: Icons.confirmation_num,
                          color: Colors.teal,
                          onTap: _notificationService.updateBadges,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Badge Management',
                            body:
                                'Checks runtime capabilities before invoking the iOS native badge bridge. Unsupported '
                                'platforms report that limitation instead of simulating success.',
                          ),
                        ),
                        FeatureCard(
                          title: 'User Feedback',
                          description:
                              'Collect user feedback and ratings through interactive templates.',
                          icon: Icons.feedback,
                          color: Colors.orange,
                          onTap: _notificationService.triggerUserFeedbackDemo,
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'User Feedback Template',
                            body:
                                'Collect user feedback, ratings, and suggestions through interactive bottom sheet templates. '
                                'Perfect for understanding user satisfaction and gathering insights.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Custom Sound Channel',
                          description:
                              'Build and register a sound-enabled notification channel.',
                          icon: Icons.music_note,
                          color: Colors.pink,
                          onTap: () async {
                            final notificationProvider =
                                Provider.of<NotificationProvider>(
                                  context,
                                  listen: false,
                                );
                            final messenger = ScaffoldMessenger.of(context);
                            await _notificationService.messagingHandler
                                .createCustomSoundChannel(
                                  channelId: 'music_channel',
                                  channelName: 'Music Notifications',
                                  channelDescription:
                                      'Notifications with custom sound',
                                  soundFileName: 'default',
                                  importance: NotificationImportanceEnum.high,
                                  priority: NotificationPriorityEnum.high,
                                );
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Custom sound channel registered.',
                                ),
                              ),
                            );
                            notificationProvider.addActivity(
                              'Registered custom sound channel',
                            );
                          },
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Custom Sounds',
                            body:
                                'Demonstrates createCustomSoundChannel to provision an Android channel with explicit sound, '
                                'importance and vibration configuration.',
                          ),
                        ),
                        FeatureCard(
                          title: 'Clear Demo State',
                          description:
                              'Reset scheduled notifications, badges and timeline.',
                          icon: Icons.delete_sweep,
                          color: Colors.redAccent,
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await _notificationService.clearAllNotifications();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Demo state cleared.'),
                              ),
                            );
                          },
                          onInfoTap: () => _showFeatureInfo(
                            context,
                            title: 'Clear Demo State',
                            body:
                                'Cancels scheduled notifications, resets badges, clears local history and activity logs to give '
                                'you a fresh testing slate.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _buildTemplatePlayground(provider),
                    const SizedBox(height: 32),
                    _buildNotificationStream(context, provider),
                    const SizedBox(height: 28),
                    _buildActivityTimeline(provider),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildShowcaseBanner(
    BuildContext context,
    NotificationProvider provider,
  ) {
    final token = provider.fcmToken;
    final tokenError = provider.tokenError;
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome to our Notification Testing Application',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'This example showcases every optional feature in the Firebase Messaging Handler. '
              'Follow the three-step loop below and watch analytics, badges, navigation, and in-app templates respond in real time.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _buildShowcaseStep(
              context,
              icon: Icons.touch_app,
              title: 'Trigger a showcase',
              description:
                  'Tap a card under "Quick Start" to fire an instant notification, scheduling job, or grouped inbox.',
            ),
            _buildShowcaseStep(
              context,
              icon: Icons.cast,
              title: 'Send a remote push',
              description:
                  'Use the Firebase console payload template to target this device and inspect the Scenario screen.',
            ),
            _buildShowcaseStep(
              context,
              icon: Icons.analytics_outlined,
              title: 'Review insights',
              description:
                  'Open the analytics dialog, observe badge parity, and track activity timeline updates.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: token == null
                      ? null
                      : () => _copyFcmToken(context, token),
                  icon: const Icon(Icons.copy),
                  label: Text(
                    token == null ? 'FCM token unavailable' : 'Copy FCM token',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openFirebaseConsole,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Firebase Console'),
                ),
                TextButton.icon(
                  onPressed: () => _showPayloadDialog(context),
                  icon: const Icon(Icons.code),
                  label: const Text('Sample payload'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (token != null)
              SelectableText(
                token,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              )
            else if (tokenError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        tokenError,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              const Text(
                'Waiting for FCM token…',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildApnsWarningBanner(BuildContext context) {
    // Only show warning if we continued without APNs
    if (!FirebaseSetupService.isIOSApnsError) {
      return const SizedBox.shrink();
    }

    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.amber.shade700,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'iOS Notifications Limited',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'iOS notifications won\'t work without APNs setup. Android features work normally.',
                    style: TextStyle(
                      color: Colors.amber.shade700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShowcaseStep(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStrip(NotificationProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 720) {
          return Row(
            children: [
              Expanded(child: _buildStatusCard(provider)),
              const SizedBox(width: 16),
              Expanded(child: _buildBadgeManagement(provider)),
            ],
          );
        }
        return Column(
          children: [
            _buildStatusCard(provider),
            const SizedBox(height: 16),
            _buildBadgeManagement(provider),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard(NotificationProvider provider) {
    final initialized = provider.isInitialized;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  initialized ? Icons.verified : Icons.hourglass_top,
                  color: initialized ? Colors.green : Colors.orangeAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    initialized
                        ? 'Handler ready – listening across foreground, background & terminated states.'
                        : 'Initializing Firebase Messaging Handler…',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              initialized
                  ? 'We requested permissions, registered notification channels, and wired analytics callbacks.'
                  : 'Permissions, channels and analytics callbacks are setting up – this typically takes a moment.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeManagement(NotificationProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Badge Snapshot',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BadgePill(
                  label: 'iOS',
                  value: provider.iosBadgeCount,
                  color: Colors.blueAccent,
                ),
                _BadgePill(
                  label: 'Android',
                  value: provider.androidBadgeCount,
                  color: Colors.deepPurpleAccent,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Use the “Update Badges” card to sync counts or “Clear Demo State” to reset.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureSection({
    required String title,
    String? subtitle,
    required List<FeatureCard> features,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 16, runSpacing: 16, children: features),
      ],
    );
  }

  Widget _buildNotificationStream(
    BuildContext context,
    NotificationProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Notification Timeline',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (provider.notifications.isNotEmpty)
              TextButton.icon(
                onPressed: () => _clearTimeline(context, provider),
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (provider.notifications.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'Trigger one of the scenarios above or send a remote push from Firebase Console to populate the timeline.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          )
        else
          ...provider.notifications
              .take(10)
              .map(
                (notification) => NotificationCard(
                  notification: notification,
                  onTap: () => _openTimelineDetails(notification),
                ),
              ),
        if (provider.initialNotification != null) ...[
          const SizedBox(height: 20),
          const Text(
            'Launch Notification',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          NotificationCard(
            notification: provider.initialNotification!,
            isInitial: true,
            onTap: () => _openTimelineDetails(provider.initialNotification!),
          ),
        ],
      ],
    );
  }

  Widget _buildActivityTimeline(NotificationProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Activity Timeline',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (provider.activityLog.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _clearActivityLog(context, provider),
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (provider.activityLog.isEmpty)
              Text(
                'Actions you take (sending, scheduling, clearing) will be logged here with timestamps.',
                style: TextStyle(color: Colors.grey.shade700),
              )
            else
              ...provider.activityLog
                  .take(8)
                  .map(
                    (entry) => ListTile(
                      leading: const Icon(Icons.bolt_outlined),
                      title: Text(entry.label),
                      subtitle: Text(_formatTimestamp(entry.timestamp)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplatePlayground(NotificationProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Template Playground',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Simulate silent FCM payloads and preview dialog, banner, bottom sheet, snackbar, and carousel layouts.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'These are just examples! You can create custom templates with any layout, styling, and behavior using our flexible template system.',
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedTemplate,
                    decoration: const InputDecoration(
                      labelText: 'Sample payload',
                      border: OutlineInputBorder(),
                    ),
                    items: _templateSamples.keys
                        .map(
                          (name) =>
                              DropdownMenuItem(value: name, child: Text(name)),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedTemplate = value;
                        _templateController.text =
                            _templateSamples[value] ?? _templateController.text;
                      });
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Reset sample',
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    setState(() {
                      _templateController.text =
                          _templateSamples[_selectedTemplate] ?? '';
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _templateController,
              maxLines: 12,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Template JSON',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _triggerTemplateFromJson,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Trigger Template'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '💡 Pro Tip: These are just examples! Register custom templates with your own layouts, animations, and interactions. The plugin provides the infrastructure - you build the experience!',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyFcmToken(BuildContext context, String? token) async {
    if (token == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await FlutterClipboard.copy(token);
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('FCM token copied to clipboard')),
    );
  }

  void _clearActivityLog(BuildContext context, NotificationProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Activity Log'),
        content: const Text(
          'Are you sure you want to clear all activity entries? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              provider.clearActivity();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Activity log cleared'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _clearTimeline(BuildContext context, NotificationProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Timeline'),
        content: const Text(
          'This will remove stored notifications and activity entries from the local timeline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await provider.clearTimelineCache();
              if (!context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Timeline cleared'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _openTimelineDetails(NotificationData data) {
    _notificationService.openScenarioFromTimeline(data);
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final date =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date · $time';
  }

  void _openFirebaseConsole() {
    launchUrl(
      Uri.parse(_firebaseConsoleUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  void _showFeatureInfo(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showPayloadDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sample Firebase Console Payload'),
        content: SizedBox(
          width: double.maxFinite,
          child: SelectableText(
            _sampleFcmPayload,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => FlutterClipboard.copy(_sampleFcmPayload),
            child: const Text('Copy JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Why Firebase Messaging Handler'),
        content: const Text(
          'This example app is backed entirely by firebase_messaging_handler. The plugin exposes a unified API for '
          'tokens, initial notification handling, foreground fallbacks, scheduling, grouping, analytics hooks, '
          'badge parity, and in-app templates. Explore each section to see how the optional pieces layer on top '
          'of the core click stream.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAnalyticsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Analytics Events'),
        content: const Text(
          'Check your console/logs for detailed analytics events including:\n\n'
          '• notification_received\n'
          '• notification_clicked\n'
          '• notification_action\n'
          '• notification_scheduled\n'
          '• fcm_token events\n\n'
          'All events include platform, timestamp, and relevant metadata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerTemplateFromJson() async {
    try {
      await _notificationService.triggerTemplateFromJson(
        _templateController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template triggered successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Template trigger failed: $error')),
      );
    }
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            value.toString(),
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
