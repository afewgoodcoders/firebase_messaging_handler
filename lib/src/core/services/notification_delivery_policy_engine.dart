import 'dart:async';

import '../../models/export.dart';
import '../interfaces/notification_state_store.dart';
import '../managers/notification_preferences_controller.dart';

/// Applies user preferences, quiet hours, frequency limits, and daily caps.
class NotificationDeliveryPolicyEngine {
  /// Creates a policy engine.
  NotificationDeliveryPolicyEngine({
    required this.preferencesController,
    this.policy = const NotificationDeliveryPolicy(),
    this.stateStore,
  });

  /// Source of live user preferences.
  final NotificationPreferencesController preferencesController;

  /// App-defined delivery limits.
  final NotificationDeliveryPolicy policy;

  /// Optional durable storage for interval and daily-cap counters.
  final NotificationStateStore? stateStore;

  static const String _storageKey = 'fmh_v2_delivery_policy_state';

  final Map<String, DateTime> _lastDelivered = <String, DateTime>{};
  final Map<String, int> _dailyCounts = <String, int>{};
  Future<void> _writeSerial = Future<void>.value();

  /// Restores frequency-limit state before the engine starts evaluating work.
  Future<void> restore() async {
    final NotificationStateStore? store = stateStore;
    if (store == null) return;
    final Object? raw = await store.read(_storageKey);
    if (raw is! Map) return;
    final Map<String, dynamic> state = Map<String, dynamic>.from(raw);
    final Object? rawLastDelivered = state['lastDelivered'];
    if (rawLastDelivered is Map) {
      for (final MapEntry<dynamic, dynamic> entry in rawLastDelivered.entries) {
        final DateTime? instant = DateTime.tryParse(entry.value.toString());
        if (instant != null) {
          _lastDelivered[entry.key.toString()] = instant.toLocal();
        }
      }
    }
    final Object? rawDailyCounts = state['dailyCounts'];
    if (rawDailyCounts is Map) {
      for (final MapEntry<dynamic, dynamic> entry in rawDailyCounts.entries) {
        final int? count = int.tryParse(entry.value.toString());
        if (count != null && count >= 0) {
          _dailyCounts[entry.key.toString()] = count;
        }
      }
    }
    _prune(DateTime.now());
  }

  /// Evaluates [request] without incrementing delivery counters.
  NotificationDeliveryDecision evaluate(NotificationDeliveryRequest request) {
    final NotificationPreferences preferences =
        preferencesController.preferences;
    if (!preferences.enabled) {
      return NotificationDeliveryDecision.suppress('notifications_disabled');
    }

    if (!preferences.category(request.categoryId).enabled) {
      return NotificationDeliveryDecision.suppress('category_disabled');
    }

    final DateTime now = request.scheduledAt ?? DateTime.now();
    final NotificationQuietHours? quietHours =
        preferences.quietHours ?? policy.quietHours;
    if (quietHours != null && quietHours.contains(now)) {
      return NotificationDeliveryDecision.defer(
        reason: 'quiet_hours',
        nextEligibleAt: quietHours.nextAllowedTime(now),
      );
    }

    final String surfaceKey = request.surface.name;
    final String categoryKey = '$surfaceKey:${request.categoryId ?? '_'}';
    final DateTime? globalLast = _lastDelivered[surfaceKey];
    if (globalLast != null && policy.globalInterval != null) {
      final DateTime next = globalLast.add(policy.globalInterval!);
      if (now.isBefore(next)) {
        return NotificationDeliveryDecision.defer(
          reason: 'global_interval',
          nextEligibleAt: next,
        );
      }
    }

    final DateTime? categoryLast = _lastDelivered[categoryKey];
    if (categoryLast != null && policy.perCategoryInterval != null) {
      final DateTime next = categoryLast.add(policy.perCategoryInterval!);
      if (now.isBefore(next)) {
        return NotificationDeliveryDecision.defer(
          reason: 'category_interval',
          nextEligibleAt: next,
        );
      }
    }

    final String day = _dayKey(now);
    if (policy.globalDailyCap != null &&
        (_dailyCounts['$day:$surfaceKey'] ?? 0) >= policy.globalDailyCap!) {
      return NotificationDeliveryDecision.defer(
        reason: 'global_daily_cap',
        nextEligibleAt: _nextDay(now),
      );
    }
    if (policy.perCategoryDailyCap != null &&
        (_dailyCounts['$day:$categoryKey'] ?? 0) >=
            policy.perCategoryDailyCap!) {
      return NotificationDeliveryDecision.defer(
        reason: 'category_daily_cap',
        nextEligibleAt: _nextDay(now),
      );
    }

    return NotificationDeliveryDecision.allow;
  }

  /// Records a successful delivery after the destination accepts it.
  void registerDelivery(NotificationDeliveryRequest request) {
    final DateTime now = request.scheduledAt ?? DateTime.now();
    final String surfaceKey = request.surface.name;
    final String categoryKey = '$surfaceKey:${request.categoryId ?? '_'}';
    final String day = _dayKey(now);
    _lastDelivered[surfaceKey] = now;
    _lastDelivered[categoryKey] = now;
    _dailyCounts.update(
      '$day:$surfaceKey',
      (int value) => value + 1,
      ifAbsent: () => 1,
    );
    _dailyCounts.update(
      '$day:$categoryKey',
      (int value) => value + 1,
      ifAbsent: () => 1,
    );
    _prune(now);
    unawaited(_persist());
  }

  Future<void> _persist() {
    final NotificationStateStore? store = stateStore;
    if (store == null) return Future<void>.value();
    _writeSerial = _writeSerial.then((_) {
      return store.write(_storageKey, <String, Object>{
        'lastDelivered': _lastDelivered.map(
          (String key, DateTime value) =>
              MapEntry<String, String>(key, value.toUtc().toIso8601String()),
        ),
        'dailyCounts': Map<String, int>.from(_dailyCounts),
      });
    });
    return _writeSerial;
  }

  /// Waits for pending persistence. Primarily useful in tests and shutdown.
  Future<void> flush() => _writeSerial;

  void _prune(DateTime now) {
    final String today = _dayKey(now);
    _dailyCounts.removeWhere((String key, int value) => !key.startsWith(today));
  }

  static String _dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime _nextDay(DateTime date) =>
      DateTime(date.year, date.month, date.day).add(const Duration(days: 1));
}
