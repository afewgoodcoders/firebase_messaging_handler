import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/fmh_analytics_service.dart';
import '../services/notification_delivery_policy_engine.dart';
import '../services/storage_service.dart';
import '../../enums/export.dart';
import '../../models/export.dart';
import '../../in_app/presentation/template_presenter.dart';

class InAppMessageManager {
  static InAppMessageManager? _instance;

  static InAppMessageManager get instance {
    _instance ??= InAppMessageManager._internal();
    return _instance!;
  }

  InAppMessageManager._internal();

  final StorageService _storageService = StorageService.instance;
  // Use the shared analytics singleton for in-app events.
  final FmhAnalyticsService _analyticsService = FmhAnalyticsService.instance;
  InAppDeliveryPolicy _deliveryPolicy = const InAppDeliveryPolicy();
  final Map<String, InAppDeliveryStats> _deliveryStats =
      <String, InAppDeliveryStats>{};
  InAppDeliveryStats _globalDeliveryStats = InAppDeliveryStats();
  bool _hasHydratedDeliveryHistory = false;
  NotificationDeliveryPolicyEngine? _sharedDeliveryPolicyEngine;
  void Function(NotificationDeliveryEvent event)? _deliveryEventSink;

  final Map<String, InAppNotificationTemplate> _templates =
      <String, InAppNotificationTemplate>{};
  final Set<String> _processedMessageIds = <String>{};
  final List<InAppNotificationData> _pendingMemoryQueue =
      <InAppNotificationData>[];
  StreamController<InAppNotificationData>? _streamController;
  bool _hasHydratedStorage = false;
  InAppNotificationDisplayCallback? _fallbackDisplay;
  bool _debugLoggingEnabled = false;

  /// Enables verbose package diagnostics in debug builds.
  void setDebugLogging(bool enabled) {
    _debugLoggingEnabled = enabled;
  }

  Stream<InAppNotificationData> getMessageStream({
    bool includePendingStorageItems = true,
  }) {
    _streamController ??= StreamController<InAppNotificationData>.broadcast(
      onListen: () {
        if (includePendingStorageItems) {
          unawaited(_deliverPendingFromStorage());
        }
      },
    );

    if (includePendingStorageItems && !_hasHydratedStorage) {
      unawaited(_deliverPendingFromStorage());
    }

    if (_pendingMemoryQueue.isNotEmpty) {
      for (final InAppNotificationData queued in _pendingMemoryQueue) {
        _streamController?.add(queued);
      }
      _pendingMemoryQueue.clear();
    }

    return _streamController!.stream;
  }

  void registerTemplates(Map<String, InAppNotificationTemplate> templates) {
    _templates.addAll(templates);
    _logMessage(
      '[InAppMessageManager] Registered templates: ${templates.keys.join(', ')}',
    );
  }

  void clearTemplates() {
    _templates.clear();
    _logMessage('[InAppMessageManager] Templates cleared');
  }

  void setFallbackDisplayHandler(
    InAppNotificationDisplayCallback? fallbackDisplay,
  ) {
    _fallbackDisplay = fallbackDisplay;
  }

