import 'dart:async';

import 'package:flutter/material.dart';

class InAppOverlayController {
  InAppOverlayController._(this._state);

  final _InAppOverlayHostState _state;

  bool get isShowing => _state._isShowing;

  void show({
    required WidgetBuilder builder,
    bool dismissible = true,
    Color barrierColor = const Color(0xB3000000),
    Duration? autoDismissAfter,
  }) {
    _state._show(
      builder: builder,
      dismissible: dismissible,
      barrierColor: barrierColor,
      autoDismissAfter: autoDismissAfter,
    );
  }

  Future<void> dismiss() => _state._dismiss();
}

class InAppOverlayHost extends StatefulWidget {
  const InAppOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  State<InAppOverlayHost> createState() => _InAppOverlayHostState();

  static InAppOverlayController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_InAppOverlayScope>()
        ?.controller;
  }

  static InAppOverlayController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller == null) {
      throw FlutterError(
        'InAppOverlayController.of(context) called with a context that does not contain '
        'an InAppOverlayHost. Make sure to wrap your app with InAppOverlayHost.',
      );
    }
    return controller;
  }
}

class _InAppOverlayHostState extends State<InAppOverlayHost> {
  late final InAppOverlayController _controller;
  WidgetBuilder? _activeBuilder;
  bool _dismissible = true;
  Color _barrierColor = const Color(0xB3000000);
  Timer? _autoDismissTimer;

  bool get _isShowing => _activeBuilder != null;

  @override
  void initState() {
    super.initState();
    _controller = InAppOverlayController._(this);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void _show({
    required WidgetBuilder builder,
    required bool dismissible,
    required Color barrierColor,
    Duration? autoDismissAfter,
  }) {
    _autoDismissTimer?.cancel();
    setState(() {
      _activeBuilder = builder;
      _dismissible = dismissible;
      _barrierColor = barrierColor;
    });

    if (autoDismissAfter != null) {
      _autoDismissTimer = Timer(autoDismissAfter, () {
        if (mounted && _isShowing) {
          _dismiss();
        }
      });
    }
  }

  Future<void> _dismiss() async {
    if (!_isShowing) return;
    _autoDismissTimer?.cancel();
    if (mounted) {
      setState(() {
        _activeBuilder = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InAppOverlayScope(
      controller: _controller,
      child: Stack(
        children: [
          widget.child,
          if (_activeBuilder != null)
            Positioned.fill(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_dismissible,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _dismissible ? _dismiss : null,
                        child: Container(color: _barrierColor),
                      ),
                    ),
                  ),
                  Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _activeBuilder!(context),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InAppOverlayScope extends InheritedWidget {
  const _InAppOverlayScope({required this.controller, required super.child});

  final InAppOverlayController controller;

  @override
  bool updateShouldNotify(covariant _InAppOverlayScope oldWidget) =>
      controller != oldWidget.controller;
}
