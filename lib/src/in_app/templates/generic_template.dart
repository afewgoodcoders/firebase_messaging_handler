import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../models/export.dart';
import '../presentation/template_presenter.dart';

typedef InAppTemplateActionCallback =
    void Function(String actionId, InAppNotificationData data);

class GenericTemplateButton {
  const GenericTemplateButton({
    required this.id,
    required this.label,
    this.style = GenericButtonStyle.filled,
    this.url,
    this.dismissOnly = false,
  });

  final String id;
  final String label;
  final GenericButtonStyle style;
  final String? url;
  final bool dismissOnly;
}

enum GenericButtonStyle { filled, outlined, text, link }

class GenericTemplateConfig {
  const GenericTemplateConfig({
    required this.layout,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.html,
    required this.imageUrl,
    required this.dismissible,
    required this.blurSigma,
    required this.barrierColor,
    required this.backgroundColor,
    required this.cornerRadius,
    required this.widthFactor,
    required this.heightFactor,
    required this.position,
    required this.buttons,
    required this.autoDismiss,
    required this.textColor,
    required this.pages,
  });

  final String layout;
  final String? title;
  final String? subtitle;
  final String? body;
  final String? html;
  final String? imageUrl;
  final bool dismissible;
  final double blurSigma;
  final Color barrierColor;
  final Color backgroundColor;
  final double cornerRadius;
  final double widthFactor;
  final double heightFactor;
  final String position;
  final List<GenericTemplateButton> buttons;
  final Duration? autoDismiss;
  final Color? textColor;
  final List<GenericTemplatePage> pages;

  static GenericTemplateConfig fromNotification(InAppNotificationData data) {
    final content = data.content;
    final layout = (content['layout'] ?? 'dialog').toString().toLowerCase();

    return GenericTemplateConfig(
      layout: layout,
      title: _string(content, 'title'),
      subtitle: _string(content, 'subtitle'),
      body: _string(content, 'body'),
      html: _string(content, 'html'),
      imageUrl: _string(content, 'imageUrl') ?? _string(content, 'image'),
      dismissible: _bool(content, 'dismissible') ?? true,
      blurSigma:
          _double(content, 'blurSigma') ?? (layout == 'dialog' ? 12.0 : 0.0),
      barrierColor: _color(content['barrierColor']) ?? const Color(0xB3000000),
      backgroundColor:
          _color(content['backgroundColor']) ?? const Color(0xFF111827),
      cornerRadius: _double(content, 'cornerRadius') ?? 18.0,
      widthFactor:
          _double(content, 'widthFactor') ?? _defaultWidthFactor(layout),
      heightFactor:
          _double(content, 'heightFactor') ?? _defaultHeightFactor(layout),
      position: (content['position'] ?? 'top').toString().toLowerCase(),
      buttons: _parseButtons(content['buttons']),
      autoDismiss: _duration(content, 'autoDismissSeconds'),
      textColor: _color(content['textColor']),
      pages: _parsePages(content['pages']),
    );
  }

  static double _defaultWidthFactor(String layout) {
    switch (layout) {
      case 'banner':
        return 1.0;
      case 'full_screen':
        return 1.0;
      case 'bottom_sheet':
        return 1.0;
      case 'tooltip':
        return 0.6;
      case 'carousel':
        return 0.9;
      default:
        return 0.85;
    }
  }

  static double _defaultHeightFactor(String layout) {
    switch (layout) {
      case 'full_screen':
        return 1.0;
      case 'bottom_sheet':
        return 0.55;
      case 'banner':
        return 0.18;
      case 'tooltip':
        return 0.0;
      case 'carousel':
        return 0.75;
      default:
        return 0.0; // auto
    }
  }

  static String? _string(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }

  static bool? _bool(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    return null;
  }

