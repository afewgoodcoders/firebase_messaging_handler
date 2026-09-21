import 'dart:async';

import 'package:flutter/material.dart';

import '../core/managers/notification_preferences_controller.dart';
import '../models/export.dart';

/// Ready-made, embeddable UI for notification preferences.
class NotificationPreferenceCenter extends StatelessWidget {
  /// Creates a preference center backed by [controller].
  const NotificationPreferenceCenter({
    required this.controller,
    this.title = 'Notifications',
    this.padding = const EdgeInsets.all(16),
    this.showQuietHours = true,
    this.showSystemSettings = true,
    super.key,
  });

  /// Controller shared with [FirebaseMessagingHandler].
  final NotificationPreferencesController controller;

  /// Heading shown above the controls.
  final String title;

  /// Outer content padding.
  final EdgeInsetsGeometry padding;

  /// Whether to show the built-in quiet-hours control.
  final bool showQuietHours;

  /// Whether to show a shortcut to the operating system's notification page.
  final bool showSystemSettings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        if (controller.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final NotificationPreferences preferences = controller.preferences;
        return ListView(
          padding: padding,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: const ValueKey<String>('notifications-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow notifications'),
              subtitle: const Text(
                'Controls push, local, in-app, and inbox delivery.',
              ),
              value: preferences.enabled,
              onChanged: (bool value) {
                unawaited(controller.setEnabled(value));
              },
            ),
            if (showQuietHours)
              _QuietHoursTile(
                controller: controller,
                enabled: preferences.enabled,
                quietHours: preferences.quietHours,
              ),
            const Divider(height: 32),
            for (final NotificationCategory category in controller.categories)
              _CategoryCard(
                category: category,
                preference: preferences.category(category.id),
                controller: controller,
                globallyEnabled: preferences.enabled,
              ),
            if (showSystemSettings &&
                controller.canOpenSystemSettings) ...<Widget>[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey<String>('open-notification-settings'),
                onPressed: () {
                  unawaited(controller.openSystemSettings());
                },
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open system notification settings'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.preference,
    required this.controller,
    required this.globallyEnabled,
  });

  final NotificationCategory category;
  final NotificationCategoryPreference preference;
  final NotificationPreferencesController controller;
  final bool globallyEnabled;

  @override
  Widget build(BuildContext context) {
    final bool enabled = globallyEnabled && preference.enabled;
    return Card(
      child: Column(
        children: <Widget>[
          SwitchListTile.adaptive(
            key: ValueKey<String>('category-${category.id}-enabled'),
            title: Text(category.name),
            subtitle: category.description == null
                ? null
                : Text(category.description!),
            value: preference.enabled,
            onChanged: globallyEnabled
                ? (bool value) {
                    unawaited(
                      controller.setCategoryEnabled(category.id, value),
                    );
                  }
                : null,
          ),
          if (category.supportsSound)
            CheckboxListTile(
              key: ValueKey<String>('category-${category.id}-sound'),
              title: const Text('Sound'),
              value: preference.soundEnabled,
              onChanged: enabled
                  ? (bool? value) {
                      unawaited(
                        controller.setCategorySoundEnabled(
                          category.id,
                          value ?? false,
                        ),
                      );
                    }
                  : null,
            ),
          if (category.supportsBadge)
            CheckboxListTile(
              key: ValueKey<String>('category-${category.id}-badge'),
              title: const Text('App badge'),
              value: preference.badgeEnabled,
              onChanged: enabled
                  ? (bool? value) {
                      unawaited(
                        controller.setCategoryBadgeEnabled(
                          category.id,
                          value ?? false,
                        ),
                      );
                    }
                  : null,
            ),
        ],
      ),
    );
  }
}

class _QuietHoursTile extends StatelessWidget {
  const _QuietHoursTile({
    required this.controller,
    required this.enabled,
    required this.quietHours,
  });

  final NotificationPreferencesController controller;
  final bool enabled;
  final NotificationQuietHours? quietHours;

  @override
  Widget build(BuildContext context) {
    final NotificationQuietHours value =
        quietHours ?? const NotificationQuietHours(startHour: 22, endHour: 7);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Quiet hours'),
      subtitle: Text(
        quietHours == null
            ? 'Off'
            : '${_hourLabel(context, value.startHour)}–'
                  '${_hourLabel(context, value.endHour)}',
      ),
      children: <Widget>[
        SwitchListTile.adaptive(
          key: const ValueKey<String>('quiet-hours-enabled'),
          title: const Text('Use quiet hours'),
          value: quietHours != null,
          onChanged: enabled
              ? (bool selected) {
                  unawaited(controller.setQuietHours(selected ? value : null));
                }
              : null,
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _HourDropdown(
                label: 'From',
                value: value.startHour,
                enabled: enabled && quietHours != null,
                onChanged: (int hour) {
                  unawaited(
                    controller.setQuietHours(
                      NotificationQuietHours(
                        startHour: hour,
                        startMinute: value.startMinute,
                        endHour: value.endHour,
                        endMinute: value.endMinute,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HourDropdown(
                label: 'Until',
                value: value.endHour,
                enabled: enabled && quietHours != null,
                onChanged: (int hour) {
                  unawaited(
                    controller.setQuietHours(
                      NotificationQuietHours(
                        startHour: value.startHour,
                        startMinute: value.startMinute,
                        endHour: hour,
                        endMinute: value.endMinute,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  static String _hourLabel(BuildContext context, int hour) =>
      TimeOfDay(hour: hour, minute: 0).format(context);
}

class _HourDropdown extends StatelessWidget {
  const _HourDropdown({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: <DropdownMenuItem<int>>[
        for (int hour = 0; hour < 24; hour++)
          DropdownMenuItem<int>(
            value: hour,
            child: Text(TimeOfDay(hour: hour, minute: 0).format(context)),
          ),
      ],
      onChanged: enabled
          ? (int? hour) {
              if (hour != null) onChanged(hour);
            }
          : null,
    );
  }
}
