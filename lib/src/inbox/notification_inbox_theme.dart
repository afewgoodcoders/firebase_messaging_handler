import 'package:flutter/material.dart';

@immutable
/// Visual customization options for [NotificationInboxView].
class NotificationInboxTheme {
  /// Creates a theme override for the inbox widget.
  const NotificationInboxTheme({
    this.backgroundColor,
    this.unreadBackgroundColor,
    this.readBackgroundColor,
    this.unreadTitleStyle,
    this.readTitleStyle,
    this.bodyStyle,
    this.subtitleStyle,
    this.timestampStyle,
    this.chipStyle,
    this.emptyState,
    this.leadingBuilder,
    this.trailingBuilder,
    this.dateFormat,
    this.dividerColor,
  });

  /// Overall background color for the inbox container.
  final Color? backgroundColor;

  /// Background color used for unread rows.
  final Color? unreadBackgroundColor;

  /// Background color used for read rows.
  final Color? readBackgroundColor;

  /// Title style used for unread items.
  final TextStyle? unreadTitleStyle;

  /// Title style used for read items.
  final TextStyle? readTitleStyle;

  /// Body text style for item content.
  final TextStyle? bodyStyle;

  /// Subtitle text style for secondary item content.
  final TextStyle? subtitleStyle;

  /// Timestamp text style.
  final TextStyle? timestampStyle;

  /// Chip theme for action chips shown in rows.
  final ChipThemeData? chipStyle;

  /// Optional widget shown when the inbox is empty.
  final Widget? emptyState;

  /// Optional builder for the leading area of each row.
  final Widget Function(BuildContext context, bool isRead)? leadingBuilder;

  /// Optional builder for the trailing area of each row.
  final Widget Function(BuildContext context)? trailingBuilder;

  /// Optional timestamp formatter override.
  final String Function(DateTime timestamp)? dateFormat;

  /// Divider color between rows.
  final Color? dividerColor;

  /// Creates a copy of this theme with selected fields replaced.
  NotificationInboxTheme copyWith({
    Color? backgroundColor,
    Color? unreadBackgroundColor,
    Color? readBackgroundColor,
    TextStyle? unreadTitleStyle,
    TextStyle? readTitleStyle,
    TextStyle? bodyStyle,
    TextStyle? subtitleStyle,
    TextStyle? timestampStyle,
    ChipThemeData? chipStyle,
    Widget? emptyState,
    Widget Function(BuildContext context, bool isRead)? leadingBuilder,
    Widget Function(BuildContext context)? trailingBuilder,
    String Function(DateTime timestamp)? dateFormat,
    Color? dividerColor,
  }) {
    return NotificationInboxTheme(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      unreadBackgroundColor:
          unreadBackgroundColor ?? this.unreadBackgroundColor,
      readBackgroundColor: readBackgroundColor ?? this.readBackgroundColor,
      unreadTitleStyle: unreadTitleStyle ?? this.unreadTitleStyle,
      readTitleStyle: readTitleStyle ?? this.readTitleStyle,
      bodyStyle: bodyStyle ?? this.bodyStyle,
      subtitleStyle: subtitleStyle ?? this.subtitleStyle,
      timestampStyle: timestampStyle ?? this.timestampStyle,
      chipStyle: chipStyle ?? this.chipStyle,
      emptyState: emptyState ?? this.emptyState,
      leadingBuilder: leadingBuilder ?? this.leadingBuilder,
      trailingBuilder: trailingBuilder ?? this.trailingBuilder,
      dateFormat: dateFormat ?? this.dateFormat,
      dividerColor: dividerColor ?? this.dividerColor,
    );
  }
}
