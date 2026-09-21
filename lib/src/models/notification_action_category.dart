import 'notification_data.dart';

/// A registered Apple notification category and its available actions.
///
/// Categories must be known during initialization so iOS can expose actions
/// while the application is suspended or terminated.
class NotificationActionCategory {
  /// Creates a notification action category.
  const NotificationActionCategory({required this.id, required this.actions});

  /// Stable category identifier referenced by notification payloads.
  final String id;

  /// Actions available for notifications in this category.
  final List<NotificationAction> actions;

  /// Converts this category to a JSON-compatible map.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'actions': actions
        .map((NotificationAction action) => action.toMap())
        .toList(),
  };

  /// Recreates a category from a serialized map.
  factory NotificationActionCategory.fromMap(Map<String, dynamic> map) {
    return NotificationActionCategory(
      id: map['id']?.toString() ?? '',
      actions:
          (map['actions'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (Map<dynamic, dynamic> action) => NotificationAction.fromMap(
                  Map<String, dynamic>.from(action),
                ),
              )
              .toList() ??
          const <NotificationAction>[],
    );
  }
}
