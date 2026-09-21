/// Android scheduling accuracy and low-power behavior.
enum NotificationScheduleMode {
  /// Approximately on time; does not require exact-alarm access.
  inexact,

  /// Approximately on time and allowed during low-power idle mode.
  inexactAllowWhileIdle,

  /// Exact time; requires Android exact-alarm access on recent versions.
  exact,

  /// Exact time during low-power idle; requires exact-alarm access.
  exactAllowWhileIdle,
}
