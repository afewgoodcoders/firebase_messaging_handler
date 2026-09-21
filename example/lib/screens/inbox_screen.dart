import 'package:flutter/material.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final InboxStorageService _storage = InboxStorageService();
  int _refreshKey = 0;
  bool _seeding = false;
  bool _clearing = false;
  int? _unreadCount;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    final int count = await _storage.count(unreadOnly: true);
    if (!mounted) return;
    setState(() => _unreadCount = count);
  }

  Future<void> _seedDemoData() async {
    if (_seeding) return;
    setState(() => _seeding = true);

    final DateTime now = DateTime.now();
    final List<NotificationInboxItem> samples = <NotificationInboxItem>[
      NotificationInboxItem(
        id: 'welcome-${now.millisecondsSinceEpoch}',
        title: 'Welcome to Inbox',
        body: 'Swipe to delete, tap to mark read, pull to refresh.',
        subtitle: 'Demonstrates theming + callbacks',
        timestamp: now,
        actions: const <NotificationAction>[
          NotificationAction(
            id: 'open',
            title: 'Open',
            payload: <String, dynamic>{'route': '/scenario'},
          ),
          NotificationAction(id: 'later', title: 'Later', destructive: false),
        ],
        data: const <String, dynamic>{'campaign': 'inbox_demo', 'cta': 'open'},
      ),
      NotificationInboxItem(
        id: 'promo-${now.millisecondsSinceEpoch + 1}',
        title: '50% off Pro',
        body: 'Upgrade before midnight to lock in pricing.',
        subtitle: 'Category: promotion',
        timestamp: now.subtract(const Duration(hours: 2)),
        imageUrl: 'https://via.placeholder.com/80x80/111827/FFFFFF?text=SALE',
        actions: const <NotificationAction>[
          NotificationAction(
            id: 'view_offer',
            title: 'View offer',
            payload: <String, dynamic>{'deep_link': 'app://promo'},
          ),
        ],
        category: 'promotion',
      ),
      NotificationInboxItem(
        id: 'update-${now.millisecondsSinceEpoch + 2}',
        title: 'Background delivery enabled',
        body: 'We will deliver notifications even when the app is closed.',
        timestamp: now.subtract(const Duration(days: 1)),
        isRead: true,
        data: const <String, dynamic>{'type': 'status'},
      ),
    ];

    for (final NotificationInboxItem item in samples) {
      await _storage.upsert(item);
    }

    if (!mounted) return;
    setState(() {
      _seeding = false;
      _refreshKey++;
    });
    await _loadUnreadCount();
    _showSnack('Seeded demo inbox items');
  }

  Future<void> _clearInbox() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    await _storage.clear();
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _refreshKey++;
      _unreadCount = 0;
    });
    _showSnack('Cleared inbox');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  NotificationInboxTheme _theme(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return NotificationInboxTheme(
      backgroundColor: Colors.grey.shade50,
      unreadBackgroundColor: Colors.white,
      readBackgroundColor: Colors.grey.shade100,
      unreadTitleStyle: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      readTitleStyle: textTheme.titleMedium,
      bodyStyle: textTheme.bodyMedium,
      subtitleStyle: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
      timestampStyle: textTheme.labelSmall?.copyWith(
        color: Colors.grey.shade600,
      ),
      dividerColor: Colors.grey.shade200,
      chipStyle: const ChipThemeData(
        backgroundColor: Color(0xFFEFF6FF),
        labelStyle: TextStyle(color: Color(0xFF1D4ED8)),
      ),
      emptyState: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No notifications yet. Seed some demo items.'),
        ),
      ),
      leadingBuilder: (BuildContext context, bool isRead) {
        return CircleAvatar(
          backgroundColor: isRead
              ? Colors.grey.shade300
              : const Color(0xFF2563EB),
          child: Icon(
            Icons.notifications,
            color: isRead ? Colors.grey.shade800 : Colors.white,
          ),
        );
      },
      trailingBuilder: (BuildContext context) =>
          const Icon(Icons.chevron_right, color: Colors.grey),
      dateFormat: (DateTime ts) => _formatTimestamp(ts),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final Duration delta = DateTime.now().difference(timestamp);
    if (delta.inMinutes < 1) return 'Just now';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final String subtitle = _unreadCount == null
        ? 'Loading unread count...'
        : 'Unread: $_unreadCount';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Inbox'),
        actions: [
          IconButton(
            onPressed: _seeding ? null : _seedDemoData,
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Seed demo data',
          ),
          IconButton(
            onPressed: _clearing ? null : _clearInbox,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear inbox',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Persisted inbox with theming hooks',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Backed by InboxStorageService (SharedPreferences). '
                  'Swipe to delete, pull to refresh, tap to mark as read.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: NotificationInboxView(
              key: ValueKey<int>(_refreshKey),
              storage: _storage,
              onItemTap: (NotificationInboxItem item) {
                _loadUnreadCount();
                _showSnack('Opened "${item.title}"');
              },
              onActionTap: (String actionId, NotificationInboxItem item) {
                _showSnack('Action "$actionId" from "${item.title}"');
              },
              onDelete: (List<String> ids) async {
                await _loadUnreadCount();
              },
              theme: _theme(context),
            ),
          ),
        ],
      ),
    );
  }
}
