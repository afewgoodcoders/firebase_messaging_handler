import type { NotificationEnvelope } from "./types.ts";

export const MAX_FCM_DATA_BYTES = 4096;

const complexKeys = new Set([
  "actions",
  "titleLocArgs",
  "bodyLocArgs",
  "analytics",
  "platform",
  "data",
]);

const commands = new Set(["display", "cancel", "replace", "markRead", "silent"]);
const priorities = new Set(["normal", "high"]);
const remotePresentations = new Set(["client", "system"]);

export function validateEnvelope(envelope: NotificationEnvelope): string[] {
  const errors: string[] = [];
  if (envelope.schemaVersion !== 2) errors.push("schemaVersion must equal 2");
  if (!envelope.id?.trim()) errors.push("id is required");
  if (!commands.has(envelope.command)) errors.push("command is unsupported");
  if (envelope.priority != null && !priorities.has(envelope.priority)) {
    errors.push("priority must be normal or high");
  }
  if (
    envelope.remotePresentation != null &&
    !remotePresentations.has(envelope.remotePresentation)
  ) {
    errors.push("remotePresentation must be client or system");
  }
  if (
    (envelope.command === "display" || envelope.command === "replace") &&
    !envelope.title?.trim() &&
    !envelope.body?.trim() &&
    !envelope.titleLocKey?.trim() &&
    !envelope.bodyLocKey?.trim()
  ) {
    errors.push("display and replace commands require title or body content");
  }
  if (envelope.ttlSeconds != null && (envelope.ttlSeconds < 0 || envelope.ttlSeconds > 2_419_200)) {
    errors.push("ttlSeconds must be between 0 and 2419200");
  }
  const sentAt = parseTimestamp("sentAt", envelope.sentAt, errors);
  const expiresAt = parseTimestamp("expiresAt", envelope.expiresAt, errors);
  if (sentAt != null && expiresAt != null && expiresAt <= sentAt) {
    errors.push("expiresAt must be later than sentAt");
  }
  const actionIds = new Set<string>();
  for (const action of envelope.actions ?? []) {
    if (!action.id?.trim() || !action.title?.trim()) errors.push("action id and title are required");
    if (actionIds.has(action.id)) errors.push(`duplicate action id: ${action.id}`);
    actionIds.add(action.id);
  }
  return errors;
}

function parseTimestamp(name: string, value: string | undefined, errors: string[]): number | undefined {
  if (value == null) return undefined;
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) {
    errors.push(`${name} must be an ISO-8601 date-time`);
    return undefined;
  }
  return timestamp;
}

export function encodeEnvelope(envelope: NotificationEnvelope): Record<string, string> {
  const errors = validateEnvelope(envelope);
  if (errors.length) throw new Error(errors.join("; "));

  const data: Record<string, string> = {};
  for (const [key, value] of Object.entries(envelope)) {
    if (value == null) continue;
    data[key] = typeof value === "string" && !complexKeys.has(key)
      ? value
      : JSON.stringify(value);
  }
  const bytes = Buffer.byteLength(JSON.stringify(data), "utf8");
  if (bytes > MAX_FCM_DATA_BYTES) {
    throw new RangeError(`FCM data payload is ${bytes} bytes; maximum is ${MAX_FCM_DATA_BYTES}`);
  }
  return data;
}

export function previewEnvelope(envelope: NotificationEnvelope) {
  const data = encodeEnvelope(envelope);
  return {
    data,
    bytes: Buffer.byteLength(JSON.stringify(data), "utf8"),
    idempotencyKey: envelope.idempotencyKey ?? envelope.id,
    expiresAt: envelope.expiresAt,
  };
}
