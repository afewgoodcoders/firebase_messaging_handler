/// Fine-grained permission options used by the explicit permission flow.
class NotificationPermissionOptions {
  /// Creates notification permission options.
  const NotificationPermissionOptions({
    this.alert = true,
    this.badge = true,
    this.sound = true,
    this.provisional = false,
    this.announcement = false,
    this.carPlay = false,
    this.criticalAlert = false,
  });

  /// Permission to display alerts.
  final bool alert;

  /// Permission to update the application badge.
  final bool badge;

  /// Permission to play notification sounds.
  final bool sound;

  /// Requests provisional delivery on Apple platforms.
  final bool provisional;

  /// Requests Siri announcement support on Apple platforms.
  final bool announcement;

  /// Requests CarPlay notification support.
  final bool carPlay;

  /// Requests critical alerts. This also requires the Apple entitlement.
  final bool criticalAlert;

  /// Converts these options to a JSON-compatible map.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'alert': alert,
    'badge': badge,
    'sound': sound,
    'provisional': provisional,
    'announcement': announcement,
    'carPlay': carPlay,
    'criticalAlert': criticalAlert,
  };

  /// Recreates permission options from a serialized map.
  factory NotificationPermissionOptions.fromMap(Map<String, dynamic> map) {
    return NotificationPermissionOptions(
      alert: map['alert'] as bool? ?? true,
      badge: map['badge'] as bool? ?? true,
      sound: map['sound'] as bool? ?? true,
      provisional: map['provisional'] as bool? ?? false,
      announcement: map['announcement'] as bool? ?? false,
      carPlay: map['carPlay'] as bool? ?? false,
      criticalAlert: map['criticalAlert'] as bool? ?? false,
    );
  }
}
