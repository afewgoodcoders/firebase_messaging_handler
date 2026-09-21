import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('InboxStorageService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('upsert orders by timestamp desc and marks read', () async {
      final storage = InboxStorageService();
      final now = DateTime.now();
      await storage.upsert(
        NotificationInboxItem(
          id: 'b',
          title: 'Second',
          body: 'Body',
          timestamp: now.subtract(const Duration(minutes: 5)),
        ),
      );
      await storage.upsert(
        NotificationInboxItem(
          id: 'a',
          title: 'First',
          body: 'Body',
          timestamp: now,
        ),
      );

      final items = await storage.fetch(page: 0, pageSize: 10);
      expect(items.first.id, 'a');

      await storage.markRead(<String>['a']);
      final updated = await storage.fetch(page: 0, pageSize: 10);
      expect(updated.first.isRead, isTrue);
    });

    test('delete removes items and pagination respects bounds', () async {
      final storage = InboxStorageService();
      final now = DateTime.now();
      for (int i = 0; i < 5; i++) {
        await storage.upsert(
          NotificationInboxItem(
            id: 'id_$i',
            title: 'Title $i',
            body: 'Body $i',
            timestamp: now.subtract(Duration(minutes: i)),
          ),
        );
      }

      await storage.delete(<String>['id_0', 'id_1']);
      final remaining = await storage.fetch(page: 0, pageSize: 10);
      expect(remaining.length, 3);

      final page1 = await storage.fetch(page: 0, pageSize: 2);
      expect(page1.length, 2);
      final page2 = await storage.fetch(page: 1, pageSize: 2);
      expect(page2.length, 1);
    });
  });

  group('InMemoryInboxStorage', () {
    test('upsert and pagination', () async {
      final storage = InMemoryInboxStorage();
      final now = DateTime.now();
      await storage.upsert(
        NotificationInboxItem(id: 'x', title: 'X', body: 'B', timestamp: now),
      );
      await storage.upsert(
        NotificationInboxItem(
          id: 'y',
          title: 'Y',
          body: 'B',
          timestamp: now.subtract(const Duration(seconds: 1)),
        ),
      );

      final firstPage = await storage.fetch(page: 0, pageSize: 1);
      expect(firstPage.single.id, 'x');

      final count = await storage.count();
      expect(count, 2);
    });
  });
}
