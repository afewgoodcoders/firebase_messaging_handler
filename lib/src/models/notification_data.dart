import '../enums/export.dart';

class NotificationAction {
  /// Stable identifier returned when the action is selected.
  final String id;

  /// User-visible action label.
  final String title;

  /// Marks an action that can remove data or perform another destructive task.
  final bool destructive;

  /// Opens the application UI when the action is selected.
  final bool foreground;

  /// Requires the device to be unlocked before the action can run.
  final bool requiresAuthentication;

  /// Removes the notification after the action is selected.
  final bool cancelNotification;

  /// Enables inline text input for reply-style actions.
  final bool textInput;

  /// Label shown by platforms that support inline input prompts.
  final String? inputLabel;

  /// Title of the submit button for inline text input on Apple platforms.
  final String? inputButtonTitle;

  /// Suggested reply choices on Android.
  final List<String> inputChoices;

  /// Whether arbitrary text is accepted in addition to [inputChoices].
  final bool allowFreeFormInput;

  /// Optional application payload associated with the action.
  final Map<String, dynamic>? payload;

  /// Creates an interactive notification action.
  const NotificationAction({
    required this.id,
    required this.title,
    this.destructive = false,
    this.foreground = true,
    this.requiresAuthentication = false,
    this.cancelNotification = true,
    this.textInput = false,
    this.inputLabel,
    this.inputButtonTitle,
    this.inputChoices = const <String>[],
    this.allowFreeFormInput = true,
    this.payload,
  });

  /// Converts this action to a JSON-compatible map.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'title': title,
    'destructive': destructive,
    'foreground': foreground,
    'requiresAuthentication': requiresAuthentication,
    'cancelNotification': cancelNotification,
    'textInput': textInput,
    'inputLabel': inputLabel,
    'inputButtonTitle': inputButtonTitle,
    'inputChoices': inputChoices,
    'allowFreeFormInput': allowFreeFormInput,
    'payload': payload,
  };

  /// Recreates an action from a JSON-compatible map.
  factory NotificationAction.fromMap(Map<String, dynamic> map) {
    return NotificationAction(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      destructive: map['destructive'] == true,
      foreground: map['foreground'] as bool? ?? true,
      requiresAuthentication: map['requiresAuthentication'] == true,
      cancelNotification: map['cancelNotification'] as bool? ?? true,
      textInput: map['textInput'] == true,
      inputLabel: map['inputLabel']?.toString(),
      inputButtonTitle: map['inputButtonTitle']?.toString(),
      inputChoices:
          (map['inputChoices'] as List<dynamic>?)
              ?.map((dynamic value) => value.toString())
              .toList() ??
          const <String>[],
      allowFreeFormInput: map['allowFreeFormInput'] as bool? ?? true,
      payload: map['payload'] is Map
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : null,
    );
  }
}

class NotificationData {
  final Map<String, dynamic> payload;
  final String? title;
  final String? body;
  final String? imageUrl;
  final String? icon;
  final String? category;
  final List<NotificationAction>? actions;
  final DateTime? timestamp;
  final NotificationTypeEnum type;
  final bool isFromTerminated;
  final String? messageId;
  final String? senderId;
  final int? badgeCount;
  final bool? isSilent;
  final String? sound;
  final String? tag;
  final String? groupKey;
  final Map<String, dynamic>? metadata;

  NotificationData({
    required this.payload,
    this.title,
    this.body,
    this.imageUrl,
    this.icon,
    this.category,
    this.actions,
    this.timestamp,
    this.type = NotificationTypeEnum.foreground,
    this.isFromTerminated = false,
    this.messageId,
    this.senderId,
    this.badgeCount,
    this.isSilent,
    this.sound,
    this.tag,
    this.groupKey,
    this.metadata,
  });

  /// Creates a copy of this NotificationData with the given fields replaced
  NotificationData copyWith({
    Map<String, dynamic>? payload,
    String? title,
    String? body,
    String? imageUrl,
    String? icon,
    String? category,
    List<NotificationAction>? actions,
    DateTime? timestamp,
    NotificationTypeEnum? type,
    bool? isFromTerminated,
    String? messageId,
    String? senderId,
    int? badgeCount,
    bool? isSilent,
    String? sound,
    String? tag,
    String? groupKey,
    Map<String, dynamic>? metadata,
  }) {
    return NotificationData(
      payload: payload ?? this.payload,
      title: title ?? this.title,
      body: body ?? this.body,
      imageUrl: imageUrl ?? this.imageUrl,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      actions: actions ?? this.actions,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      isFromTerminated: isFromTerminated ?? this.isFromTerminated,
      messageId: messageId ?? this.messageId,
      senderId: senderId ?? this.senderId,
      badgeCount: badgeCount ?? this.badgeCount,
      isSilent: isSilent ?? this.isSilent,
      sound: sound ?? this.sound,
      tag: tag ?? this.tag,
      groupKey: groupKey ?? this.groupKey,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Converts the notification data to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'payload': payload,
      'title': title,
      'body': body,
      'imageUrl': imageUrl,
      'icon': icon,
      'category': category,
      'actions': actions
          ?.map((NotificationAction action) => action.toMap())
          .toList(),
      'timestamp': timestamp?.toIso8601String(),
      'type': type.toString().split('.').last, // Get enum name safely
      'isFromTerminated': isFromTerminated,
      'messageId': messageId,
      'senderId': senderId,
      'badgeCount': badgeCount,
      'isSilent': isSilent,
      'sound': sound,
      'tag': tag,
      'groupKey': groupKey,
      'metadata': metadata,
    };
  }

  /// Creates a NotificationData from a map
  factory NotificationData.fromMap(Map<String, dynamic> map) {
    return NotificationData(
      payload: Map<String, dynamic>.from(map['payload'] ?? {}),
      title: map['title'],
      body: map['body'],
      imageUrl: map['imageUrl'],
      icon: map['icon'],
      category: map['category'],
      actions: map['actions'] != null
          ? (map['actions'] as List<dynamic>)
                .map(
                  (dynamic action) => NotificationAction.fromMap(
                    Map<String, dynamic>.from(action as Map),
                  ),
                )
                .toList()
          : null,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      type: NotificationTypeEnum.values.firstWhere(
        (type) => type.toString().split('.').last == map['type'],
        orElse: () => NotificationTypeEnum.foreground,
      ),
      isFromTerminated: map['isFromTerminated'] ?? false,
      messageId: map['messageId'],
      senderId: map['senderId'],
      badgeCount: map['badgeCount'],
      isSilent: map['isSilent'],
      sound: map['sound'],
      tag: map['tag'],
      groupKey: map['groupKey'],
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(map['metadata'])
          : null,
    );
  }
}
