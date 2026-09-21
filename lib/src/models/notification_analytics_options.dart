/// Controls how much notification content can leave the package through the
/// configured analytics callback.
enum NotificationAnalyticsPrivacy {
  /// Do not emit package analytics events.
  disabled,

  /// Emit identifiers, lifecycle, and non-content metadata only.
  metadataOnly,

  /// Emit notification content and application data.
  ///
  /// Applications are responsible for consent and data-governance compliance.
  fullPayload,
}

/// Privacy settings for package analytics.
class NotificationAnalyticsOptions {
  /// Creates analytics options.
  const NotificationAnalyticsOptions({
    this.privacy = NotificationAnalyticsPrivacy.metadataOnly,
  });

  /// Selected content privacy level.
  final NotificationAnalyticsPrivacy privacy;

  /// Converts these settings to a JSON-compatible map.
  Map<String, dynamic> toMap() => <String, dynamic>{'privacy': privacy.name};

  /// Recreates analytics settings from a serialized map.
  factory NotificationAnalyticsOptions.fromMap(Map<String, dynamic> map) {
    final String? name = map['privacy']?.toString();
    return NotificationAnalyticsOptions(
      privacy: NotificationAnalyticsPrivacy.values.firstWhere(
        (NotificationAnalyticsPrivacy value) => value.name == name,
        orElse: () => NotificationAnalyticsPrivacy.metadataOnly,
      ),
    );
  }
}