  static double? _double(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static Duration? _duration(Map<dynamic, dynamic> map, String key) {
    final seconds = _double(map, key);
    if (seconds == null) return null;
    if (seconds <= 0) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  static Color? _color(dynamic value) {
    if (value is int) {
      return Color(value);
    }
    if (value is String) {
      final hex = value.replaceAll('#', '').replaceAll('0x', '');
      if (hex.isEmpty) return null;
      final buffer = StringBuffer();
      if (hex.length == 6) buffer.write('FF');
      buffer.write(hex.toUpperCase());
      final intVal = int.tryParse(buffer.toString(), radix: 16);
      if (intVal != null) {
        return Color(intVal);
      }
    }
    if (value is Map) {
      final r = value['r'] ?? value['red'];
      final g = value['g'] ?? value['green'];
      final b = value['b'] ?? value['blue'];
      final a = value['a'] ?? value['alpha'] ?? 1.0;
      if (r is num && g is num && b is num) {
        final alpha = a is num ? a.toDouble() : 1.0;
        return Color.fromRGBO(
          r.clamp(0, 255).toInt(),
          g.clamp(0, 255).toInt(),
          b.clamp(0, 255).toInt(),
          alpha.clamp(0.0, 1.0),
        );
      }
    }
    return null;
  }

  static List<GenericTemplateButton> _parseButtons(dynamic value) {
    final List<GenericTemplateButton> buttons = [];
    if (value is List) {
      for (final item in value) {
        if (item is Map) {
          final id = (item['id'] ?? item['action'])?.toString();
          final label = item['label']?.toString();
          if (id == null || label == null) continue;
          final styleString = (item['style'] ?? 'filled')
              .toString()
              .toLowerCase();
          final style = GenericButtonStyle.values.firstWhere(
            (s) => s.name == styleString,
            orElse: () => GenericButtonStyle.filled,
          );
          buttons.add(
            GenericTemplateButton(
              id: id,
              label: label,
              style: style,
              url: _string(item, 'url') ?? _string(item, 'deepLink'),
              dismissOnly: _bool(item, 'dismissOnly') ?? false,
            ),
          );
        }
      }
    }
    return buttons;
  }

  static List<GenericTemplatePage> _parsePages(dynamic value) {
    final List<GenericTemplatePage> pages = [];
    if (value is List) {
      for (final item in value) {
        if (item is Map) {
          pages.add(GenericTemplatePage.fromMap(item));
        }
      }
    }
    return pages;
  }
}

class GenericTemplatePage {
  GenericTemplatePage({
    this.title,
    this.subtitle,
    this.body,
    this.html,
    this.imageUrl,
    this.backgroundColor,
    this.textColor,
    this.buttons = const <GenericTemplateButton>[],
  });

  final String? title;
  final String? subtitle;
  final String? body;
  final String? html;
  final String? imageUrl;
  final Color? backgroundColor;
  final Color? textColor;
  final List<GenericTemplateButton> buttons;

  factory GenericTemplatePage.fromMap(Map<dynamic, dynamic> map) {
    return GenericTemplatePage(
      title: GenericTemplateConfig._string(map, 'title'),
      subtitle: GenericTemplateConfig._string(map, 'subtitle'),
      body: GenericTemplateConfig._string(map, 'body'),
      html: GenericTemplateConfig._string(map, 'html'),
      imageUrl:
          GenericTemplateConfig._string(map, 'imageUrl') ??
          GenericTemplateConfig._string(map, 'image'),
      backgroundColor: GenericTemplateConfig._color(map['backgroundColor']),
      textColor: GenericTemplateConfig._color(map['textColor']),
      buttons: GenericTemplateConfig._parseButtons(map['buttons']),
    );
  }
}

class BuiltInInAppTemplates {
  const BuiltInInAppTemplates._();

  static InAppNotificationTemplate generic({
    InAppTemplateActionCallback? onAction,
  }) {
    return InAppNotificationTemplate(
      id: 'builtin_generic',
      description: 'Generic, multi-layout template with configurable payload.',
      onDisplay: (data) async {
        final presenter = InAppTemplatePresenter.instance;
        final config = GenericTemplateConfig.fromNotification(data);
        await _showWithLayout(presenter, config, data, onAction);
      },
    );
  }

  static Future<void> _showWithLayout(
    InAppTemplatePresenter presenter,
    GenericTemplateConfig config,
    InAppNotificationData data,
    InAppTemplateActionCallback? onAction,
  ) async {
    try {
      switch (config.layout) {
        case 'banner':
          await presenter.showOverlayEntry(
            (context, dismiss) => _BannerTemplate(
              config: config,
              data: data,
              onAction: onAction,
              onDismiss: dismiss,
            ),
            displayDuration: config.autoDismiss ?? const Duration(seconds: 5),
          );
          break;
        case 'bottom_sheet':
          await presenter.showBottomSheet(
            builder: (context) => _BottomSheetTemplate(
              config: config,
              data: data,
              onAction: onAction,
            ),
          );
          break;
        case 'snackbar':
          await presenter.showSnackBar(
            SnackBar(
              content: Text(config.body ?? config.title ?? ''),
              behavior: SnackBarBehavior.floating,
              duration: config.autoDismiss ?? const Duration(seconds: 4),
              backgroundColor: config.backgroundColor,
              action: config.buttons.isEmpty
                  ? null
                  : SnackBarAction(
                      label: config.buttons.first.label,
                      textColor: config.textColor,
                      onPressed: () =>
                          onAction?.call(config.buttons.first.id, data),
                    ),
            ),
          );
          break;
        case 'carousel':
          await presenter.showDialog(
            barrierDismissible: config.dismissible,
            barrierColor: config.barrierColor,
            builder: (context) => _CarouselTemplate(
              config: config,
              data: data,
              onAction: onAction,
            ),
          );
          break;
        case 'full_screen':
        case 'dialog':
        default:
          await presenter.showDialog(
            barrierDismissible: config.dismissible,
            barrierColor: config.barrierColor,
            transitionBuilder: (context, animation, secondary, child) {
              return BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: config.blurSigma,
                  sigmaY: config.blurSigma,
                ),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            builder: (context) =>
                _DialogTemplate(config: config, data: data, onAction: onAction),
          );
          break;
      }
    } catch (error, stackTrace) {
      debugPrint('[BuiltInInAppTemplates] Error showing template: $error');
      debugPrint('[BuiltInInAppTemplates] Stack trace: $stackTrace');
    }
  }
}

class _DialogTemplate extends StatelessWidget {
  const _DialogTemplate({
    required this.config,
    required this.data,
    this.onAction,
  });

  final GenericTemplateConfig config;
  final InAppNotificationData data;
  final InAppTemplateActionCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final double width = media.width * config.widthFactor;
    final double height = config.heightFactor > 0
        ? media.height * max(0.3, min(config.heightFactor, 0.9))
        : double.nan;

    final content = _TemplateContent(
      config: config,
      data: data,
      onAction: onAction,
      onDismiss: () => Navigator.of(context, rootNavigator: true).maybePop(),
    );

    final child = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: min(520, width),
        maxHeight: height.isNaN ? double.infinity : height,
      ),
      child: Material(
        color: config.backgroundColor,
        borderRadius: BorderRadius.circular(config.cornerRadius),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );

    if (config.layout == 'full_screen') {
      return SizedBox.expand(child: child);
    }

    return Center(child: child);
  }
}

