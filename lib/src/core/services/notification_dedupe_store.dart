import '../interfaces/notification_state_store.dart';

/// Durable idempotency ledger shared by foreground and background isolates.
class NotificationDedupeStore {
  /// Creates a deduplication ledger.
  NotificationDedupeStore({
    required NotificationStateStore stateStore,
    this.retention = const Duration(days: 7),
    this.maxEntries = 1000,
  }) : _stateStore = stateStore;

  static const String _storageKey = 'fmh_v2_dedupe_ledger';

  final NotificationStateStore _stateStore;

  /// Maximum age of an idempotency record.
  final Duration retention;

  /// Maximum number of records retained.
  final int maxEntries;

  Future<void> _serial = Future<void>.value();

  /// Returns true when [key] has already been recorded and is still valid.
  /// Otherwise records it atomically within this isolate and returns false.
  Future<bool> checkAndRecord(
    String key, {
    DateTime? now,
    DateTime? expiresAt,
  }) async {
    final DateTime instant = now ?? DateTime.now();
    var duplicate = false;
    _serial = _serial.then((_) async {
      final Object? raw = await _stateStore.read(_storageKey);
      final Map<String, dynamic> ledger = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      ledger.removeWhere((String _, dynamic value) {
        final DateTime? expiry = DateTime.tryParse(value?.toString() ?? '');
        return expiry == null || !expiry.isAfter(instant);
      });
      duplicate = ledger.containsKey(key);
      if (!duplicate) {
        ledger[key] = (expiresAt ?? instant.add(retention))
            .toUtc()
            .toIso8601String();
      }
      if (ledger.length > maxEntries) {
        final List<MapEntry<String, dynamic>> ordered = ledger.entries.toList()
          ..sort(
            (MapEntry<String, dynamic> a, MapEntry<String, dynamic> b) =>
                a.value.toString().compareTo(b.value.toString()),
          );
        for (final MapEntry<String, dynamic> entry in ordered.take(
          ledger.length - maxEntries,
        )) {
          ledger.remove(entry.key);
        }
      }
      await _stateStore.write(_storageKey, ledger);
    });
    await _serial;
    return duplicate;
  }

  /// Clears all idempotency records.
  Future<void> clear() => _stateStore.remove(_storageKey);
}
