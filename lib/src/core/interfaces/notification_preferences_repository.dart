import '../../models/notification_preferences.dart';

/// Persistence boundary for user-controlled notification preferences.
abstract class NotificationPreferencesRepository {
  /// Loads saved preferences, or null when the user has not saved any.
  Future<NotificationPreferences?> load();

  /// Persists [preferences].
  Future<void> save(NotificationPreferences preferences);

  /// Removes persisted preferences.
  Future<void> clear();
}
