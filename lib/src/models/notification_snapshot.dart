/// A pending local notification accepted by the platform scheduler.
class PendingNotificationSnapshot {
  const PendingNotificationSnapshot({
    required this.id,
    this.title,
    this.body,
    this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

/// A notification that is currently visible in the system notification UI.
class ActiveNotificationSnapshot {
  const ActiveNotificationSnapshot({
    this.id,
    this.channelId,
    this.groupKey,
    this.title,
    this.body,
    this.payload,
    this.tag,
    this.bigText,
  });

  final int? id;
  final String? channelId;
  final String? groupKey;
  final String? title;
  final String? body;
  final String? payload;
  final String? tag;
  final String? bigText;
}
