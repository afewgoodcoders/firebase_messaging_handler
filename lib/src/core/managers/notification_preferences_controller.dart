import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../models/export.dart';
import '../interfaces/notification_preferences_repository.dart';

/// Loads, mutates, and persists user notification controls.
class NotificationPreferencesController extends ChangeNotifier {
  /// Creates a preferences controller.
  NotificationPreferencesController({
    required NotificationPreferencesRepository repository,
    List<NotificationCategory> categories = const <NotificationCategory>[],
    Future<bool> Function()? openSystemSettings,
  }) : _repository = repository,
       _categories = List<NotificationCategory>.unmodifiable(categories),
       _openSystemSettings = openSystemSettings,
       _preferences = _defaultsFor(categories);

  final NotificationPreferencesRepository _repository;
  final List<NotificationCategory> _categories;
  final Future<bool> Function()? _openSystemSettings;
  NotificationPreferences _preferences;
  bool _isLoading = false;

  /// Configured categories in display order.
  UnmodifiableListView<NotificationCategory> get categories =>
      UnmodifiableListView<NotificationCategory>(_categories);

  /// Current immutable preferences.
  NotificationPreferences get preferences => _preferences;

  /// Whether preferences are being loaded.
  bool get isLoading => _isLoading;

  /// Whether the host platform can open notification settings.
  bool get canOpenSystemSettings => _openSystemSettings != null;

  /// Opens this app's notification settings when supported.
  Future<bool> openSystemSettings() async =>
      await _openSystemSettings?.call() ?? false;

  /// Loads saved values and merges defaults for newly added categories.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    final NotificationPreferences? saved = await _repository.load();
    final NotificationPreferences defaults = _defaultsFor(_categories);
    _preferences = NotificationPreferences(
      enabled: saved?.enabled ?? defaults.enabled,
      categories: <String, NotificationCategoryPreference>{
        ...defaults.categories,
        ...?saved?.categories,
      },
      quietHours: saved?.quietHours,
    );
    _isLoading = false;
    notifyListeners();
  }

  /// Enables or disables all package-managed notification surfaces.
  Future<void> setEnabled(bool enabled) async {
    await _update(_preferences.copyWith(enabled: enabled));
  }

  /// Enables or disables a category.
  Future<void> setCategoryEnabled(String categoryId, bool enabled) async {
    await _updateCategory(
      categoryId,
      _preferences.category(categoryId).copyWith(enabled: enabled),
    );
  }

  /// Enables or disables sound for a category.
  Future<void> setCategorySoundEnabled(String categoryId, bool enabled) async {
    await _updateCategory(
      categoryId,
      _preferences.category(categoryId).copyWith(soundEnabled: enabled),
    );
  }

  /// Enables or disables badge updates for a category.
  Future<void> setCategoryBadgeEnabled(String categoryId, bool enabled) async {
    await _updateCategory(
      categoryId,
      _preferences.category(categoryId).copyWith(badgeEnabled: enabled),
    );
  }

  /// Sets user quiet hours. Pass null to use the app policy instead.
  Future<void> setQuietHours(NotificationQuietHours? quietHours) async {
    await _update(
      quietHours == null
          ? _preferences.copyWith(clearQuietHours: true)
          : _preferences.copyWith(quietHours: quietHours),
    );
  }

  Future<void> _updateCategory(
    String categoryId,
    NotificationCategoryPreference categoryPreference,
  ) async {
    await _update(
      _preferences.copyWith(
        categories: <String, NotificationCategoryPreference>{
          ..._preferences.categories,
          categoryId: categoryPreference,
        },
      ),
    );
  }

  Future<void> _update(NotificationPreferences next) async {
    _preferences = next;
    notifyListeners();
    await _repository.save(next);
  }

  static NotificationPreferences _defaultsFor(
    List<NotificationCategory> categories,
  ) {
    return NotificationPreferences(
      categories: <String, NotificationCategoryPreference>{
        for (final NotificationCategory category in categories)
          category.id: NotificationCategoryPreference(
            enabled: category.defaultEnabled,
          ),
      },
    );
  }
}