class _BottomSheetTemplate extends StatelessWidget {
  const _BottomSheetTemplate({
    required this.config,
    required this.data,
    this.onAction,
  });

  final GenericTemplateConfig config;
  final InAppNotificationData data;
  final InAppTemplateActionCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: config.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewPadding.bottom + 8,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: _TemplateContent(
          config: config,
          data: data,
          onAction: onAction,
          onDismiss: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}

// Removed tooltip template functionality as requested
/*
class _TooltipTemplate extends StatelessWidget {
  const _TooltipTemplate({
    required this.config,
    required this.data,
    this.onAction,
    required this.onDismiss,
  });

  final GenericTemplateConfig config;
  final InAppNotificationData data;
  final InAppTemplateActionCallback? onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final alignment = _alignmentFromPosition(config.position);
    final bubble = Material(
      color: config.backgroundColor,
      borderRadius: BorderRadius.circular(config.cornerRadius),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: _TemplateContent(
          config: config,
          data: data,
          onAction: onAction,
          isCompact: true,
          onDismiss: onDismiss,
        ),
      ),
    );

    Widget child;
    switch (config.position) {
      case 'bottom':
        child = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tooltipArrow('top'),
            const SizedBox(height: 6),
            bubble,
          ],
        );
        break;
      case 'left':
        child = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            bubble,
            const SizedBox(width: 8),
            _tooltipArrow('right'),
          ],
        );
        break;
      case 'right':
        child = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tooltipArrow('left'),
            const SizedBox(width: 8),
            bubble,
          ],
        );
        break;
      case 'top':
      default:
        child = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            bubble,
            const SizedBox(height: 6),
            _tooltipArrow('bottom'),
          ],
        );
        break;
    }

    return SafeArea(
      child: IgnorePointer(
        ignoring: false,
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  Alignment _alignmentFromPosition(String position) {
    switch (position) {
      case 'bottom':
        return Alignment.bottomCenter;
      case 'left':
        return Alignment.centerLeft;
      case 'right':
        return Alignment.centerRight;
      case 'top':
      default:
        return Alignment.topCenter;
    }
  }

  Widget _tooltipArrow(String direction) {
    return SizedBox(
      width: 18,
      height: 12,
      child: CustomPaint(
        painter: _TrianglePainter(
          color: config.backgroundColor,
          direction: direction,
        ),
      ),
    );
  }
}

*/

class _CarouselTemplate extends StatefulWidget {
  const _CarouselTemplate({
    required this.config,
    required this.data,
    this.onAction,
  });

