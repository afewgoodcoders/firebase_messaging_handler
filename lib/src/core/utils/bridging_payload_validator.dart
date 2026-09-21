import 'dart:convert';

import '../../models/notification_envelope.dart';

/// Validates data-only / bridging payloads before promotion or unified handling.
class BridgingPayloadValidator {
  /// Returns true when the payload is valid. Calls [onError] with a human-friendly
  /// reason when invalid.
  static bool validate(
    Map<String, dynamic> data, {
    void Function(String reason)? onError,
  }) {
    String? asString(dynamic value) => value?.toString().trim();

    bool fail(String reason) {
      onError?.call(reason);
      return false;
    }

    final Map<String, dynamic> normalized = normalize(data);
    data
      ..clear()
      ..addAll(normalized);

    if (data.containsKey('schemaVersion')) {
      final NotificationEnvelopeValidationResult result =
          NotificationEnvelope.fromMap(data).validate();
      if (!result.isValid) return fail(result.errors.join('; '));
      return true;
    }

    final String? title = asString(data['title']);
    final String? body = asString(data['body']);

    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return fail('missing "title" or "body" for data-only bridge');
    }

    // Analytics: normalization accepts a map or JSON string representing a map.
    final dynamic analytics = data['analytics'];
    if (analytics != null) {
      if (analytics is Map<String, dynamic>) {
        // ok
      } else {
        return fail('"analytics" must be a map or JSON string');
      }
    }

    // Actions: must be a list of maps with id/title strings.
    if (data['actions'] != null) {
      final dynamic actions = data['actions'];
      if (actions is! List) {
        return fail('"actions" must be an array of action objects');
      }
      for (final dynamic item in actions) {
        if (item is! Map) {
          return fail('each action must be an object with "id" and "title"');
        }
        final String? actionId = asString(item['id']);
        final String? actionTitle = asString(item['title']);
        if (actionId == null || actionId.isEmpty || actionTitle == null) {
          return fail('action is missing "id" or "title"');
        }
      }
    }

    // Optional keys type checks.
    final List<String> stringFields = <String>[
      'channelId',
      'image',
      'deeplink',
      'templateId',
      'priority',
      'category',
    ];
    for (final String field in stringFields) {
      if (data[field] != null && data[field] is! String) {
        return fail('"$field" must be a string when provided');
      }
    }

    return true;
  }

  /// Decodes JSON-encoded FCM values into the application-level payload shape.
  ///
  /// FCM requires all `data` values to be strings, so lists and maps such as
  /// actions, analytics, and platform overrides arrive as JSON strings.
  static Map<String, dynamic> normalize(Map<String, dynamic> data) {
    final Map<String, dynamic> result = Map<String, dynamic>.from(data);
    const Set<String> jsonFields = <String>{
      'actions',
      'analytics',
      'platform',
      'data',
      'titleLocArgs',
      'bodyLocArgs',
    };
    for (final String field in jsonFields) {
      final dynamic value = result[field];
      if (value is! String || value.isEmpty) continue;
      try {
        result[field] = jsonDecode(value);
      } catch (_) {
        // Validation below reports the precise expected type.
      }
    }
    return result;
  }
}
