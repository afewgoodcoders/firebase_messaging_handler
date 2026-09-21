import 'dart:convert';

import 'notification_data.dart';

/// Commands understood by the v2 notification pipeline.
enum NotificationEnvelopeCommand {
  /// Display or otherwise deliver a notification.
  display,

  /// Cancel a previously displayed or pending notification.
  cancel,

  /// Replace a notification that uses the same stable identifier.
  replace,

  /// Mark a matching inbox item as read without displaying a notification.
  markRead,

  /// Process data without presenting a system notification.
  silent,
}

/// Delivery priority requested by a v2 payload.
enum NotificationEnvelopePriority { normal, high }

/// Who presents a remote display notification outside the foreground.
enum NotificationRemotePresentation {
  /// The package receives data and applies client-side policy before display.
  client,

  /// FCM/APNs displays the notification when the application is not active.
  system,
}

/// Validation result for a [NotificationEnvelope].
class NotificationEnvelopeValidationResult {
  /// Creates a validation result.
  const NotificationEnvelopeValidationResult(this.errors);

  /// Validation failures. An empty list means the envelope is valid.
  final List<String> errors;

  /// Whether validation succeeded.
  bool get isValid => errors.isEmpty;
}

/// Versioned, platform-neutral wire contract for remote notifications.
///
/// [toFcmData] produces a string-only map suitable for the FCM `data` field.
/// Complex values are encoded as JSON, then decoded by [fromMap].
class NotificationEnvelope {
  /// Current schema version emitted by this package.
  static const int currentSchemaVersion = 2;

  /// Conservative FCM data payload limit in UTF-8 bytes.
  static const int maxFcmDataBytes = 4096;

  /// Maximum time-to-live accepted by FCM.
  static const Duration maxTimeToLive = Duration(days: 28);

  /// Creates a notification envelope.
  const NotificationEnvelope({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    this.idempotencyKey,
    this.command = NotificationEnvelopeCommand.display,
    this.title,
    this.body,
    this.titleLocalizationKey,
    this.titleLocalizationArguments = const <String>[],
    this.bodyLocalizationKey,
    this.bodyLocalizationArguments = const <String>[],
    this.category,
    this.route,
    this.imageUrl,
    this.sound,
    this.channelId,
    this.actions = const <NotificationAction>[],
    this.timeToLive,
    this.priority = NotificationEnvelopePriority.high,
    this.remotePresentation = NotificationRemotePresentation.client,
    this.collapseKey,
    this.dedupeKey,
    this.sentAt,
    this.expiresAt,
    this.storeInInbox = true,
    this.updateBadge = true,
    this.presentInApp = false,
    this.analytics = const <String, dynamic>{},
    this.platform = const <String, dynamic>{},
    this.data = const <String, dynamic>{},
  });

  /// Wire-schema version.
  final int schemaVersion;

  /// Stable message identifier used for routing and replacement.
  final String id;

  /// Server-provided idempotency key. Defaults to [id] when omitted.
  final String? idempotencyKey;

  /// Operation the client should perform.
  final NotificationEnvelopeCommand command;

  /// Notification title, or null when localization fields are used.
  final String? title;

  /// Notification body, or null when localization fields are used.
  final String? body;

  /// Platform localization key for the title.
  final String? titleLocalizationKey;

  /// Arguments for [titleLocalizationKey].
  final List<String> titleLocalizationArguments;

  /// Platform localization key for the body.
  final String? bodyLocalizationKey;

  /// Arguments for [bodyLocalizationKey].
  final List<String> bodyLocalizationArguments;

  /// Preference/action category.
  final String? category;

  /// Application route or deep link.
  final String? route;

  /// Optional rich-media URL.
  final String? imageUrl;

  /// Optional platform sound resource.
  final String? sound;

  /// Android notification channel identifier.
  final String? channelId;

  /// Interactive actions.
  final List<NotificationAction> actions;

  /// Client-visible message lifetime.
  final Duration? timeToLive;

  /// Delivery priority.
  final NotificationEnvelopePriority priority;

  /// Whether FCM or the package owns background/terminated presentation.
  ///
  /// `system` is more reliable for user-visible alerts when the application is
  /// suspended. `client` enables preferences and policy to run before display,
  /// but data-only delivery remains subject to operating-system restrictions.
  final NotificationRemotePresentation remotePresentation;

  /// FCM collapse key used to replace undelivered messages.
  final String? collapseKey;

  /// Client-side deduplication key.
  final String? dedupeKey;

  /// Time the backend accepted or emitted the message.
  final DateTime? sentAt;

  /// Absolute expiry time checked by the client.
  final DateTime? expiresAt;

  /// Whether the package should persist an inbox item.
  final bool storeInInbox;

  /// Whether the package may update the application badge.
  final bool updateBadge;