  Future<void> setDeliveryPolicy(InAppDeliveryPolicy policy) async {
    await _ensureDeliveryHistoryLoaded();
    _deliveryPolicy = policy;
    await _persistDeliveryHistory();
  }

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    InAppTemplatePresenter.instance.configure(navigatorKey: key);
  }

  /// Applies the package-wide delivery policy to in-app messages.
  void configureDeliveryControls(
    NotificationDeliveryPolicyEngine engine,
    void Function(NotificationDeliveryEvent event) eventSink,
  ) {
    _sharedDeliveryPolicyEngine = engine;
    _deliveryEventSink = eventSink;
  }

  Future<void> handleRemoteMessage(RemoteMessage message) async {
    final Map<String, dynamic>? rawPayload = _extractInAppPayload(message.data);
    if (rawPayload == null) {
      return;
    }

    final String candidateId =
        rawPayload['id'] as String? ?? message.messageId ?? _generateTempId();
    if (_processedMessageIds.contains(candidateId)) {
      return;
    }

    final InAppNotificationData data = _buildNotificationData(
      candidateId,
      rawPayload,
      message,
    );

    _processedMessageIds.add(candidateId);
    _analyticsService.trackEvent('in_app_received', <String, dynamic>{
      'template_id': data.templateId,
      'trigger_type': data.triggerType.name,
      'message_id': data.id,
    });

    switch (data.triggerType) {
      case InAppTriggerTypeEnum.immediate:
        await _present(data);
        break;
      case InAppTriggerTypeEnum.nextForeground:
      case InAppTriggerTypeEnum.appLaunch:
        await _enqueuePending(data);
        break;
      case InAppTriggerTypeEnum.custom:
        /*
         * Why: Custom triggers are user-defined; we surface them immediately so the host
         * app can decide when and how to render based on its own heuristics.
         */
        await _present(data);
        break;
    }
  }

  Future<void> flushPendingInAppMessages() async {
    await _deliverPendingFromStorage();
  }

  Future<void> clearPendingInAppMessages({String? id}) async {
    await _storageService.clearPendingInAppMessages(id: id);
  }

  Future<void> dispose() async {
    await _streamController?.close();
    _streamController = null;
    _processedMessageIds.clear();
    _pendingMemoryQueue.clear();
    _hasHydratedStorage = false;
  }

  Future<void> triggerInAppNotification(InAppNotificationData data) async {
    _processedMessageIds.add(data.id);
    _analyticsService.trackEvent('in_app_triggered', {
      'template_id': data.templateId,
      'trigger_type': data.triggerType.name,
      'manual': true,
    });
    await _present(data);
  }

  Future<void> _enqueuePending(
    InAppNotificationData data, {
    DateTime? nextEligibleAt,
  }) async {
    _pendingMemoryQueue.add(data);
    await _storageService.savePendingInAppMessage(
      data.toMap(),
      nextEligibleAt: nextEligibleAt,
    );
    _logMessage(
      '[InAppMessageManager] Pending in-app message queued: '
      '${data.id} (next eligible: ${nextEligibleAt?.toIso8601String() ?? 'immediate'})',
    );
  }

  Future<void> _deliverPendingFromStorage() async {
    if (!_hasHydratedStorage) {
      _hasHydratedStorage = true;
    }
    final List<Map<String, dynamic>> stored = await _storageService
        .getPendingInAppMessages();
    if (stored.isEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    final List<Map<String, dynamic>> remaining = <Map<String, dynamic>>[];

    for (final Map<String, dynamic> item in stored) {
      try {
        final String? nextEligibleRaw = item['__nextEligibleAt'] as String?;
        final DateTime? nextEligibleAt = nextEligibleRaw != null
            ? DateTime.tryParse(nextEligibleRaw)
            : null;
        if (nextEligibleAt != null && nextEligibleAt.isAfter(now)) {
          remaining.add(item);
          continue;
        }
        final InAppNotificationData data = InAppNotificationData.fromMap(item);
        await _present(data);
      } catch (error, stack) {
        _logMessage(
          '[InAppMessageManager] Pending message hydration error: $error',
        );
        _logMessage('[InAppMessageManager] Stack trace: $stack');
      }
    }

    if (remaining.isEmpty) {
      await _storageService.clearPendingInAppMessages();
    } else {
      await _storageService.setPendingInAppMessages(remaining);
    }
  }

  Future<void> _present(InAppNotificationData data) async {
    await _ensureDeliveryHistoryLoaded();
    final DateTime now = DateTime.now();
    final NotificationDeliveryRequest request = NotificationDeliveryRequest(
      surface: NotificationDeliverySurface.inApp,
      lifecycle: NotificationLifecycle.foreground,
      messageId: data.id,
      categoryId:
          data.rawPayload['category']?.toString() ??
          data.content['category']?.toString(),
      data: data.rawPayload,
    );
    _emitDeliveryEvent(NotificationDeliveryEventType.received, request);
    final NotificationDeliveryDecision sharedDecision =
        _sharedDeliveryPolicyEngine?.evaluate(request) ??
        NotificationDeliveryDecision.allow;
    if (!sharedDecision.isAllowed) {
      _emitDeliveryEvent(
        sharedDecision.outcome == NotificationDeliveryOutcome.suppressed
            ? NotificationDeliveryEventType.suppressed
            : NotificationDeliveryEventType.deferred,
        request,
        reason: sharedDecision.reason,
        nextEligibleAt: sharedDecision.nextEligibleAt,
      );
      if (sharedDecision.nextEligibleAt != null) {
        await _enqueuePending(
          data,
          nextEligibleAt: sharedDecision.nextEligibleAt,
        );
      }
      return;
    }

    final InAppDeliveryDecision decision = _evaluateDeliveryDecision(
      data.templateId,
      now,
    );

    if (!decision.allowed) {
      if (decision.nextEligibleAt != null) {
        await _enqueuePending(data, nextEligibleAt: decision.nextEligibleAt);
      }
      _logMessage(
        '[InAppMessageManager] Delivery deferred for ${data.id}: '
        '${decision.reason ?? 'policy'}',
      );
      _emitDeliveryEvent(
        NotificationDeliveryEventType.deferred,
        request,
        reason: decision.reason,
        nextEligibleAt: decision.nextEligibleAt,
      );
      return;
    }

    _registerDelivery(data.templateId, now);
    await _persistDeliveryHistory();
    _emit(data);
    _sharedDeliveryPolicyEngine?.registerDelivery(request);
    _emitDeliveryEvent(NotificationDeliveryEventType.delivered, request);
  }

  void _emitDeliveryEvent(
    NotificationDeliveryEventType type,
    NotificationDeliveryRequest request, {
    String? reason,
    DateTime? nextEligibleAt,
  }) {
    _deliveryEventSink?.call(
      NotificationDeliveryEvent(
        type: type,
        surface: request.surface,
        messageId: request.messageId,
        timestamp: DateTime.now(),
        lifecycle: request.lifecycle,
        categoryId: request.categoryId,
        reason: reason,
        nextEligibleAt: nextEligibleAt,
        data: request.data,
      ),
    );
  }

  void _emit(InAppNotificationData data) {
    if (_streamController == null || !_streamController!.hasListener) {
      _pendingMemoryQueue.add(data);
    } else {
      _streamController?.add(data);
    }

    final InAppNotificationTemplate? template = _templates[data.templateId];
    if (template != null) {
      try {
        template.onDisplay(data);
      } catch (error, stack) {
        _logMessage('[InAppMessageManager] Template display error: $error');
        _logMessage('[InAppMessageManager] Stack trace: $stack');
      }
      return;
    }

    if (_fallbackDisplay != null) {
      try {
        _fallbackDisplay!.call(data);
      } catch (error, stack) {
        _logMessage('[InAppMessageManager] Fallback display error: $error');
        _logMessage('[InAppMessageManager] Stack trace: $stack');
      }
    }
  }

  Map<String, dynamic>? _extractInAppPayload(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return null;
    }

    final dynamic payloadCandidate =
        data['fcmh_inapp'] ?? data['in_app_payload'];
    if (payloadCandidate == null) {
      return null;
    }

    if (payloadCandidate is Map<String, dynamic>) {
      return Map<String, dynamic>.from(payloadCandidate);
    }

    if (payloadCandidate is String) {
      try {
        final dynamic decoded = jsonDecode(payloadCandidate);
        if (decoded is Map<String, dynamic>) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (error, stack) {
        _logMessage(
          '[InAppMessageManager] Payload decode error: $error for data: $payloadCandidate',
        );
        _logMessage('[InAppMessageManager] Stack trace: $stack');
      }
    }

    return null;
  }

  InAppNotificationData _buildNotificationData(
    String id,
    Map<String, dynamic> payload,
    RemoteMessage message,
  ) {
    final String templateId =
        payload['templateId'] as String? ??
        payload['template_id'] as String? ??
        'default';
    final InAppTriggerTypeEnum trigger = InAppTriggerTypeEnum.fromString(
      payload['trigger'] as String?,
    );

    final Map<String, dynamic> analyticsPayload =
        Map<String, dynamic>.from(
            payload['analytics'] as Map? ?? <String, dynamic>{},
          )
          ..putIfAbsent('campaign_id', () => payload['campaignId'])
          ..putIfAbsent('variant_id', () => payload['variant']);

    final Map<String, dynamic> reservedKeys = <String, dynamic>{
      'templateId': templateId,
      'template_id': templateId,
      'trigger': trigger.name,
      'analytics': analyticsPayload,
      'campaignId': payload['campaignId'],
      'variant': payload['variant'],
      'id': id,
      'autoDismissMs': payload['autoDismissMs'],
    };

    final Map<String, dynamic> content = <String, dynamic>{};
    if (payload['content'] is Map<String, dynamic>) {
      content.addAll(payload['content'] as Map<String, dynamic>);
    }

    if (content.isEmpty) {
      payload.forEach((String key, dynamic value) {
        if (!reservedKeys.containsKey(key)) {
          content[key] = value;
        }
      });
    }

    if (payload['autoDismissMs'] != null) {
      content['autoDismissMs'] = payload['autoDismissMs'];
    }

    return InAppNotificationData(
      id: id,
      templateId: templateId,
      triggerType: trigger,
      content: content,
      analytics: analyticsPayload,
      rawPayload: payload,
      receivedAt: message.sentTime ?? DateTime.now(),
    );
  }

  Future<void> _ensureDeliveryHistoryLoaded() async {
    if (_hasHydratedDeliveryHistory) {
      return;
    }
    final Map<String, dynamic> stored = await _storageService
        .getInAppDeliveryHistory();
    stored.forEach((String key, dynamic value) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(
        value as Map? ?? <String, dynamic>{},
      );
      final DateTime? lastShown = map['lastShown'] != null
          ? DateTime.tryParse(map['lastShown'] as String)
          : null;
      final Map<String, int> perDayCounts = <String, int>{};
      final Map<String, dynamic> counts = Map<String, dynamic>.from(
        map['perDayCounts'] as Map? ?? {},
      );
      counts.forEach((String k, dynamic v) {
        perDayCounts[k] = (v as num).toInt();
      });
      final stats = InAppDeliveryStats(
        lastShown: lastShown,
        perDayCounts: perDayCounts,
      );
      if (key == '__global') {
        _globalDeliveryStats = stats;
      } else {
        _deliveryStats[key] = stats;
      }
    });
    _hasHydratedDeliveryHistory = true;
  }

  Future<void> _persistDeliveryHistory() async {
    if (!_hasHydratedDeliveryHistory) {
      return;
    }
    final Map<String, dynamic> payload = <String, dynamic>{
      '__global': _statsToMap(_globalDeliveryStats),
    };
    _deliveryStats.forEach((String key, InAppDeliveryStats stats) {
      payload[key] = _statsToMap(stats);
    });
    await _storageService.saveInAppDeliveryHistory(payload);
  }

  Map<String, dynamic> _statsToMap(InAppDeliveryStats stats) =>
      <String, dynamic>{
        'lastShown': stats.lastShown?.toIso8601String(),
        'perDayCounts': stats.perDayCounts,
      };

  InAppDeliveryDecision _evaluateDeliveryDecision(
    String templateId,
    DateTime now,
  ) {
    final InAppDeliveryStats templateStats = _deliveryStats.putIfAbsent(
      templateId,
      () => InAppDeliveryStats(),
    );

    if (_deliveryPolicy.quietHours?.isQuiet(now) ?? false) {
      final DateTime next = _deliveryPolicy.quietHours!
          .nextAllowedTime(now)
          .toLocal();
      return InAppDeliveryDecision.defer(
        nextEligibleAt: next,
        reason: 'quiet_hours',
      );
    }

    if (_deliveryPolicy.globalInterval != null &&
        _globalDeliveryStats.lastShown != null) {
      final DateTime eligible = _globalDeliveryStats.lastShown!.add(
        _deliveryPolicy.globalInterval!,
      );
      if (eligible.isAfter(now)) {
        return InAppDeliveryDecision.defer(
          nextEligibleAt: eligible,
          reason: 'global_interval',
        );
      }
    }

    if (_deliveryPolicy.perTemplateInterval != null &&
        templateStats.lastShown != null) {
      final DateTime eligible = templateStats.lastShown!.add(
        _deliveryPolicy.perTemplateInterval!,
      );
      if (eligible.isAfter(now)) {
        return InAppDeliveryDecision.defer(
          nextEligibleAt: eligible,
          reason: 'template_interval',
        );
      }
    }

    final int templateCountToday = templateStats.countForDay(now);
    if (_deliveryPolicy.perTemplateDailyCap != null &&
        templateCountToday >= _deliveryPolicy.perTemplateDailyCap!) {
      final DateTime nextDay = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: 1));
      return InAppDeliveryDecision.defer(
        nextEligibleAt: nextDay,
        reason: 'template_daily_cap',
      );
    }

    final int globalCountToday = _globalDeliveryStats.countForDay(now);
    if (_deliveryPolicy.globalDailyCap != null &&
        globalCountToday >= _deliveryPolicy.globalDailyCap!) {
      final DateTime nextDay = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: 1));
      return InAppDeliveryDecision.defer(
        nextEligibleAt: nextDay,
        reason: 'global_daily_cap',
      );
    }

    return InAppDeliveryDecision.allow;
  }

  void _registerDelivery(String templateId, DateTime now) {
    final InAppDeliveryStats templateStats = _deliveryStats.putIfAbsent(
      templateId,
      () => InAppDeliveryStats(),
    );
    templateStats.register(now);
    _globalDeliveryStats.register(now);
  }

  String _generateTempId() =>
      'inapp_${DateTime.now().microsecondsSinceEpoch}_${_processedMessageIds.length}';

  Map<String, dynamic> getDeliveryDiagnostics(DateTime now) {
    final InAppQuietHours? quietHours = _deliveryPolicy.quietHours;
    return <String, dynamic>{
      'quietHoursActive': quietHours?.isQuiet(now) ?? false,
      'quietHours': quietHours == null
          ? null
          : {
              'startHour': quietHours.startHour,
              'startMinute': quietHours.startMinute,
              'endHour': quietHours.endHour,
              'endMinute': quietHours.endMinute,
            },
      'globalIntervalSeconds': _deliveryPolicy.globalInterval?.inSeconds,
      'perTemplateIntervalSeconds':
          _deliveryPolicy.perTemplateInterval?.inSeconds,
      'globalDailyCap': _deliveryPolicy.globalDailyCap,
      'perTemplateDailyCap': _deliveryPolicy.perTemplateDailyCap,
    };
  }

  void _logMessage(String message) {
    if (kDebugMode && _debugLoggingEnabled) {
      print(message);
    }
  }
}
