import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStateStore implements NotificationStateStore {
  final Map<String, Object?> values = <String, Object?>{};

  @override
  Future<Object?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> write(String key, Object? value) async {
    values[key] = value;
  }
}

void main() {
  group('NotificationDeliveryPolicyEngine', () {
    test(
      'suppresses globally disabled and category-disabled delivery',
      () async {
        final InMemoryNotificationPreferencesRepository repository =
            InMemoryNotificationPreferencesRepository(
              const NotificationPreferences(enabled: false),
            );
        final NotificationPreferencesController controller =
            NotificationPreferencesController(repository: repository);
        await controller.load();
        final NotificationDeliveryPolicyEngine engine =
            NotificationDeliveryPolicyEngine(preferencesController: controller);
        const NotificationDeliveryRequest request = NotificationDeliveryRequest(
          surface: NotificationDeliverySurface.local,
          lifecycle: NotificationLifecycle.foreground,
          messageId: 'global-off',
          categoryId: 'marketing',
        );

        expect(engine.evaluate(request).reason, 'notifications_disabled');

        await controller.setEnabled(true);
        await controller.setCategoryEnabled('marketing', false);
        expect(engine.evaluate(request).reason, 'category_disabled');
      },
    );

    test('defers delivery until cross-midnight quiet hours end', () async {
      final NotificationPreferencesController controller =
          NotificationPreferencesController(
            repository: InMemoryNotificationPreferencesRepository(),
          );
      await controller.load();
      final NotificationDeliveryPolicyEngine engine =
          NotificationDeliveryPolicyEngine(
            preferencesController: controller,
            policy: const NotificationDeliveryPolicy(
              quietHours: NotificationQuietHours(startHour: 22, endHour: 7),
            ),
          );
      final DateTime scheduledAt = DateTime(2026, 9, 20, 23, 30);
      final NotificationDeliveryDecision decision = engine.evaluate(
        NotificationDeliveryRequest(
          surface: NotificationDeliverySurface.inApp,
          lifecycle: NotificationLifecycle.foreground,
          messageId: 'quiet-hours',
          scheduledAt: scheduledAt,
        ),
      );

      expect(decision.outcome, NotificationDeliveryOutcome.deferred);
      expect(decision.reason, 'quiet_hours');
      expect(decision.nextEligibleAt, DateTime(2026, 9, 21, 7));
    });

    test('tracks interval and daily caps per surface and category', () async {
      final NotificationPreferencesController controller =
          NotificationPreferencesController(
            repository: InMemoryNotificationPreferencesRepository(),
          );
      await controller.load();
      final NotificationDeliveryPolicyEngine engine =
          NotificationDeliveryPolicyEngine(
            preferencesController: controller,
            policy: const NotificationDeliveryPolicy(
              perCategoryInterval: Duration(hours: 1),
              perCategoryDailyCap: 2,
            ),
          );

      NotificationDeliveryRequest requestAt(DateTime time) =>
          NotificationDeliveryRequest(
            surface: NotificationDeliverySurface.inbox,
            lifecycle: NotificationLifecycle.background,
            messageId: time.toIso8601String(),
            categoryId: 'orders',
            scheduledAt: time,
          );

      final NotificationDeliveryRequest first = requestAt(
        DateTime(2026, 9, 20, 9),
      );
      engine.registerDelivery(first);

      final NotificationDeliveryDecision intervalDecision = engine.evaluate(
        requestAt(DateTime(2026, 9, 20, 9, 30)),
      );
      expect(intervalDecision.reason, 'category_interval');

      final NotificationDeliveryRequest second = requestAt(
        DateTime(2026, 9, 20, 10),
      );
      expect(engine.evaluate(second).isAllowed, isTrue);
      engine.registerDelivery(second);

      final NotificationDeliveryDecision capDecision = engine.evaluate(
        requestAt(DateTime(2026, 9, 20, 12)),
      );
      expect(capDecision.reason, 'category_daily_cap');
      expect(capDecision.nextEligibleAt, DateTime(2026, 9, 21));
    });

    test('restores frequency counters after a process restart', () async {
      final _MemoryStateStore state = _MemoryStateStore();
      final NotificationPreferencesController controller =
          NotificationPreferencesController(
            repository: InMemoryNotificationPreferencesRepository(),
          );
      await controller.load();
      const NotificationDeliveryPolicy policy = NotificationDeliveryPolicy(
        perCategoryDailyCap: 1,
      );
      final NotificationDeliveryPolicyEngine first =
          NotificationDeliveryPolicyEngine(
            preferencesController: controller,
            policy: policy,
            stateStore: state,
          );
      final DateTime today = DateTime.now();
      final DateTime instant = DateTime(today.year, today.month, today.day, 10);
      first.registerDelivery(
        NotificationDeliveryRequest(
          surface: NotificationDeliverySurface.push,
          lifecycle: NotificationLifecycle.background,
          messageId: 'first',
          categoryId: 'orders',
          scheduledAt: instant,
        ),
      );
      await first.flush();

      final NotificationDeliveryPolicyEngine restored =
          NotificationDeliveryPolicyEngine(
            preferencesController: controller,
            policy: policy,
            stateStore: state,
          );
      await restored.restore();
      final NotificationDeliveryDecision decision = restored.evaluate(
        NotificationDeliveryRequest(
          surface: NotificationDeliverySurface.push,
          lifecycle: NotificationLifecycle.background,
          messageId: 'second',
          categoryId: 'orders',
          scheduledAt: instant.add(const Duration(hours: 1)),
        ),
      );

      expect(decision.reason, 'category_daily_cap');
    });
  });
}
