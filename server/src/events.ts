import type { FcmTarget, NotificationEnvelope, SendReceipt } from "./types.ts";

export type NotificationServerEvent =
  | { type: "token.registered"; installationId: string; userId?: string; at: string }
  | { type: "token.unregistered"; installationId: string; at: string }
  | { type: "notification.send.started"; notificationId: string; targetCount: number; correlationId: string; at: string }
  | { type: "notification.send.completed"; notificationId: string; receipts: SendReceipt[]; correlationId: string; at: string }
  | { type: "notification.send.deduplicated"; notificationId: string; idempotencyKey: string; at: string }
  | { type: "notification.scheduled"; jobId: string; runAt: string; target: FcmTarget; envelope: NotificationEnvelope; at: string }
  | { type: "notification.dead_lettered"; jobId: string; reason: string; at: string };

export interface NotificationEventSink {
  emit(event: NotificationServerEvent): Promise<void> | void;
}
