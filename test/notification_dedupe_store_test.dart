import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:firebase_messaging_handler/src/core/services/notification_dedupe_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStateStore implements NotificationStateStore {
  final Map<String, Object?> values = <String, Object?>{};

  @override
  Future<Object?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> write(String key, Object? value) async {
    values[key] = value;
  }
}

void main() {
  group('NotificationDedupeStore', () {
    test('persists idempotency across store instances', () async {
      final _MemoryStateStore state = _MemoryStateStore();
      final DateTime now = DateTime.utc(2026, 9, 20);
      final NotificationDedupeStore first = NotificationDedupeStore(
        stateStore: state,
      );
      final NotificationDedupeStore second = NotificationDedupeStore(
        stateStore: state,
      );

      expect(await first.checkAndRecord('message-1', now: now), isFalse);
      expect(await second.checkAndRecord('message-1', now: now), isTrue);
    });

    test('prunes expired entries before checking duplicates', () async {
      final _MemoryStateStore state = _MemoryStateStore();
      final NotificationDedupeStore store = NotificationDedupeStore(
        stateStore: state,
        retention: const Duration(minutes: 5),
      );
      final DateTime first = DateTime.utc(2026, 9, 20, 10);

      expect(await store.checkAndRecord('message-1', now: first), isFalse);
      expect(
        await store.checkAndRecord(
          'message-1',
          now: first.add(const Duration(minutes: 6)),
        ),
        isFalse,
      );
    });

    test('keeps the ledger bounded', () async {
      final _MemoryStateStore state = _MemoryStateStore();
      final NotificationDedupeStore store = NotificationDedupeStore(
        stateStore: state,
        maxEntries: 2,
      );
      final DateTime now = DateTime.utc(2026, 9, 20);

      await store.checkAndRecord('one', now: now);
      await store.checkAndRecord(
        'two',
        now: now.add(const Duration(seconds: 1)),
      );
      await store.checkAndRecord(
        'three',
        now: now.add(const Duration(seconds: 2)),
      );

      final Map<dynamic, dynamic> ledger =
          state.values['fmh_v2_dedupe_ledger']! as Map<dynamic, dynamic>;
      expect(ledger, hasLength(2));
    });
  });
}
