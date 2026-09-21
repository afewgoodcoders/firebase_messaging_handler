/// Describes a user-controllable class of notifications.
class NotificationCategory {
  /// Creates a notification category.
  const NotificationCategory({
    required this.id,
    required this.name,
    this.description,
    this.defaultEnabled = true,
    this.supportsSound = true,
    this.supportsBadge = true,
  });

  /// Stable identifier sent in a payload's `category` field.
  final String id;

  /// User-facing category name.
  final String name;

  /// Optional explanation shown in a preference center.
  final String? description;

  /// Whether the category starts enabled before a user changes it.
  final bool defaultEnabled;

  /// Whether users may control sound for this category.
  final bool supportsSound;

  /// Whether users may control app badge updates for this category.
  final bool supportsBadge;
}

/// User preferences for one [NotificationCategory].
class NotificationCategoryPreference {
  /// Creates category preferences.
  const NotificationCategoryPreference({
    this.enabled = true,
    this.soundEnabled = true,
    this.badgeEnabled = true,
  });

  /// Whether delivery is enabled on all package-managed surfaces.
  final bool enabled;

  /// Whether notification sound is enabled.
  final bool soundEnabled;

  /// Whether app badge updates are enabled.
  final bool badgeEnabled;

  /// Creates a copy with selected values replaced.
  NotificationCategoryPreference copyWith({
    bool? enabled,
    bool? soundEnabled,
    bool? badgeEnabled,
  }) {
    return NotificationCategoryPreference(
      enabled: enabled ?? this.enabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      badgeEnabled: badgeEnabled ?? this.badgeEnabled,
    );
  }

  /// Converts this value to JSON-compatible data.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'enabled': enabled,
    'soundEnabled': soundEnabled,
    'badgeEnabled': badgeEnabled,
  };

  /// Recreates preferences from JSON-compatible data.
  factory NotificationCategoryPreference.fromMap(Map<String, dynamic> map) {
    return NotificationCategoryPreference(
      enabled: map['enabled'] as bool? ?? true,
      soundEnabled: map['soundEnabled'] as bool? ?? true,
      badgeEnabled: map['badgeEnabled'] as bool? ?? true,
    );
  }
}
