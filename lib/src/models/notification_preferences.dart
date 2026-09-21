import 'notification_category.dart';
import 'notification_delivery_policy.dart';

/// Persisted notification controls selected by the user.
class NotificationPreferences {
  /// Creates notification preferences.
  const NotificationPreferences({
    this.enabled = true,
    this.categories = const <String, NotificationCategoryPreference>{},
    this.quietHours,
  });

  /// Global notification switch.
  final bool enabled;

  /// Per-category preferences keyed by category identifier.
  final Map<String, NotificationCategoryPreference> categories;

  /// User-selected quiet hours, which override the app policy.
  final NotificationQuietHours? quietHours;

  /// Returns preferences for [categoryId], falling back to enabled defaults.
  NotificationCategoryPreference category(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) {
      return const NotificationCategoryPreference();
    }
    return categories[categoryId] ?? const NotificationCategoryPreference();
  }

  /// Creates a copy with selected values replaced.
  NotificationPreferences copyWith({
    bool? enabled,
    Map<String, NotificationCategoryPreference>? categories,
    NotificationQuietHours? quietHours,
    bool clearQuietHours = false,
  }) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      categories: categories ?? this.categories,
      quietHours: clearQuietHours ? null : quietHours ?? this.quietHours,
    );
  }

  /// Converts this value to JSON-compatible data.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'enabled': enabled,
    'categories': categories.map(
      (String key, NotificationCategoryPreference value) =>
          MapEntry<String, dynamic>(key, value.toMap()),
    ),
    'quietHours': quietHours?.toMap(),
  };

  /// Recreates preferences from JSON-compatible data.
  factory NotificationPreferences.fromMap(Map<String, dynamic> map) {
    final Map<dynamic, dynamic> rawCategories =
        map['categories'] as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
    final dynamic rawQuietHours = map['quietHours'];
    return NotificationPreferences(
      enabled: map['enabled'] as bool? ?? true,
      categories: rawCategories.map(
        (dynamic key, dynamic value) =>
            MapEntry<String, NotificationCategoryPreference>(
              key.toString(),
              NotificationCategoryPreference.fromMap(
                Map<String, dynamic>.from(value as Map),
              ),
            ),
      ),
      quietHours: rawQuietHours is Map
          ? NotificationQuietHours.fromMap(
              Map<String, dynamic>.from(rawQuietHours),
            )
          : null,
    );
  }
}
