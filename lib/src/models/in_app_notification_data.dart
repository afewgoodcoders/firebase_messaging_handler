import '../enums/export.dart';

class InAppNotificationData {
  final String id;
  final String templateId;
  final InAppTriggerTypeEnum triggerType;
  final Map<String, dynamic> content;
  final Map<String, dynamic> analytics;
  final Map<String, dynamic> rawPayload;
  final DateTime receivedAt;

  const InAppNotificationData({
    required this.id,
    required this.templateId,
    required this.triggerType,
    required this.content,
    required this.analytics,
    required this.rawPayload,
    required this.receivedAt,
  });

  InAppNotificationData copyWith({
    String? id,
    String? templateId,
    InAppTriggerTypeEnum? triggerType,
    Map<String, dynamic>? content,
    Map<String, dynamic>? analytics,
    Map<String, dynamic>? rawPayload,
    DateTime? receivedAt,
  }) {
    return InAppNotificationData(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      triggerType: triggerType ?? this.triggerType,
      content: content ?? this.content,
      analytics: analytics ?? this.analytics,
      rawPayload: rawPayload ?? this.rawPayload,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'templateId': templateId,
      'triggerType': triggerType.name,
      'content': content,
      'analytics': analytics,
      'rawPayload': rawPayload,
      'receivedAt': receivedAt.toIso8601String(),
    };
  }

  factory InAppNotificationData.fromMap(Map<String, dynamic> map) {
    return InAppNotificationData(
      id: map['id'] as String,
      templateId: map['templateId'] as String,
      triggerType: InAppTriggerTypeEnum.fromString(
        map['triggerType'] as String?,
      ),
      content: Map<String, dynamic>.from(
        (map['content'] as Map?) ?? <String, dynamic>{},
      ),
      analytics: Map<String, dynamic>.from(
        (map['analytics'] as Map?) ?? <String, dynamic>{},
      ),
      rawPayload: Map<String, dynamic>.from(
        (map['rawPayload'] as Map?) ?? <String, dynamic>{},
      ),
      receivedAt:
          DateTime.tryParse(map['receivedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
