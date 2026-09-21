import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Fully typed local-notification request with native-platform escape hatches.
///
/// Use [androidDetails] for styles such as big picture, inbox, messaging,
/// media, progress, conversations, full-screen intents, and call layouts. Use
/// [appleDetails] for attachments, interruption levels, relevance, categories,
/// and thread metadata. [linuxDetails] and [windowsDetails] expose the complete
/// desktop option sets supported by `flutter_local_notifications`.
class LocalNotificationRequest {
  const LocalNotificationRequest({
    required this.id,
    required this.title,
    required this.body,
    this.payload = const <String, dynamic>{},
    this.channelId,
    this.category,
    this.threadIdentifier,
    this.groupKey,
    this.isGroupSummary = false,
    this.androidDetails,
    this.appleDetails,
    this.linuxDetails,
    this.windowsDetails,
  });

  final int id;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final String? channelId;
  final String? category;
  final String? threadIdentifier;
  final String? groupKey;
  final bool isGroupSummary;
  final AndroidNotificationDetails? androidDetails;
  final DarwinNotificationDetails? appleDetails;
  final LinuxNotificationDetails? linuxDetails;
  final WindowsNotificationDetails? windowsDetails;
}
