import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/firebase_messaging_handler_constants.dart';
import '../../models/notification_inbox_item.dart';
import '../interfaces/notification_inbox_storage_interface.dart';

class InboxStorageService implements NotificationInboxStorageInterface {
  InboxStorageService({SharedPreferences? preferences, int maxItems = 100})
    : _prefsFuture = preferences != null
          ? Future<SharedPreferences>.value(preferences)
          : SharedPreferences.getInstance(),
      _maxItems = maxItems;

  final Future<SharedPreferences> _prefsFuture;
  final int _maxItems;
  static const int _defaultPageSize = 20;

  @override
  Future<List<NotificationInboxItem>> fetch({
    int page = 0,
    int pageSize = _defaultPageSize,
  }) async {
    final List<NotificationInboxItem> items = await _readAll();
    final int safePage = page < 0 ? 0 : page;
    final int safeSize = pageSize <= 0 ? _defaultPageSize : pageSize;
    final int start = safePage * safeSize;
    if (start >= items.length) {
      return <NotificationInboxItem>[];
    }
    final int end = (start + safeSize) > items.length
        ? items.length
        : start + safeSize;
    return items.sublist(start, end);
  }

  @override
  Future<void> upsert(NotificationInboxItem item) async {
    final List<NotificationInboxItem> items = await _readAll();
    final List<NotificationInboxItem> filtered = items
        .where((NotificationInboxItem existing) => existing.id != item.id)
        .toList();
    filtered.add(item);
    filtered.sort(
      (NotificationInboxItem a, NotificationInboxItem b) =>
          b.timestamp.compareTo(a.timestamp),
    );
    if (filtered.length > _maxItems) {
      filtered.removeRange(_maxItems, filtered.length);
    }
    await _writeAll(filtered);
  }

  @override
  Future<void> upsertAll(List<NotificationInboxItem> items) async {
    if (items.isEmpty) {
      return;
    }
    final List<NotificationInboxItem> current = await _readAll();
    final Map<String, NotificationInboxItem> merged =
        <String, NotificationInboxItem>{
          for (final NotificationInboxItem item in current) item.id: item,
        };
    for (final NotificationInboxItem item in items) {
      merged[item.id] = item;
    }
    final List<NotificationInboxItem> ordered = merged.values.toList()
      ..sort(
        (NotificationInboxItem a, NotificationInboxItem b) =>
            b.timestamp.compareTo(a.timestamp),
      );
    if (ordered.length > _maxItems) {
      ordered.removeRange(_maxItems, ordered.length);
    }
    await _writeAll(ordered);
  }

  @override
  Future<void> markRead(List<String> ids, {bool isRead = true}) async {
    if (ids.isEmpty) {
      return;
    }
    final List<NotificationInboxItem> items = await _readAll();
    final Set<String> targetIds = ids.toSet();
    final List<NotificationInboxItem> updated = items
        .map(
          (NotificationInboxItem item) => targetIds.contains(item.id)
              ? item.copyWith(isRead: isRead)
              : item,
        )
        .toList();
    await _writeAll(updated);
  }

  @override
  Future<void> delete(List<String> ids) async {
    if (ids.isEmpty) {
      return;
    }
    final Set<String> targetIds = ids.toSet();
    final List<NotificationInboxItem> items = await _readAll();
    final List<NotificationInboxItem> remaining = items
        .where((NotificationInboxItem item) => !targetIds.contains(item.id))
        .toList();
    await _writeAll(remaining);
  }

  @override
  Future<void> clear() async {
    final SharedPreferences prefs = await _prefsFuture;
    await prefs.remove(FirebaseMessagingHandlerConstants.inboxItemsPrefKey);
  }

  @override
  Future<int> count({bool unreadOnly = false}) async {
    final List<NotificationInboxItem> items = await _readAll();
    if (!unreadOnly) {
      return items.length;
    }
    return items.where((NotificationInboxItem item) => !item.isRead).length;
  }

