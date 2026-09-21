import 'package:alchemist/alchemist.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:flutter/material.dart';

class _FakeStorage implements NotificationInboxStorageInterface {
  _FakeStorage(this._items);

  final List<NotificationInboxItem> _items;

  @override
  Future<int> count({bool unreadOnly = false}) async {
    if (!unreadOnly) return _items.length;
    return _items.where((NotificationInboxItem item) => !item.isRead).length;
  }

  @override
  Future<void> clear() async {
    _items.clear();
  }

  @override
  Future<List<NotificationInboxItem>> fetch({
    int page = 0,
    int pageSize = 20,
  }) async {
    final int start = page * pageSize;
    if (start >= _items.length) return <NotificationInboxItem>[];
    final int end = (start + pageSize) > _items.length
        ? _items.length
        : start + pageSize;
    return _items.sublist(start, end);
  }

  @override
  Future<void> delete(List<String> ids) async {
    _items.removeWhere((NotificationInboxItem item) => ids.contains(item.id));
  }

  @override
  Future<void> markRead(List<String> ids, {bool isRead = true}) async {
    final Set<String> target = ids.toSet();
    for (int i = 0; i < _items.length; i++) {
      if (target.contains(_items[i].id)) {
        _items[i] = _items[i].copyWith(isRead: isRead);
      }
    }
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
      await upsert(item);
    }
  }
}

void main() {
  final List<NotificationInboxItem> seeded = <NotificationInboxItem>[
    NotificationInboxItem(
      id: 'welcome',
      title: 'Welcome to the inbox',
      body: 'Swipe to delete, tap to mark as read.',
      timestamp: DateTime(2024, 12, 5, 10, 0),
      isRead: false,
      actions: const <NotificationAction>[
        NotificationAction(id: 'open', title: 'Open'),
      ],
    ),
    NotificationInboxItem(
      id: 'promo',
      title: '50% off today only',
      body: 'Upgrade before midnight to lock the price.',
      timestamp: DateTime(2024, 12, 4, 15, 30),
      isRead: true,
    ),
  ];

  goldenTest(
    'inbox renders seeded items with theming',
    fileName: 'inbox_seeded.png',
    builder: () => MaterialApp(
      home: Scaffold(
        body: NotificationInboxView(
          storage: _FakeStorage(seeded),
          theme: NotificationInboxTheme(
            unreadTitleStyle: const TextStyle(fontWeight: FontWeight.bold),
            subtitleStyle: const TextStyle(color: Colors.grey),
          ),
          enableSwipeToDelete: false,
        ),
      ),
    ),
  );

  goldenTest(
    'inbox renders empty state in dark mode',
    fileName: 'inbox_empty_dark.png',
    builder: () => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: NotificationInboxView(
          storage: _FakeStorage(<NotificationInboxItem>[]),
          theme: const NotificationInboxTheme(
            emptyState: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nothing here yet'),
              ),
            ),
          ),
          enableSwipeToDelete: false,
        ),
      ),
    ),
  );
}