  final GenericTemplateConfig config;
  final InAppNotificationData data;
  final InAppTemplateActionCallback? onAction;

  @override
  State<_CarouselTemplate> createState() => _CarouselTemplateState();
}

class _CarouselTemplateState extends State<_CarouselTemplate> {
  late final PageController _pageController;
  int _currentIndex = 0;

  List<GenericTemplatePage> get _pages => widget.config.pages.isNotEmpty
      ? widget.config.pages
      : [
          GenericTemplatePage(
            title: widget.config.title,
            subtitle: widget.config.subtitle,
            body: widget.config.body,
            html: widget.config.html,
            imageUrl: widget.config.imageUrl,
            buttons: widget.config.buttons,
          ),
        ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final double width = min<double>(
      520.0,
      media.width * widget.config.widthFactor,
    );
    final double heightFactor;
    if (widget.config.heightFactor > 0) {
      final num clamped = widget.config.heightFactor.clamp(0.4, 0.9);
      heightFactor = clamped.toDouble();
    } else {
      heightFactor = 0.6;
    }
    final height = media.height * heightFactor;

    final pages = _pages;
    final currentPage = pages[_currentIndex];

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: BoxConstraints(maxWidth: width, maxHeight: height),
        decoration: BoxDecoration(
          color: currentPage.backgroundColor ?? widget.config.backgroundColor,
          borderRadius: BorderRadius.circular(widget.config.cornerRadius),
        ),
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                },
                itemBuilder: (context, index) => SingleChildScrollView(
                  child: _TemplateContent(
                    config: widget.config,
                    data: widget.data,
                    onAction: widget.onAction,
                    onDismiss: () =>
                        Navigator.of(context, rootNavigator: true).maybePop(),
                    page: pages[index],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (pages.length > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _currentIndex ? 10 : 6,
                      height: i == _currentIndex ? 10 : 6,
                      decoration: BoxDecoration(
                        color: i == _currentIndex
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _BannerTemplate extends StatelessWidget {
  const _BannerTemplate({
    required this.config,
    required this.data,
    this.onAction,
    required this.onDismiss,
  });

  final GenericTemplateConfig config;
  final InAppNotificationData data;
  final InAppTemplateActionCallback? onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final banner = Align(
      alignment: config.position == 'bottom'
          ? Alignment.bottomCenter
          : Alignment.topCenter,
      child: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Material(
          color: config.backgroundColor,
          elevation: 10,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: media.width * 0.94,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: _BannerContent(
              config: config,
              data: data,
              onAction: onAction,
              onDismiss: onDismiss,
            ),
          ),
        ),
      ),
    );

    return IgnorePointer(ignoring: false, child: banner);
  }
}

class _BannerContent extends StatelessWidget {
  const _BannerContent({
    required this.config,
    required this.data,
    this.onAction,
    required this.onDismiss,
  });

  final GenericTemplateConfig config;
  final InAppNotificationData data;
  final InAppTemplateActionCallback? onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    final textColor = config.textColor ?? Colors.white;
    final title = config.title;
    final body = config.body;
    final buttons = config.buttons;

    // Title
    if (title != null) {
      children.add(
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
    }

    // Body
    if (body != null) {
      children.add(
        Text(
          body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: textColor.withValues(alpha: 0.9),
            fontSize: 14,
          ),
        ),
      );
      children.add(const SizedBox(height: 16));
    }

    // Buttons
    if (buttons.isNotEmpty) {
      children.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: buttons
              .map((button) => _buildBannerButton(context, button))
              .toList(),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _buildBannerButton(
    BuildContext context,
    GenericTemplateButton button,
  ) {
    void handlePressed() {
      onDismiss();
      if (!button.dismissOnly) {
        onAction?.call(button.id, data);
      }
    }

    final textColor = config.textColor ?? Colors.white;

    switch (button.style) {
      case GenericButtonStyle.outlined:
        return OutlinedButton(
          onPressed: handlePressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            side: BorderSide(color: textColor.withValues(alpha: 0.3)),
            foregroundColor: textColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(button.label),
        );
      case GenericButtonStyle.text:
        return TextButton(
          onPressed: handlePressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            foregroundColor: textColor.withValues(alpha: 0.8),
          ),
          child: Text(button.label),
        );
      case GenericButtonStyle.link:
        return TextButton(
          onPressed: handlePressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            foregroundColor: textColor.withValues(alpha: 0.8),
          ),
          child: Text(
            button.label,
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        );
      case GenericButtonStyle.filled:
        return FilledButton(
          onPressed: handlePressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            backgroundColor: textColor,
            foregroundColor: config.backgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(button.label),
        );
    }
  }
}

class _TemplateContent extends StatelessWidget {
  const _TemplateContent({
    required this.config,
    required this.data,
    this.onAction,
    // ignore: unused_element_parameter
    this.isCompact = false,
    this.page,
    required this.onDismiss,
  });

  final GenericTemplateConfig config;
  final InAppNotificationData data;
  final InAppTemplateActionCallback? onAction;
  final bool isCompact;
  final GenericTemplatePage? page;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    final textColor = page?.textColor ?? config.textColor ?? Colors.white;
    final imageUrl = page?.imageUrl ?? config.imageUrl;
    final title = page?.title ?? config.title;
    final subtitle = page?.subtitle ?? config.subtitle;
    final html = page?.html ?? config.html;
    final body = page?.body ?? config.body;
    final buttons = (page?.buttons.isNotEmpty ?? false)
        ? page!.buttons
        : config.buttons;

    if (imageUrl != null) {
      children.add(
        ClipRRect(
          borderRadius: BorderRadius.circular(config.cornerRadius - 4),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.white.withValues(alpha: 0.1),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.image_not_supported,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ),
      );
      children.add(const SizedBox(height: 16));
    }

    if (title != null) {
      children.add(
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      children.add(const SizedBox(height: 12));
    }

    if (subtitle != null) {
      children.add(
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: textColor.withValues(alpha: 0.85),
          ),
        ),
      );
      children.add(const SizedBox(height: 12));
    }

    if (html != null) {
      children.add(
        HtmlWidget(
          html,
          textStyle: TextStyle(color: textColor.withValues(alpha: 0.9)),
        ),
      );
    } else if (body != null) {
      children.add(
        Text(
          body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: textColor.withValues(alpha: 0.9),
          ),
        ),
      );
    }