  Future<List<NotificationInboxItem>> _readAll() async {
    try {
      final SharedPreferences prefs = await _prefsFuture;
      final String? stored = prefs.getString(
        FirebaseMessagingHandlerConstants.inboxItemsPrefKey,
      );
      if (stored == null) {
        return <NotificationInboxItem>[];
      }
      final List<dynamic> decoded = jsonDecode(stored) as List<dynamic>;
      final List<NotificationInboxItem> items = decoded
          .map(
            (dynamic item) => NotificationInboxItem.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      items.sort(
        (NotificationInboxItem a, NotificationInboxItem b) =>
            b.timestamp.compareTo(a.timestamp),
      );
      return items;
    } catch (error, stackTrace) {
      _log('[InboxStorage] read error: $error');
      _log('[InboxStorage] $stackTrace');
      return <NotificationInboxItem>[];
    }
  }

  Future<void> _writeAll(List<NotificationInboxItem> items) async {
    try {
      final SharedPreferences prefs = await _prefsFuture;
      final List<Map<String, dynamic>> encoded = items
          .map((NotificationInboxItem item) => item.toMap())
          .toList();
      await prefs.setString(
        FirebaseMessagingHandlerConstants.inboxItemsPrefKey,
        jsonEncode(encoded),
      );
    } catch (error, stackTrace) {
      _log('[InboxStorage] write error: $error');
      _log('[InboxStorage] $stackTrace');
    }
  }

  void _log(String message) {
    debugPrint(message);
  }
}

class InMemoryInboxStorage implements NotificationInboxStorageInterface {
  InMemoryInboxStorage({int pageSize = 20}) : _pageSize = pageSize;

  final List<NotificationInboxItem> _items = <NotificationInboxItem>[];
  final int _pageSize;

  @override
  Future<List<NotificationInboxItem>> fetch({
    int page = 0,
    int pageSize = 20,
  }) async {
    final int safePage = page < 0 ? 0 : page;
    final int safeSize = pageSize <= 0 ? _pageSize : pageSize;
    final int start = safePage * safeSize;
    if (start >= _items.length) {
      return <NotificationInboxItem>[];
    }
    final int end = (start + safeSize) > _items.length
        ? _items.length
        : start + safeSize;
    return _items.sublist(start, end);
  }

  @override
  Future<void> upsert(NotificationInboxItem item) async {
    _items.removeWhere((NotificationInboxItem entry) => entry.id == item.id);
    _items.add(item);
    _items.sort(
      (NotificationInboxItem a, NotificationInboxItem b) =>
          b.timestamp.compareTo(a.timestamp),
    );
  }

  @override
  Future<void> upsertAll(List<NotificationInboxItem> items) async {
    for (final NotificationInboxItem item in items) {
      _items.removeWhere((NotificationInboxItem entry) => entry.id == item.id);
      _items.add(item);
    }
    _items.sort(
      (NotificationInboxItem a, NotificationInboxItem b) =>
          b.timestamp.compareTo(a.timestamp),
    );
  }

  @override
  Future<void> markRead(List<String> ids, {bool isRead = true}) async {
    final Set<String> targetIds = ids.toSet();
    for (int i = 0; i < _items.length; i++) {
      final NotificationInboxItem item = _items[i];
      if (targetIds.contains(item.id)) {
        _items[i] = item.copyWith(isRead: isRead);
      }
    }
  }

  @override
  Future<void> delete(List<String> ids) async {
    final Set<String> targetIds = ids.toSet();
    _items.removeWhere((NotificationInboxItem item) {
      return targetIds.contains(item.id);
    });
  }

  @override
  Future<void> clear() async {
    _items.clear();
  }

  @override
  Future<int> count({bool unreadOnly = false}) async {
    if (!unreadOnly) {
      return _items.length;
    }
    return _items.where((NotificationInboxItem item) => !item.isRead).length;
  }
}
