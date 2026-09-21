import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/notification_preferences.dart';
import '../interfaces/notification_preferences_repository.dart';

/// Stores notification preferences in `SharedPreferences`.
class SharedPreferencesNotificationPreferencesRepository
    implements NotificationPreferencesRepository {
  /// Creates a repository, optionally using an injected preferences instance.
  SharedPreferencesNotificationPreferencesRepository({
    SharedPreferences? preferences,
    this.storageKey = 'fmh_notification_preferences_v1',
  }) : _preferences = preferences == null
           ? SharedPreferences.getInstance()
           : Future<SharedPreferences>.value(preferences);

  final Future<SharedPreferences> _preferences;

  /// Key used for the encoded preferences document.
  final String storageKey;

  @override
  Future<NotificationPreferences?> load() async {
    final String? encoded = (await _preferences).getString(storageKey);
    if (encoded == null || encoded.isEmpty) return null;
    final dynamic decoded = jsonDecode(encoded);
    if (decoded is! Map) return null;
    return NotificationPreferences.fromMap(Map<String, dynamic>.from(decoded));
  }

  @override
  Future<void> save(NotificationPreferences preferences) async {
    await (await _preferences).setString(
      storageKey,
      jsonEncode(preferences.toMap()),
    );
  }

  @override
  Future<void> clear() async {
    await (await _preferences).remove(storageKey);
  }
}

/// In-memory repository intended for tests and ephemeral sessions.
class InMemoryNotificationPreferencesRepository
    implements NotificationPreferencesRepository {
  /// Creates a repository with optional initial preferences.
  InMemoryNotificationPreferencesRepository([this.value]);

  /// Current stored value.
  NotificationPreferences? value;

  @override
  Future<NotificationPreferences?> load() async => value;

  @override
  Future<void> save(NotificationPreferences preferences) async {
    value = preferences;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