  /// Whether the message is eligible for in-app presentation.
  final bool presentInApp;

  /// Privacy-safe analytics dimensions.
  final Map<String, dynamic> analytics;

  /// Typed-platform escape hatch (`android`, `apple`, and `web` keys).
  final Map<String, dynamic> platform;

  /// Application-owned payload data.
  final Map<String, dynamic> data;

  /// Effective idempotency key.
  String get effectiveIdempotencyKey => idempotencyKey ?? id;

  /// Returns true when the envelope is expired at [now].
  bool isExpired([DateTime? now]) {
    final DateTime instant = now ?? DateTime.now();
    if (expiresAt != null) return !expiresAt!.isAfter(instant);
    if (sentAt != null && timeToLive != null) {
      return !sentAt!.add(timeToLive!).isAfter(instant);
    }
    return false;
  }

  /// Validates identifiers, presentation content, actions, and expiry fields.
  NotificationEnvelopeValidationResult validate() {
    final List<String> errors = <String>[];
    if (schemaVersion != currentSchemaVersion) {
      errors.add(
        'Unsupported schemaVersion $schemaVersion; expected $currentSchemaVersion',
      );
    }
    if (id.trim().isEmpty) errors.add('id is required');
    if (command == NotificationEnvelopeCommand.display ||
        command == NotificationEnvelopeCommand.replace) {
      final bool hasTitle =
          title?.trim().isNotEmpty == true ||
          titleLocalizationKey?.trim().isNotEmpty == true;
      final bool hasBody =
          body?.trim().isNotEmpty == true ||
          bodyLocalizationKey?.trim().isNotEmpty == true;
      if (!hasTitle && !hasBody) {
        errors.add(
          'display and replace commands require title or body content',
        );
      }
    }
    if (timeToLive?.isNegative == true ||
        (timeToLive != null && timeToLive! > maxTimeToLive)) {
      errors.add('timeToLive must be between zero and 28 days');
    }
    if (expiresAt != null && sentAt != null && !expiresAt!.isAfter(sentAt!)) {
      errors.add('expiresAt must be later than sentAt');
    }
    final Set<String> actionIds = <String>{};
    for (final NotificationAction action in actions) {
      if (action.id.trim().isEmpty || action.title.trim().isEmpty) {
        errors.add('action id and title cannot be empty');
      } else if (!actionIds.add(action.id)) {
        errors.add('action IDs must be unique: ${action.id}');
      }
    }
    for (final String key in data.keys) {
      if (_reservedKeys.contains(key)) {
        errors.add('data key "$key" is reserved by the v2 envelope');
      }
    }
    return NotificationEnvelopeValidationResult(errors);
  }

  /// Creates an envelope from either a decoded application map or string-only
  /// FCM data. JSON-encoded complex fields are accepted in both forms.
  factory NotificationEnvelope.fromMap(Map<String, dynamic> source) {
    final Map<String, dynamic> map = Map<String, dynamic>.from(source);
    dynamic decoded(String key) => _decodeJsonValue(map[key]);

    final dynamic rawActions = decoded('actions');
    final dynamic rawAnalytics = decoded('analytics');
    final dynamic rawPlatform = decoded('platform');
    final dynamic rawData = decoded('data');
    final int? ttlSeconds = _asInt(map['ttlSeconds']);

    return NotificationEnvelope(
      schemaVersion: _asInt(map['schemaVersion']) ?? currentSchemaVersion,
      id:
          _asString(map['id']) ??
          _asString(map['messageId']) ??
          _asString(map['dedupeKey']) ??
          '',
      idempotencyKey: _asString(map['idempotencyKey']),
      command: _enumByName(
        NotificationEnvelopeCommand.values,
        _asString(map['command']),
        NotificationEnvelopeCommand.display,
      ),
      title: _asString(map['title']),
      body: _asString(map['body']),
      titleLocalizationKey: _asString(map['titleLocKey']),
      titleLocalizationArguments: _stringList(decoded('titleLocArgs')),
      bodyLocalizationKey: _asString(map['bodyLocKey']),
      bodyLocalizationArguments: _stringList(decoded('bodyLocArgs')),
      category: _asString(map['category']),
      route: _asString(map['route']) ?? _asString(map['deeplink']),
      imageUrl: _asString(map['image']),
      sound: _asString(map['sound']),
      channelId: _asString(map['channelId']),
      actions: rawActions is List
          ? rawActions
                .whereType<Map>()
                .map(
                  (Map<dynamic, dynamic> action) => NotificationAction.fromMap(
                    Map<String, dynamic>.from(action),
                  ),
                )
                .toList()
          : const <NotificationAction>[],
      timeToLive: ttlSeconds == null ? null : Duration(seconds: ttlSeconds),
      priority: _enumByName(
        NotificationEnvelopePriority.values,
        _asString(map['priority']),
        NotificationEnvelopePriority.high,
      ),
      remotePresentation: _enumByName(
        NotificationRemotePresentation.values,
        _asString(map['remotePresentation']),
        NotificationRemotePresentation.client,
      ),
      collapseKey: _asString(map['collapseKey']),
      dedupeKey: _asString(map['dedupeKey']),
      sentAt: _asDateTime(map['sentAt']),
      expiresAt: _asDateTime(map['expiresAt']),
      storeInInbox: _asBool(map['storeInInbox']) ?? true,
      updateBadge: _asBool(map['updateBadge']) ?? true,
      presentInApp: _asBool(map['presentInApp']) ?? false,
      analytics: rawAnalytics is Map
          ? Map<String, dynamic>.from(rawAnalytics)
          : const <String, dynamic>{},
      platform: rawPlatform is Map
          ? Map<String, dynamic>.from(rawPlatform)
          : const <String, dynamic>{},
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : _unreservedData(map),
    );
  }