    if (body != null || html != null) {
      children.add(const SizedBox(height: 24));
    }

    if (buttons.isNotEmpty) {
      final buttonWidgets = buttons
          .map((button) => _buildButton(context, button))
          .toList();

      if (isCompact) {
        children.add(Wrap(spacing: 8, runSpacing: 8, children: buttonWidgets));
      } else {
        children.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < buttonWidgets.length; i++) ...[
                buttonWidgets[i],
                if (i < buttonWidgets.length - 1) const SizedBox(height: 16),
              ],
            ],
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildButton(BuildContext context, GenericTemplateButton button) {
    void handlePressed() {
      onDismiss();
      if (!button.dismissOnly) {
        onAction?.call(button.id, data);
      }
    }

    switch (button.style) {
      case GenericButtonStyle.outlined:
        return OutlinedButton(
          onPressed: handlePressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            foregroundColor: Colors.white,
          ),
          child: Text(button.label),
        );
      case GenericButtonStyle.text:
        return TextButton(
          onPressed: handlePressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            foregroundColor: Colors.white.withValues(alpha: 0.8),
          ),
          child: Text(button.label),
        );
      case GenericButtonStyle.link:
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: handlePressed,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              foregroundColor: Colors.white.withValues(alpha: 0.8),
            ),
            child: Text(
              button.label,
              style: const TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        );
      case GenericButtonStyle.filled:
        return FilledButton(
          onPressed: handlePressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
          ),
          child: Text(button.label),
        );
    }
  }
}
