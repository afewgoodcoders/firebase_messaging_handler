/// Package capabilities that can vary by platform and runtime setup.
enum NotificationCapability {
  remotePush,
  localPresentation,
  foregroundDelivery,
  backgroundDelivery,
  terminatedDelivery,
  scheduling,
  recurringScheduling,
  exactScheduling,
  appIconBadge,
  topicSubscriptions,
  notificationActions,
  inlineReply,
  notificationInbox,
  inAppMessaging,
  webServiceWorker,
  deliveryMetricsExport,
}

/// Support status and setup guidance for one capability.
class NotificationCapabilityStatus {
  /// Creates a capability status.
  const NotificationCapabilityStatus({
    required this.supported,
    this.reason,
    this.requiresSetup = false,
  });

  /// Whether the capability is available in the current runtime.
  final bool supported;

  /// Human-readable limitation or setup requirement.
  final String? reason;

  /// Whether support depends on application or OS configuration.
  final bool requiresSetup;
}

/// Truthful runtime capability matrix for the current platform.
class NotificationCapabilities {
  /// Creates a capability matrix.
  const NotificationCapabilities({
    required this.platform,
    required this.statuses,
  });

  /// Current platform name.
  final String platform;

  /// Status for every known package capability.
  final Map<NotificationCapability, NotificationCapabilityStatus> statuses;

  /// Returns the status for [capability].
  NotificationCapabilityStatus operator [](NotificationCapability capability) {
    return statuses[capability] ??
        const NotificationCapabilityStatus(
          supported: false,
          reason: 'Capability status is unavailable.',
        );
  }

  /// Whether [capability] is supported.
  bool supports(NotificationCapability capability) =>
      this[capability].supported;
}
