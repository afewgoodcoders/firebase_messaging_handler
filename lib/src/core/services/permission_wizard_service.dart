import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/platform_utils.dart';
import '../../models/permission_wizard_result.dart';

/// Small cross-platform helper that requests notification permissions and
/// returns actionable guidance for the current platform.
class PermissionWizardService {
  const PermissionWizardService();

  /// Requests platform notification permissions or returns platform-specific
  /// guidance when direct permission APIs are unavailable.
  Future<PermissionWizardResult> requestPermissions() async {
    final List<String> notes = <String>[];
    bool? androidPost;
    String? androidExactAlarmNote;
    String? iosStatus;
    String? webStatus;

    if (isWindows || isLinux) {
      notes.add(
        'Firebase Cloud Messaging is not available on $currentPlatformName. Use local notifications, scheduling, inbox, and in-app templates in desktop mode.',
      );
      notes.add(
        'If you need remote delivery on desktop, route messages through your backend and present them locally in the app.',
      );
      return PermissionWizardResult(
        overallStatus: 'desktop_local_mode',
        notes: notes,
      );
    }

    if (isWeb) {
      // Web permissions are handled by the browser prompt; firebase_messaging
      // will request when getToken is called. We surface a note only.
      webStatus = 'prompt';
      notes.add(
        'Web: ensure you call requestPermission() or getToken() to trigger the browser prompt.',
      );
      return PermissionWizardResult(
        overallStatus: 'web_prompt',
        webPermission: webStatus,
        notes: notes,
      );
    }

    final NotificationSettings settings = await FirebaseMessaging.instance
        .requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

    if (isAndroid) {
      // POST_NOTIFICATIONS is covered by requestPermission on Android 13+.
      androidPost =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      androidExactAlarmNote =
          'Exact alarm permission must be granted in system settings on Android 14+ (SCHEDULE_EXACT_ALARM).';
      notes.add(
        'Android: if scheduling exact alarms, prompt users to enable exact alarms in system settings.',
      );
    } else if (isIOS) {
      iosStatus = settings.authorizationStatus.name;
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        notes.add('iOS: notifications not authorized ($iosStatus).');
      }
    }

    final bool ok =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    return PermissionWizardResult(
      overallStatus: ok ? 'granted' : 'denied',
      androidPostNotifications: androidPost,
      androidExactAlarmNote: androidExactAlarmNote,
      iosAuthorizationStatus: iosStatus,
      webPermission: webStatus,
      notes: notes,
    );
  }
}
