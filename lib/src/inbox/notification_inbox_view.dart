import 'package:flutter/material.dart';

import '../core/interfaces/notification_inbox_storage_interface.dart';
import '../models/notification_inbox_item.dart';
import 'notification_inbox_theme.dart';

typedef NotificationInboxItemTap = void Function(NotificationInboxItem item);

typedef NotificationInboxActionTap =
    void Function(String actionId, NotificationInboxItem item);

typedef NotificationInboxDelete = Future<void> Function(List<String> ids);

class NotificationInboxView extends StatefulWidget {
  const NotificationInboxView({
    super.key,
    required this.storage,
    this.pageSize = 20,
    this.onItemTap,
    this.onActionTap,
    this.onDelete,
    this.theme,
    this.enableSwipeToDelete = true,
    this.showDivider = true,
  });

  final NotificationInboxStorageInterface storage;
  final int pageSize;
  final NotificationInboxItemTap? onItemTap;
  final NotificationInboxActionTap? onActionTap;
  final NotificationInboxDelete? onDelete;
  final NotificationInboxTheme? theme;
  final bool enableSwipeToDelete;
  final bool showDivider;

  @override
  State<NotificationInboxView> createState() => _NotificationInboxViewState();
}

class _NotificationInboxViewState extends State<NotificationInboxView> {
  final List<NotificationInboxItem> _items = <NotificationInboxItem>[];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _page = 0;
      _hasMore = true;
      _items.clear();
    });
    await _loadPage(reset: true);
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) {
      return;
    }
    setState(() {
      _isLoadingMore = true;
    });
    await _loadPage(reset: false);
    setState(() {
      _isLoadingMore = false;
    });
  }

  Future<void> _loadPage({required bool reset}) async {
    final List<NotificationInboxItem> page = await widget.storage.fetch(
      page: reset ? 0 : _page,
      pageSize: widget.pageSize,
    );

    setState(() {
      if (reset) {
        _items
          ..clear()
          ..addAll(page);
      } else {
        _items.addAll(page);
      }
      _hasMore = page.length == widget.pageSize;
      if (page.isNotEmpty) {
        _page = reset ? 1 : _page + 1;
      }
    });
  }

  Future<void> _onRefresh() async {
    await _loadInitial();
  }

  Future<void> _onDeleteItems(List<String> ids) async {
    if (ids.isEmpty) {
      return;
    }
    await widget.storage.delete(ids);
    if (widget.onDelete != null) {
      await widget.onDelete!(ids);
    }
    setState(() {
      _items.removeWhere((NotificationInboxItem item) => ids.contains(item.id));
    });
  }

  Future<void> _onMarkRead(NotificationInboxItem item) async {
    if (item.isRead) {
      widget.onItemTap?.call(item);
      return;
    }
    await widget.storage.markRead(<String>[item.id]);
    setState(() {
      final int index = _items.indexWhere(
        (NotificationInboxItem it) => it.id == item.id,
      );
      if (index != -1) {
        _items[index] = item.copyWith(isRead: true);
      }
    });
    widget.onItemTap?.call(item.copyWith(isRead: true));
  }

  @override
  Widget build(BuildContext context) {
    final NotificationInboxTheme? theme = widget.theme;
    final Color? bg = theme?.backgroundColor;
    final Color divider = theme?.dividerColor ?? Colors.grey.shade200;

    final Widget child = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty
        ? theme?.emptyState ??
              const Center(child: Text('No notifications yet.'))
        : ListView.separated(
            itemCount: _items.length + (_hasMore ? 1 : 0),
            separatorBuilder: (_, _) => widget.showDivider
                ? Divider(height: 1, color: divider)
                : const SizedBox.shrink(),
            itemBuilder: (BuildContext context, int index) {
              if (index >= _items.length) {
                _loadMore();
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final NotificationInboxItem item = _items[index];
              return _buildTile(context, item, theme);
            },
          );

    return Container(
      color: bg,
      child: RefreshIndicator(onRefresh: _onRefresh, child: child),
    );
  }

  Widget _buildTile(
    BuildContext context,
    NotificationInboxItem item,
    NotificationInboxTheme? theme,
  ) {
    final TextStyle? titleStyle = item.isRead
        ? theme?.readTitleStyle
        : theme?.unreadTitleStyle;
    final Color? tileColor = item.isRead
        ? theme?.readBackgroundColor
        : theme?.unreadBackgroundColor;
    final Widget? leading = theme?.leadingBuilder?.call(context, item.isRead);
    final Widget? trailing = theme?.trailingBuilder?.call(context);
    final String timestampLabel =
        theme?.dateFormat?.call(item.timestamp) ??
        item.timestamp.toIso8601String();

    final List<Widget> actionChips = item.actions
        .map(
          (action) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(action.title),
              onPressed: () => widget.onActionTap?.call(action.id, item),
              shape: theme?.chipStyle?.shape,
              backgroundColor: theme?.chipStyle?.backgroundColor,
              labelStyle: theme?.chipStyle?.labelStyle,
            ),
          ),
        )
        .toList();

    final List<Widget> columnChildren = <Widget>[
      Text(
        item.title,
        style: titleStyle ?? Theme.of(context).textTheme.titleMedium,
      ),
      if (item.subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            item.subtitle!,
            style:
                theme?.subtitleStyle ?? Theme.of(context).textTheme.bodySmall,
          ),
        ),
      if (item.body.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(item.body, style: theme?.bodyStyle),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: DefaultTextStyle(
          style:
              (theme?.timestampStyle ??
                      Theme.of(context).textTheme.labelSmall ??
                      const TextStyle())
                  .copyWith(color: theme?.timestampStyle?.color ?? Colors.grey),
          child: Text(timestampLabel),
        ),
      ),
      if (actionChips.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(children: actionChips),
        ),
    ];

    final Widget content = ListTile(
      tileColor: tileColor,
      leading: leading,
      trailing: trailing,
      onTap: () => _onMarkRead(item),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columnChildren,
      ),
    );

    if (!widget.enableSwipeToDelete) {
      return content;
    }

    return Dismissible(
      key: ValueKey<String>(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: Colors.redAccent,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _onDeleteItems(<String>[item.id]),
      child: content,
    );
  }
}