  /// Converts this envelope into a string-only FCM data payload.
  ///
  /// Throws [StateError] for an invalid envelope and [RangeError] when the
  /// encoded payload exceeds [maxFcmDataBytes].
  Map<String, String> toFcmData() {
    final NotificationEnvelopeValidationResult validation = validate();
    if (!validation.isValid) {
      throw StateError(validation.errors.join('; '));
    }
    final Map<String, dynamic> raw =
        <String, dynamic>{
          'schemaVersion': schemaVersion,
          'id': id,
          'idempotencyKey': idempotencyKey,
          'command': command.name,
          'title': title,
          'body': body,
          'titleLocKey': titleLocalizationKey,
          'titleLocArgs': titleLocalizationArguments,
          'bodyLocKey': bodyLocalizationKey,
          'bodyLocArgs': bodyLocalizationArguments,
          'category': category,
          'route': route,
          'image': imageUrl,
          'sound': sound,
          'channelId': channelId,
          'actions': actions
              .map((NotificationAction action) => action.toMap())
              .toList(),
          'ttlSeconds': timeToLive?.inSeconds,
          'priority': priority.name,
          'remotePresentation': remotePresentation.name,
          'collapseKey': collapseKey,
          'dedupeKey': dedupeKey,
          'sentAt': sentAt?.toUtc().toIso8601String(),
          'expiresAt': expiresAt?.toUtc().toIso8601String(),
          'storeInInbox': storeInInbox,
          'updateBadge': updateBadge,
          'presentInApp': presentInApp,
          'analytics': analytics,
          'platform': platform,
          'data': data,
        }..removeWhere((String _, dynamic value) {
          if (value == null) return true;
          if (value is Iterable || value is Map) return value.isEmpty;
          return false;
        });

    final Map<String, String> encoded = raw.map(
      (String key, dynamic value) => MapEntry<String, String>(
        key,
        value is String ? value : jsonEncode(value),
      ),
    );
    final int bytes = utf8.encode(jsonEncode(encoded)).length;
    if (bytes > maxFcmDataBytes) {
      throw RangeError(
        'FCM data payload is $bytes bytes; maximum is $maxFcmDataBytes bytes',
      );
    }
    return encoded;
  }

  static const Set<String> _reservedKeys = <String>{
    'schemaVersion',
    'id',
    'messageId',
    'idempotencyKey',
    'command',
    'title',
    'body',
    'titleLocKey',
    'titleLocArgs',
    'bodyLocKey',
    'bodyLocArgs',
    'category',
    'route',
    'deeplink',
    'image',
    'sound',
    'channelId',
    'actions',
    'ttlSeconds',
    'priority',
    'remotePresentation',
    'collapseKey',
    'dedupeKey',
    'sentAt',
    'expiresAt',
    'storeInInbox',
    'updateBadge',
    'presentInApp',
    'analytics',
    'platform',
    'data',
  };

  static Map<String, dynamic> _unreservedData(Map<String, dynamic> map) {
    return Map<String, dynamic>.fromEntries(
      map.entries.where((MapEntry<String, dynamic> entry) {
        return !_reservedKeys.contains(entry.key);
      }),
    );
  }

  static dynamic _decodeJsonValue(dynamic value) {
    if (value is! String || value.isEmpty) return value;
    final String trimmed = value.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return value;
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  static String? _asString(dynamic value) {
    if (value == null) return null;
    final String result = value.toString();
    return result.isEmpty ? null : result;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value == 'true' || value == '1') return true;
    if (value == 'false' || value == '0') return false;
    return null;
  }

  static DateTime? _asDateTime(dynamic value) {
    final String? raw = _asString(value);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value.map((dynamic item) => item.toString()).toList();
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final T value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
