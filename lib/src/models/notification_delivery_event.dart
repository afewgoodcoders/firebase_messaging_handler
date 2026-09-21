import '../enums/notification_lifecycle_enum.dart';
import 'notification_delivery_policy.dart';

/// Typed events emitted throughout notification delivery and interaction.
enum NotificationDeliveryEventType {
  /// A message entered the package pipeline.
  received,

  /// A notification was displayed or persisted successfully.
  delivered,

  /// A notification was accepted by the platform scheduler.
  scheduled,

  /// A policy or preference prevented delivery.
  suppressed,

  /// Delivery was moved to a later time.
  deferred,

  /// The user opened a notification.
  opened,

  /// The user selected an action button.
  actionSelected,

  /// The user dismissed a notification.
  dismissed,

  /// Delivery failed.
  failed,

  /// An expired payload was ignored.
  expired,

  /// An already-processed idempotency key was ignored.
  deduplicated,

  /// A remote command cancelled a notification.
  cancelled,

  /// A non-display remote command completed successfully.
  commandProcessed,
}

/// A strongly typed notification lifecycle event.
class NotificationDeliveryEvent {
  /// Creates a delivery event.
  const NotificationDeliveryEvent({
    required this.type,
    required this.surface,
    required this.messageId,
    required this.timestamp,
    this.lifecycle,
    this.categoryId,
    this.actionId,
    this.actionInput,
    this.reason,
    this.nextEligibleAt,
    this.data = const <String, dynamic>{},
  });

  /// Event type.
  final NotificationDeliveryEventType type;

  /// Surface associated with the event.
  final NotificationDeliverySurface surface;

  /// Message or notification identifier.
  final String messageId;

  /// Time at which the event occurred.
  final DateTime timestamp;

  /// App lifecycle, when known.
  final NotificationLifecycle? lifecycle;

  /// Preference category, when present.
  final String? categoryId;

  /// Selected action identifier, when present.
  final String? actionId;

  /// Text submitted by an inline reply action, when present.
  final String? actionInput;

  /// Suppression, deferral, or failure reason.
  final String? reason;

  /// Suggested retry time for a deferred event.
  final DateTime? nextEligibleAt;

  /// Original application payload.
  final Map<String, dynamic> data;
}
