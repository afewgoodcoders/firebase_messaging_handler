/// Web-safe local-notification request shape.
///
/// Native detail overrides are retained as opaque values so shared application
/// code can compile, but `showLocalNotification` returns `unsupported` on web.
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
  final Object? androidDetails;
  final Object? appleDetails;
  final Object? linuxDetails;
  final Object? windowsDetails;
}
