import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationPreferencesController', () {
    test(
      'merges saved values with defaults for newly added categories',
      () async {
        final InMemoryNotificationPreferencesRepository repository =
            InMemoryNotificationPreferencesRepository(
              const NotificationPreferences(
                categories: <String, NotificationCategoryPreference>{
                  'orders': NotificationCategoryPreference(soundEnabled: false),
                },
              ),
            );
        final NotificationPreferencesController controller =
            NotificationPreferencesController(
              repository: repository,
              categories: const <NotificationCategory>[
                NotificationCategory(id: 'orders', name: 'Orders'),
                NotificationCategory(
                  id: 'marketing',
                  name: 'Marketing',
                  defaultEnabled: false,
                ),
              ],
            );

        await controller.load();

        expect(controller.preferences.category('orders').soundEnabled, isFalse);
        expect(controller.preferences.category('marketing').enabled, isFalse);
      },
    );

    test('persists mutations and delegates system settings', () async {
      bool openedSettings = false;
      final InMemoryNotificationPreferencesRepository repository =
          InMemoryNotificationPreferencesRepository();
      final NotificationPreferencesController controller =
          NotificationPreferencesController(
            repository: repository,
            openSystemSettings: () async {
              openedSettings = true;
              return true;
            },
          );
      await controller.load();

      await controller.setCategoryBadgeEnabled('news', false);
      await controller.setQuietHours(
        const NotificationQuietHours(startHour: 21, endHour: 6),
      );

      expect(repository.value?.category('news').badgeEnabled, isFalse);
      expect(repository.value?.quietHours?.startHour, 21);
      expect(await controller.openSystemSettings(), isTrue);
      expect(openedSettings, isTrue);
    });
  });
}
