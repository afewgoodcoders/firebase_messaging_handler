/// Stable error categories returned by v2 operations.
enum NotificationOperationErrorCode {
  unsupported,
  disabled,
  invalidArgument,
  permissionDenied,
  platformFailure,
  unknown,
}

/// Typed result for operations that can fail or be unsupported.
class NotificationOperationResult<T> {
  const NotificationOperationResult._({
    required this.isSuccess,
    this.value,
    this.errorCode,
    this.message,
    this.error,
  });

  /// Creates a successful result.
  const NotificationOperationResult.success([T? value])
    : this._(isSuccess: true, value: value);

  /// Creates a failed result.
  const NotificationOperationResult.failure({
    required NotificationOperationErrorCode code,
    required String message,
    Object? error,
  }) : this._(
         isSuccess: false,
         errorCode: code,
         message: message,
         error: error,
       );

  /// Whether the operation completed successfully.
  final bool isSuccess;

  /// Successful value, when present.
  final T? value;

  /// Stable failure category.
  final NotificationOperationErrorCode? errorCode;

  /// Human-readable failure details.
  final String? message;

  /// Original platform error, when available.
  final Object? error;
}
