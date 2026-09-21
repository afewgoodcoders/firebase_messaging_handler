import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cross-isolate key/value persistence used by the v2 runtime state machine.
abstract class NotificationStateStore {
  /// Reads a JSON-compatible value.
  Future<Object?> read(String key);

  /// Writes a JSON-compatible value.
  Future<void> write(String key, Object? value);

  /// Removes a stored value.
  Future<void> remove(String key);
}

/// Default state store backed by the cache-coherent SharedPreferences async API.
class SharedPreferencesNotificationStateStore
    implements NotificationStateStore {
  /// Creates a SharedPreferences-backed state store.
  SharedPreferencesNotificationStateStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences;

  SharedPreferencesAsync? _preferences;

  @override
  Future<Object?> read(String key) async {
    final String? encoded = await _readString(key);
    if (encoded == null) return null;
    return jsonDecode(encoded) as Object?;
  }

  @override
  Future<void> write(String key, Object? value) async {
    final String encoded = jsonEncode(value);
    try {
      final SharedPreferencesAsync preferences = _preferences ??=
          SharedPreferencesAsync();
      await preferences.setString(key, encoded);
    } on StateError {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      await preferences.setString(key, encoded);
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      final SharedPreferencesAsync preferences = _preferences ??=
          SharedPreferencesAsync();
      await preferences.remove(key);
    } on StateError {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      await preferences.remove(key);
    }
  }

  Future<String?> _readString(String key) async {
    try {
      final SharedPreferencesAsync preferences = _preferences ??=
          SharedPreferencesAsync();
      return await preferences.getString(key);
    } on StateError {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      return preferences.getString(key);
    }
  }
}
