import 'dart:typed_data';
import 'dart:ui';
import 'package:firebase_messaging_handler/src/enums/export.dart';
import 'package:firebase_messaging_handler/src/models/notification_data.dart';

/// Describes a notification channel and its defaults for Android delivery.
class NotificationChannelData {
  /// Stable channel identifier used by Android notifications.
  final String id;

  /// Human-readable channel name shown in system settings.
  final String name;

  /// Optional system-visible description for the channel.
  final String? description;

  /// Optional Android channel group identifier.
  final String? groupId;

  /// Channel importance level for Android.
  final NotificationImportanceEnum importance;

  /// Whether notifications in this channel should play a sound.
  final bool playSound;

  /// Raw Android sound resource name when using a custom sound.
  final String? soundPath;

  /// Optional original sound file name used by higher-level APIs.
  final String? soundFileName;

  /// Whether vibration is enabled for this channel.
  final bool enableVibration;

  /// Whether notification lights are enabled for this channel.
  final bool enableLights;

  /// Optional custom vibration pattern.
  final Int64List? vibrationPattern;

  /// Optional LED color for supported Android devices.
  final Color? ledColor;

  /// Whether notifications in this channel should contribute to app badges.
  final bool showBadge;

  /// Default priority to use when presenting notifications in this channel.
  final NotificationPriorityEnum priority;

  /// Optional default action definitions associated with the channel.
  final List<NotificationAction>? actions;

  /// Creates a channel definition used during initialization and local display.
  NotificationChannelData({
    required this.id,
    required this.name,
    this.description,
    this.groupId,
    this.importance = NotificationImportanceEnum.defaultImportance,
    this.playSound = true,
    this.soundPath,
    this.soundFileName,
    this.enableVibration = true,
    this.enableLights = false,
    this.vibrationPattern,
    this.ledColor,
    this.showBadge = true,
    this.priority = NotificationPriorityEnum.defaultPriority,
    this.actions,
  });
}
