import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders and updates notification preferences', (
    WidgetTester tester,
  ) async {
    bool openedSettings = false;
    final InMemoryNotificationPreferencesRepository repository =
        InMemoryNotificationPreferencesRepository();
    final NotificationPreferencesController controller =
        NotificationPreferencesController(
          repository: repository,
          categories: const <NotificationCategory>[
            NotificationCategory(
              id: 'orders',
              name: 'Order updates',
              description: 'Shipping and delivery alerts',
            ),
          ],
          openSystemSettings: () async {
            openedSettings = true;
            return true;
          },
        );
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationPreferenceCenter(controller: controller),
        ),
      ),
    );

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Order updates'), findsOneWidget);
    expect(find.text('Shipping and delivery alerts'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('notifications-enabled')),
    );
    await tester.pumpAndSettle();
    expect(repository.value?.enabled, isFalse);

    final Finder settingsButton = find.byKey(
      const ValueKey<String>('open-notification-settings'),
    );
    await tester.scrollUntilVisible(settingsButton, 200);
    await tester.tap(settingsButton);
    await tester.pump();
    expect(openedSettings, isTrue);
  });
}
