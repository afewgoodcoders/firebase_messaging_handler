import { encodeEnvelope } from "./envelope.ts";
import type {
  FcmTarget,
  NotificationEnvelope,
  SendOptions,
  SendReceipt,
} from "./types.ts";

export interface FcmClientOptions {
  projectId: string;
  accessToken: () => Promise<string>;
  fetch?: typeof globalThis.fetch;
  maxAttempts?: number;
  baseDelayMs?: number;
  random?: () => number;
  sleep?: (milliseconds: number) => Promise<void>;
}

export class FcmClient {
  readonly #projectId: string;
  readonly #accessToken: () => Promise<string>;
  readonly #fetch: typeof globalThis.fetch;
  readonly #maxAttempts: number;
  readonly #baseDelayMs: number;
  readonly #random: () => number;
  readonly #sleep: (milliseconds: number) => Promise<void>;

  constructor(options: FcmClientOptions) {
    this.#projectId = options.projectId;
    this.#accessToken = options.accessToken;
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#maxAttempts = options.maxAttempts ?? 4;
    this.#baseDelayMs = options.baseDelayMs ?? 500;
    this.#random = options.random ?? Math.random;
    this.#sleep = options.sleep ?? ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
  }

  async send(
    target: FcmTarget,
    envelope: NotificationEnvelope,
    options: SendOptions = {},
  ): Promise<SendReceipt> {
    assertTarget(target);
    const data = encodeEnvelope(envelope);
    const message = this.#message(target, envelope, data);
    let attempts = 0;
    while (attempts < this.#maxAttempts) {
      attempts += 1;
      const response = await this.#fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(this.#projectId)}/messages:send`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${await this.#accessToken()}`,
            "content-type": "application/json",
            ...(options.correlationId ? { "x-correlation-id": options.correlationId } : {}),
          },
          body: JSON.stringify({ message, validate_only: options.dryRun ?? false }),
        },
      );
      const payload = await response.json().catch(() => ({})) as Record<string, unknown>;
      if (response.ok) {
        return {
          target,
          accepted: true,
          messageName: payload.name?.toString(),
          attempts,
          staleToken: false,
          correlationId: options.correlationId,
        };
      }
      const error = readFcmError(payload);
      const staleToken = error.code === "UNREGISTERED";
      if (!isRetryable(response.status) || attempts >= this.#maxAttempts) {
        return {
          target,
          accepted: false,
          errorCode: error.code ?? `HTTP_${response.status}`,
          errorMessage: error.message,
          attempts,
          staleToken,
          correlationId: options.correlationId,
        };
      }
      const retryAfter = parseRetryAfter(response.headers.get("retry-after"));
      const exponential = this.#baseDelayMs * 2 ** (attempts - 1);
      const jittered = Math.round(exponential * (0.5 + this.#random()));
      await this.#sleep(retryAfter ?? jittered);
    }
    throw new Error("unreachable");
  }

  #message(target: FcmTarget, envelope: NotificationEnvelope, data: Record<string, string>) {
    const systemPresentation =
      envelope.remotePresentation === "system" &&
      (envelope.command === "display" || envelope.command === "replace");
    const apple = envelope.platform?.apple ?? {};
    const appleHeaders = isRecord(apple.headers) ? apple.headers : {};
    const applePayload = isRecord(apple.payload) ? apple.payload : {};
    const appleAps = isRecord(applePayload.aps) ? applePayload.aps : {};
    const web = envelope.platform?.web ?? {};
    const webHeaders = isRecord(web.headers) ? web.headers : {};
    const android = {
      priority: envelope.priority === "normal" ? "NORMAL" : "HIGH",
      ttl: envelope.ttlSeconds == null ? undefined : `${envelope.ttlSeconds}s`,
      collapse_key: envelope.collapseKey,
      ...(envelope.platform?.android ?? {}),
    };
    const apns = {
      ...apple,
      headers: {
        "apns-push-type": systemPresentation ? "alert" : "background",
        "apns-priority": systemPresentation && envelope.priority !== "normal" ? "10" : "5",
        ...(envelope.ttlSeconds != null && envelope.sentAt
          ? { "apns-expiration": String(Math.floor(new Date(envelope.sentAt).getTime() / 1000) + envelope.ttlSeconds) }
          : {}),
        ...(envelope.collapseKey ? { "apns-collapse-id": envelope.collapseKey } : {}),
        ...appleHeaders,
      },
      payload: {
        ...applePayload,
        aps: {
          ...(!systemPresentation ? { "content-available": 1 } : {}),
          ...appleAps,
        },
      },
    };
    const webpush = {
      ...web,
      headers: {
        ...(envelope.ttlSeconds != null ? { TTL: String(envelope.ttlSeconds) } : {}),
        ...webHeaders,
      },
    };
    const notification = systemPresentation && (envelope.title || envelope.body || envelope.image)
      ? compact({ title: envelope.title, body: envelope.body, image: envelope.image })
      : undefined;
    return compact({ ...target, notification, data, android, apns, webpush });
  }
}

function assertTarget(target: FcmTarget): void {
  const entries = [target.token, target.topic, target.condition]
    .filter((value) => typeof value === "string" && value.trim().length > 0);
  if (entries.length !== 1) {
    throw new TypeError("FCM target must contain exactly one non-empty token, topic, or condition");
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function compact<T extends Record<string, unknown>>(value: T): T {
  for (const key of Object.keys(value)) {
    const child = value[key];
    if (child === undefined) delete value[key];
    else if (child && typeof child === "object" && !Array.isArray(child)) compact(child as Record<string, unknown>);
  }
  return value;
}

function isRetryable(status: number): boolean {
  return status === 429 || status === 500 || status === 502 || status === 503 || status === 504;
}

function parseRetryAfter(value: string | null): number | undefined {
  if (!value) return undefined;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000);
  const instant = Date.parse(value);
  return Number.isNaN(instant) ? undefined : Math.max(0, instant - Date.now());
}

function readFcmError(payload: Record<string, unknown>): { code?: string; message?: string } {
  const error = payload.error as Record<string, unknown> | undefined;
  const details = Array.isArray(error?.details) ? error.details as Record<string, unknown>[] : [];
  const fcmError = details.find((detail) => typeof detail.errorCode === "string");
  return { code: fcmError?.errorCode?.toString(), message: error?.message?.toString() };
}
