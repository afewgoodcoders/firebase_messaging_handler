import 'dart:async';

import 'package:flutter/material.dart';

class InAppTemplatePresenter {
  static final InAppTemplatePresenter instance =
      InAppTemplatePresenter._internal();

  InAppTemplatePresenter._internal();

  GlobalKey<NavigatorState>? _navigatorKey;

  void configure({GlobalKey<NavigatorState>? navigatorKey}) {
    _navigatorKey = navigatorKey;
  }

  BuildContext? get _context => _navigatorKey?.currentContext;

  OverlayState? get _overlayState => _navigatorKey?.currentState?.overlay;

  Future<T?> showDialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Color barrierColor = const Color(0xB3000000),
    String? barrierLabel,
    Duration transitionDuration = const Duration(milliseconds: 220),
    RouteTransitionsBuilder? transitionBuilder,
  }) async {
    final context = _context;
    if (context == null) {
      debugPrint('[InAppTemplatePresenter] No navigator context available.');
      return null;
    }

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel:
          barrierLabel ??
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: barrierColor,
      transitionDuration: transitionDuration,
      transitionBuilder: transitionBuilder,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    );
  }

  Future<T?> showBottomSheet<T>({
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    Color? backgroundColor,
    double? elevation,
    ShapeBorder? shape,
    Clip? clipBehavior,
    bool enableDrag = true,
  }) async {
    final context = _context;
    if (context == null) {
      debugPrint('[InAppTemplatePresenter] No navigator context available.');
      return null;
    }

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      enableDrag: enableDrag,
      builder: builder,
    );
  }

  Future<void> showSnackBar(SnackBar snackBar) async {
    final context = _context;
    if (context == null) {
      debugPrint('[InAppTemplatePresenter] No navigator context available.');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  Future<void> showOverlayEntry(
    Widget Function(BuildContext context, VoidCallback dismiss) builder, {
    Duration displayDuration = const Duration(seconds: 4),
  }) async {
    final overlay = _overlayState;
    if (overlay == null) {
      debugPrint('[InAppTemplatePresenter] No overlay available.');
      return;
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => builder(context, () {
        // Check if overlay is still available before removing
        if (overlay.mounted) {
          entry.remove();
        }
      }),
    );
    overlay.insert(entry);

    await Future<void>.delayed(displayDuration);

    // Check if overlay is still available before removing
    if (overlay.mounted) {
      entry.remove();
    }
  }
}
