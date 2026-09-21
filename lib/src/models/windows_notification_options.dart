/// Application identity required by Windows toast notifications.
class WindowsNotificationOptions {
  /// Creates Windows notification initialization options.
  const WindowsNotificationOptions({
    required this.appName,
    required this.appUserModelId,
    required this.guid,
    this.iconPath,
  });

  /// Name displayed by Windows for toast notifications.
  final String appName;

  /// Stable Windows AppUserModelID.
  final String appUserModelId;

  /// Stable GUID for the notification activation callback.
  final String guid;

  /// Optional application icon path.
  final String? iconPath;

  /// Converts these options to a JSON-compatible map.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'appName': appName,
    'appUserModelId': appUserModelId,
    'guid': guid,
    'iconPath': iconPath,
  };

  /// Recreates options from a serialized map.
  factory WindowsNotificationOptions.fromMap(Map<String, dynamic> map) {
    return WindowsNotificationOptions(
      appName: map['appName']?.toString() ?? '',
      appUserModelId: map['appUserModelId']?.toString() ?? '',
      guid: map['guid']?.toString() ?? '',
      iconPath: map['iconPath']?.toString(),
    );
  }
}
