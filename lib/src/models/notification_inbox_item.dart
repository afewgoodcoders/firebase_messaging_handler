import 'notification_data.dart';

class NotificationInboxItem {
  final String id;
  final String title;
  final String body;
  final String? subtitle;
  final DateTime timestamp;
  final bool isRead;
  final String? imageUrl;
  final List<NotificationAction> actions;
  final String? category;
  final Map<String, dynamic> data;

  const NotificationInboxItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.subtitle,
    this.isRead = false,
    this.imageUrl,
    this.actions = const <NotificationAction>[],
    this.category,
    this.data = const <String, dynamic>{},
  });

  NotificationInboxItem copyWith({
    String? id,
    String? title,
    String? body,
    String? subtitle,
    DateTime? timestamp,
    bool? isRead,
    String? imageUrl,
    List<NotificationAction>? actions,
    String? category,
    Map<String, dynamic>? data,
  }) {
    return NotificationInboxItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      subtitle: subtitle ?? this.subtitle,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      imageUrl: imageUrl ?? this.imageUrl,
      actions: actions ?? this.actions,
      category: category ?? this.category,
      data: data ?? this.data,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'body': body,
      'subtitle': subtitle,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'imageUrl': imageUrl,
      'category': category,
      'data': data,
      'actions': actions
          .map(
            (NotificationAction action) => <String, dynamic>{
              'id': action.id,
              'title': action.title,
              'destructive': action.destructive,
              'payload': action.payload,
            },
          )
          .toList(),
    };
  }

  factory NotificationInboxItem.fromMap(Map<String, dynamic> map) {
    return NotificationInboxItem(
      id: map['id'] as String,
      title: map['title'] as String,
      body: map['body'] as String,
      subtitle: map['subtitle'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      isRead: map['isRead'] as bool? ?? false,
      imageUrl: map['imageUrl'] as String?,
      category: map['category'] as String?,
      data: map['data'] != null
          ? Map<String, dynamic>.from(map['data'] as Map)
          : const <String, dynamic>{},
      actions: (map['actions'] as List<dynamic>? ?? <dynamic>[]).map((
        dynamic action,
      ) {
        final Map<String, dynamic> parsed = Map<String, dynamic>.from(
          action as Map,
        );
        return NotificationAction(
          id: parsed['id'] as String,
          title: parsed['title'] as String,
          destructive: parsed['destructive'] as bool? ?? false,
          payload: parsed['payload'] != null
              ? Map<String, dynamic>.from(parsed['payload'] as Map)
              : null,
        );
      }).toList(),
    );
  }
}
