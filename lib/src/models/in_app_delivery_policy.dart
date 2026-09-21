/// Defines a quiet-hours window during which in-app presentation should be
/// deferred.
class InAppQuietHours {
  /// Creates a quiet-hours rule.
  const InAppQuietHours({
    required this.startHour,
    this.startMinute = 0,
    required this.endHour,
    this.endMinute = 0,
  });

  /// Start hour in 24-hour time.
  final int startHour;

  /// Optional start minute.
  final int startMinute;

  /// End hour in 24-hour time.
  final int endHour;

  /// Optional end minute.
  final int endMinute;

  /// Returns true when [now] falls inside the quiet-hours window.
  bool isQuiet(DateTime now) {
    final int currentMinutes = now.hour * 60 + now.minute;
    final int start = startHour * 60 + startMinute;
    final int end = endHour * 60 + endMinute;

    if (start == end) {
      return false;
    }

    if (start < end) {
      return currentMinutes >= start && currentMinutes < end;
    }

    return currentMinutes >= start || currentMinutes < end;
  }

  /// Returns the next time presentation is allowed for the provided moment.
  DateTime nextAllowedTime(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime endTime = today.add(
      Duration(hours: endHour, minutes: endMinute),
    );

    if (!isQuiet(now)) {
      return now;
    }

    if (startHour < endHour ||
        (startHour == endHour && startMinute < endMinute)) {
      if (now.isBefore(endTime)) {
        return endTime;
      }
      return endTime.add(const Duration(days: 1));
    }

    return endTime;
  }
}

/// Result of evaluating whether an in-app message may be shown now.
class InAppDeliveryDecision {
  const InAppDeliveryDecision._({
    required this.allowed,
    this.nextEligibleAt,
    this.reason,
  });

  /// Whether the message may be shown immediately.
  final bool allowed;

  /// Next time the message would be allowed, when deferred.
  final DateTime? nextEligibleAt;

  /// Human-readable reason for deferral.
  final String? reason;

  /// Successful decision indicating immediate display is allowed.
  static const InAppDeliveryDecision allow = InAppDeliveryDecision._(
    allowed: true,
  );

  /// Creates a deferred decision with the next eligible time.
  factory InAppDeliveryDecision.defer({
    required DateTime nextEligibleAt,
    String? reason,
  }) => InAppDeliveryDecision._(
    allowed: false,
    nextEligibleAt: nextEligibleAt,
    reason: reason,
  );
}

/// Global policy used to throttle or defer in-app notification presentation.
class InAppDeliveryPolicy {
  /// Creates a delivery policy.
  const InAppDeliveryPolicy({
    this.globalInterval,
    this.perTemplateInterval,
    this.globalDailyCap,
    this.perTemplateDailyCap,
    this.quietHours,
  });

  /// Minimum interval between any two in-app messages.
  final Duration? globalInterval;

  /// Minimum interval between messages of the same template.
  final Duration? perTemplateInterval;

  /// Maximum number of in-app messages allowed per day globally.
  final int? globalDailyCap;

  /// Maximum number of in-app messages allowed per template per day.
  final int? perTemplateDailyCap;

  /// Quiet-hours window for deferring presentation.
  final InAppQuietHours? quietHours;
}

/// Mutable counters used to evaluate [InAppDeliveryPolicy] decisions.
class InAppDeliveryStats {
  /// Creates a stats bucket, optionally seeded from persisted values.
  InAppDeliveryStats({this.lastShown, Map<String, int>? perDayCounts})
    : perDayCounts = perDayCounts ?? <String, int>{};

  /// Last time any message covered by these stats was shown.
  DateTime? lastShown;

  /// Per-day delivery counts keyed by calendar day.
  final Map<String, int> perDayCounts;

  /// Registers a successful display event.
  void register(DateTime now) {
    lastShown = now;
    final String key = _dateKey(now);
    _pruneOldEntries(now);
    perDayCounts.update(key, (value) => value + 1, ifAbsent: () => 1);
  }

  /// Returns the count recorded for the calendar day containing [day].
  int countForDay(DateTime day) {
    return perDayCounts[_dateKey(day)] ?? 0;
  }

  void _pruneOldEntries(DateTime now) {
    final DateTime threshold = now.subtract(const Duration(days: 7));
    final Iterable<String> staleKeys = perDayCounts.keys.where((String key) {
      final DateTime parsed = DateTime.tryParse(key) ?? now;
      return parsed.isBefore(threshold);
    }).toList();
    for (final String key in staleKeys) {
      perDayCounts.remove(key);
    }
  }

  static String _dateKey(DateTime date) =>
      DateTime(date.year, date.month, date.day).toIso8601String();
}
