import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'fcm_error.dart';

/// Log levels for the FCM logger
enum LogLevel { debug, info, warning, error, critical }

/// Logger class for FCM operations
class FCMLogger {
  static FCMLogger? _instance;
  LogLevel _minLevel = LogLevel.debug;
  bool _enableConsoleLogging = true;
  bool _enableFileLogging = false;
  final List<LogEntry> _logEntries = [];
  final int _maxLogEntries = 1000;

  /// Singleton instance
  static FCMLogger get instance {
    _instance ??= FCMLogger._internal();
    return _instance!;
  }

  FCMLogger._internal();

  /// Sets the minimum log level
  void setMinLevel(LogLevel level) {
    _minLevel = level;
  }

  /// Enables or disables console logging
  void setConsoleLogging(bool enabled) {
    _enableConsoleLogging = enabled;
  }

  /// Enables or disables file logging
  void setFileLogging(bool enabled) {
    _enableFileLogging = enabled;
  }

  /// Logs a debug message
  void debug(String message, {String? tag, dynamic data}) {
    _log(LogLevel.debug, message, tag: tag, data: data);
  }

  /// Logs an info message
  void info(String message, {String? tag, dynamic data}) {
    _log(LogLevel.info, message, tag: tag, data: data);
  }

  /// Logs a warning message
  void warning(String message, {String? tag, dynamic data}) {
    _log(LogLevel.warning, message, tag: tag, data: data);
  }

  /// Logs an error message
  void error(String message, {String? tag, dynamic data, FCMError? fcmError}) {
    _log(LogLevel.error, message, tag: tag, data: data, fcmError: fcmError);
  }

  /// Logs a critical message
  void critical(
    String message, {
    String? tag,
    dynamic data,
    FCMError? fcmError,
  }) {
    _log(LogLevel.critical, message, tag: tag, data: data, fcmError: fcmError);
  }

  /// Logs an FCM error
  void logError(FCMError error, {String? tag}) {
    _log(LogLevel.error, error.message, tag: tag, fcmError: error);
  }

  /// Gets all log entries
  List<LogEntry> getLogEntries() {
    return List.unmodifiable(_logEntries);
  }

  /// Clears all log entries
  void clearLogs() {
    _logEntries.clear();
  }

  /// Gets log entries filtered by level
  List<LogEntry> getLogEntriesByLevel(LogLevel level) {
    return _logEntries.where((entry) => entry.level == level).toList();
  }

  /// Gets log entries filtered by tag
  List<LogEntry> getLogEntriesByTag(String tag) {
    return _logEntries.where((entry) => entry.tag == tag).toList();
  }

  /// Exports logs to a map
  List<Map<String, dynamic>> exportLogs() {
    return _logEntries.map((entry) => entry.toMap()).toList();
  }

  void _log(
    LogLevel level,
    String message, {
    String? tag,
    dynamic data,
    FCMError? fcmError,
  }) {
    if (level.index < _minLevel.index) return;

    final entry = LogEntry(
      level: level,
      message: message,
      tag: tag ?? 'FCM',
      data: data,
      fcmError: fcmError,
      timestamp: DateTime.now(),
    );

    // Add to log entries
    _logEntries.add(entry);

    // Keep only the most recent entries
    if (_logEntries.length > _maxLogEntries) {
      _logEntries.removeAt(0);
    }

    // Console logging
    if (_enableConsoleLogging) {
      _logToConsole(entry);
    }

    // File logging (if enabled)
    if (_enableFileLogging) {
      _logToFile(entry);
    }
  }

  void _logToConsole(LogEntry entry) {
    final levelString = entry.level.name.toUpperCase();
    final timestamp = entry.timestamp.toIso8601String();
    final tag = entry.tag;
    final message = entry.message;

    final logMessage = '[$timestamp] [$levelString] [$tag] $message';

    switch (entry.level) {
      case LogLevel.debug:
        if (kDebugMode) {
          print(logMessage);
        }
        break;
      case LogLevel.info:
        if (kDebugMode) {
          print(logMessage);
        }
        break;
      case LogLevel.warning:
        if (kDebugMode) {
          print(logMessage);
        }
        break;
      case LogLevel.error:
        if (kDebugMode) {
          print(logMessage);
        }
        log(logMessage, name: 'FCM_ERROR');
        break;
      case LogLevel.critical:
        if (kDebugMode) {
          print(logMessage);
        }
        log(logMessage, name: 'FCM_CRITICAL');
        break;
    }

    // Log additional data if present
    if (entry.data != null) {
      log('Data: ${entry.data}', name: 'FCM_DATA');
    }

    // Log FCM error details if present
    if (entry.fcmError != null) {
      log('FCM Error: ${entry.fcmError!.toMap()}', name: 'FCM_ERROR_DETAILS');
    }
  }

  void _logToFile(LogEntry entry) {
    // File logging implementation would go here
    // For now, we'll just add it to the log entries
  }
}

/// Log entry class
class LogEntry {
  final LogLevel level;
  final String message;
  final String tag;
  final dynamic data;
  final FCMError? fcmError;
  final DateTime timestamp;

  const LogEntry({
    required this.level,
    required this.message,
    required this.tag,
    this.data,
    this.fcmError,
    required this.timestamp,
  });

  /// Converts the log entry to a map
  Map<String, dynamic> toMap() {
    return {
      'level': level.name,
      'message': message,
      'tag': tag,
      'data': data?.toString(),
      'fcmError': fcmError?.toMap(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    final levelString = level.name.toUpperCase();
    final timestamp = this.timestamp.toIso8601String();
    return '[$timestamp] [$levelString] [$tag] $message';
  }
}
