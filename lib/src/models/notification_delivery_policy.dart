import '../enums/notification_lifecycle_enum.dart';

/// A daily quiet-hours window in the device's local timezone.
class NotificationQuietHours {
  /// Creates a quiet-hours window.
  const NotificationQuietHours({
    required this.startHour,
    this.startMinute = 0,
    required this.endHour,
    this.endMinute = 0,
  }) : assert(startHour >= 0 && startHour <= 23),
       assert(endHour >= 0 && endHour <= 23),
       assert(startMinute >= 0 && startMinute <= 59),
       assert(endMinute >= 0 && endMinute <= 59);

  /// Start hour in 24-hour time.
  final int startHour;

  /// Start minute.
  final int startMinute;

  /// End hour in 24-hour time.
  final int endHour;

  /// End minute.
  final int endMinute;

  /// Whether [now] falls within this window.
  bool contains(DateTime now) {
    final int current = now.hour * 60 + now.minute;
    final int start = startHour * 60 + startMinute;
    final int end = endHour * 60 + endMinute;
    if (start == end) return false;
    if (start < end) return current >= start && current < end;
    return current >= start || current < end;
  }

  /// The first local time after [now] that is outside this window.
  DateTime nextAllowedTime(DateTime now) {
    if (!contains(now)) return now;
    final DateTime endToday = DateTime(
      now.year,
      now.month,
      now.day,
      endHour,
      endMinute,
    );
    return now.isBefore(endToday)
        ? endToday
        : endToday.add(const Duration(days: 1));
  }

  /// Converts this value to JSON-compatible data.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'startHour': startHour,
    'startMinute': startMinute,
    'endHour': endHour,
    'endMinute': endMinute,
  };

  /// Recreates a quiet-hours window from JSON-compatible data.
  factory NotificationQuietHours.fromMap(Map<String, dynamic> map) {
    return NotificationQuietHours(
      startHour: map['startHour'] as int? ?? 22,
      startMinute: map['startMinute'] as int? ?? 0,
      endHour: map['endHour'] as int? ?? 7,
      endMinute: map['endMinute'] as int? ?? 0,
    );
  }
}

/// A package-managed notification destination.
enum NotificationDeliverySurface {
  /// An FCM or browser/system notification.
  push,

  /// A local notification created by the package.
  local,

  /// An in-app overlay or template.
  inApp,

  /// A persisted notification inbox entry.
  inbox,
}

/// The result of applying delivery controls.
enum NotificationDeliveryOutcome {
  /// Delivery may continue now.
  allowed,

  /// Delivery must not occur.
  suppressed,

  /// Delivery should occur at [NotificationDeliveryDecision.nextEligibleAt].
  deferred,
}

/// Input used to make one delivery decision.
class NotificationDeliveryRequest {
  /// Creates a request.
  const NotificationDeliveryRequest({
    required this.surface,
    required this.lifecycle,
    required this.messageId,
    this.categoryId,
    this.scheduledAt,
    this.data = const <String, dynamic>{},
  });

  /// Destination being evaluated.
  final NotificationDeliverySurface surface;

  /// App lifecycle at receipt time.
  final NotificationLifecycle lifecycle;

  /// Message or local notification identifier.
  final String messageId;

  /// Optional preference category.
  final String? categoryId;

  /// Intended delivery time, or null for immediate delivery.
  final DateTime? scheduledAt;

  /// Original application payload.
  final Map<String, dynamic> data;
}

/// Result returned by a [NotificationDeliveryPolicy] evaluation.
class NotificationDeliveryDecision {
  const NotificationDeliveryDecision._(
    this.outcome, {
    this.reason,
    this.nextEligibleAt,
  });

  /// Decision outcome.
  final NotificationDeliveryOutcome outcome;

  /// Stable, analytics-friendly reason.
  final String? reason;

  /// Earliest suggested delivery time for deferred requests.
  final DateTime? nextEligibleAt;

  /// Whether delivery may continue immediately.
  bool get isAllowed => outcome == NotificationDeliveryOutcome.allowed;

  /// An allowed decision.
  static const NotificationDeliveryDecision allow =
      NotificationDeliveryDecision._(NotificationDeliveryOutcome.allowed);

  /// Creates a suppressed decision.
  factory NotificationDeliveryDecision.suppress(String reason) =>
      NotificationDeliveryDecision._(
        NotificationDeliveryOutcome.suppressed,
        reason: reason,
      );

  /// Creates a deferred decision.
  factory NotificationDeliveryDecision.defer({
    required String reason,
    required DateTime nextEligibleAt,
  }) => NotificationDeliveryDecision._(
    NotificationDeliveryOutcome.deferred,
    reason: reason,
    nextEligibleAt: nextEligibleAt,
  );
}

/// Policy shared by push, local, in-app, and inbox delivery.
class NotificationDeliveryPolicy {
  /// Creates a delivery policy.
  const NotificationDeliveryPolicy({
    this.quietHours,
    this.globalInterval,
    this.perCategoryInterval,
    this.globalDailyCap,
    this.perCategoryDailyCap,
  }) : assert(globalDailyCap == null || globalDailyCap > 0),
       assert(perCategoryDailyCap == null || perCategoryDailyCap > 0);

  /// App-defined quiet hours used when the user has not chosen their own.
  final NotificationQuietHours? quietHours;

  /// Minimum interval between deliveries on the same surface.
  final Duration? globalInterval;

  /// Minimum interval per category and surface.
  final Duration? perCategoryInterval;

  /// Maximum deliveries per surface and calendar day.
  final int? globalDailyCap;

  /// Maximum deliveries per category, surface, and calendar day.
  final int? perCategoryDailyCap;

  /// Converts this policy to JSON-compatible data.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'quietHours': quietHours?.toMap(),
    'globalIntervalSeconds': globalInterval?.inSeconds,
    'perCategoryIntervalSeconds': perCategoryInterval?.inSeconds,
    'globalDailyCap': globalDailyCap,
    'perCategoryDailyCap': perCategoryDailyCap,
  };

  /// Recreates a policy from JSON-compatible data.
  factory NotificationDeliveryPolicy.fromMap(Map<String, dynamic> map) {
    final dynamic rawQuietHours = map['quietHours'];
    final int? globalIntervalSeconds = (map['globalIntervalSeconds'] as num?)
        ?.toInt();
    final int? perCategoryIntervalSeconds =
        (map['perCategoryIntervalSeconds'] as num?)?.toInt();
    return NotificationDeliveryPolicy(
      quietHours: rawQuietHours is Map
          ? NotificationQuietHours.fromMap(
              Map<String, dynamic>.from(rawQuietHours),
            )
          : null,
      globalInterval: globalIntervalSeconds == null
          ? null
          : Duration(seconds: globalIntervalSeconds),
      perCategoryInterval: perCategoryIntervalSeconds == null
          ? null
          : Duration(seconds: perCategoryIntervalSeconds),
      globalDailyCap: (map['globalDailyCap'] as num?)?.toInt(),
      perCategoryDailyCap: (map['perCategoryDailyCap'] as num?)?.toInt(),
    );
  }
}
