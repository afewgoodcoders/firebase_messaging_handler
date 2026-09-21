import '../../models/notification_inbox_item.dart';

/// Persistence abstraction used by `NotificationInboxView` and inbox services.
abstract class NotificationInboxStorageInterface {
  /// Returns a page of inbox items ordered newest-first.
  Future<List<NotificationInboxItem>> fetch({int page = 0, int pageSize = 20});

  /// Inserts or updates a single inbox item.
  Future<void> upsert(NotificationInboxItem item);

  /// Inserts or updates multiple inbox items.
  Future<void> upsertAll(List<NotificationInboxItem> items);

  /// Marks the provided items as read or unread.
  Future<void> markRead(List<String> ids, {bool isRead = true});

  /// Deletes the provided inbox item identifiers.
  Future<void> delete(List<String> ids);

  /// Removes all stored inbox items.
  Future<void> clear();

  /// Returns the total item count, optionally restricted to unread items.
  Future<int> count({bool unreadOnly = false});
}
