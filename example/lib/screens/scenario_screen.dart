import 'dart:convert';

import 'package:clipboard/clipboard.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:provider/provider.dart';

import '../providers/notification_provider.dart';

class ScenarioScreen extends StatelessWidget {
  const ScenarioScreen({super.key, required this.notification});

  final NotificationData notification;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final payload = Map<String, dynamic>.from(notification.payload)
      ..removeWhere((key, value) => value == null);
    final prettyPayload = const JsonEncoder.withIndent('  ').convert(payload);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Scenario'),
        actions: [
          IconButton(
            tooltip: 'Copy payload JSON',
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await FlutterClipboard.copy(prettyPayload);
              messenger.showSnackBar(
                const SnackBar(content: Text('Payload copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroTitle(notification: notification),
          const SizedBox(height: 16),
          _KeyFacts(notification: notification, provider: provider),
          const SizedBox(height: 24),
          _ActionsOverview(notification: notification),
          const SizedBox(height: 24),
          _PayloadViewer(prettyPayload: prettyPayload),
        ],
      ),
    );
  }
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.notification});

  final NotificationData notification;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.campaign,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  notification.title ?? 'Untitled notification',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (notification.body != null) ...[
              const SizedBox(height: 8),
              Text(
                notification.body!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KeyFacts extends StatelessWidget {
  const _KeyFacts({required this.notification, required this.provider});

  final NotificationData notification;
  final NotificationProvider provider;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Key Facts',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _FactChip(
                  label: 'Type',
                  value: notification.type.name,
                  icon: Icons.layers,
                ),
                _FactChip(
                  label: 'Category',
                  value: notification.category ?? 'none',
                  icon: Icons.label,
                ),
                _FactChip(
                  label: 'Origin',
                  value: notification.isFromTerminated
                      ? 'Terminated'
                      : 'App session',
                  icon: Icons.history,
                ),
                if (notification.timestamp != null)
                  _FactChip(
                    label: 'Received',
                    value: notification.timestamp!
                        .toLocal()
                        .toIso8601String()
                        .substring(0, 19),
                    icon: Icons.schedule,
                  ),
                _FactChip(
                  label: 'Badge Count',
                  value: (notification.badgeCount ?? 0).toString(),
                  icon: Icons.confirmation_num,
                ),
                _FactChip(
                  label: 'Stored Notifications',
                  value: provider.notifications.length.toString(),
                  icon: Icons.inbox,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          Text(value),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
  }
}

class _ActionsOverview extends StatelessWidget {
  const _ActionsOverview({required this.notification});

  final NotificationData notification;

  @override
  Widget build(BuildContext context) {
    final actions = notification.actions ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.touch_app),
                const SizedBox(width: 8),
                Text(
                  'Available Actions (${actions.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (actions.isEmpty)
              const Text(
                'No interactive actions attached. Try the “Send Test Notification” demo to see action buttons in this view.',
              )
            else
              Column(
                children: actions
                    .map(
                      (action) => ListTile(
                        leading: Icon(
                          action.destructive
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          color: action.destructive
                              ? Colors.redAccent
                              : Colors.green,
                        ),
                        title: Text(action.title),
                        subtitle: action.payload != null
                            ? Text(
                                const JsonEncoder.withIndent(
                                  '  ',
                                ).convert(action.payload),
                              )
                            : const Text('No payload provided'),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _PayloadViewer extends StatelessWidget {
  const _PayloadViewer({required this.prettyPayload});

  final String prettyPayload;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.data_object),
                const SizedBox(width: 8),
                Text(
                  'Payload (${prettyPayload.length} chars)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  prettyPayload,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
