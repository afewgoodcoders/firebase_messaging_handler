import { randomUUID } from "node:crypto";

import { previewEnvelope } from "./envelope.ts";
import type { FcmClient } from "./fcm_client.ts";
import type { NotificationJob, NotificationJobStore } from "./scheduler.ts";
import type { TokenRegistry } from "./token_registry.ts";
import type {
  FcmTarget,
  NotificationEnvelope,
  SendOptions,
  SendReceipt,
  TokenRegistration,
} from "./types.ts";
import type { NotificationEventSink, NotificationServerEvent } from "./events.ts";

export interface IdempotencyStore {
  claim(key: string, expiresAt: Date): Promise<boolean>;
}

export class InMemoryIdempotencyStore implements IdempotencyStore {
  readonly #claims = new Map<string, number>();

  async claim(key: string, expiresAt: Date): Promise<boolean> {
    const now = Date.now();
    for (const [claim, expiry] of this.#claims) if (expiry <= now) this.#claims.delete(claim);
    if (this.#claims.has(key)) return false;
    this.#claims.set(key, expiresAt.getTime());
    return true;
  }
}

export interface NotificationServerOptions {
  client: FcmClient;
  registry: TokenRegistry;
  idempotency?: IdempotencyStore;
  jobs?: NotificationJobStore;
  maxJobAttempts?: number;
  now?: () => Date;
  events?: NotificationEventSink;
}

export class NotificationServer {
  readonly #client: FcmClient;
  readonly #registry: TokenRegistry;
  readonly #idempotency: IdempotencyStore;
  readonly #jobs?: NotificationJobStore;
  readonly #maxJobAttempts: number;
  readonly #now: () => Date;
  readonly #events?: NotificationEventSink;

  constructor(options: NotificationServerOptions) {
    this.#client = options.client;
    this.#registry = options.registry;
    this.#idempotency = options.idempotency ?? new InMemoryIdempotencyStore();
    this.#jobs = options.jobs;
    this.#maxJobAttempts = options.maxJobAttempts ?? 5;
    this.#now = options.now ?? (() => new Date());
    this.#events = options.events;
  }

  async register(registration: TokenRegistration): Promise<void> {
    await this.#registry.upsert(registration);
    await this.#emit({
      type: "token.registered",
      installationId: registration.installationId,
      userId: registration.userId,
      at: this.#now().toISOString(),
    });
  }

  async unregister(installationId: string): Promise<void> {
    await this.#registry.removeInstallation(installationId);
    await this.#emit({ type: "token.unregistered", installationId, at: this.#now().toISOString() });
  }

  preview(envelope: NotificationEnvelope) { return previewEnvelope(envelope); }

  async sendToInstallation(
    installationId: string,
    envelope: NotificationEnvelope,
    options: SendOptions = {},
  ): Promise<SendReceipt[]> {
    const registration = await this.#registry.getByInstallation(installationId);
    if (!registration) return [];
    return this.sendToTargets([{ token: registration.token }], envelope, options);
  }

  async sendToUser(
    userId: string,
    envelope: NotificationEnvelope,
    options: SendOptions = {},
  ): Promise<SendReceipt[]> {
    const registrations = await this.#registry.listByUser(userId);
    return this.sendToTargets(registrations.map(({ token }) => ({ token })), envelope, options);
  }

  sendToTopic(topic: string, envelope: NotificationEnvelope, options: SendOptions = {}) {
    return this.sendToTargets([{ topic }], envelope, options);
  }

  sendToCondition(condition: string, envelope: NotificationEnvelope, options: SendOptions = {}) {
    return this.sendToTargets([{ condition }], envelope, options);
  }

  async sendToTargets(
    targets: FcmTarget[],
    envelope: NotificationEnvelope,
    options: SendOptions = {},
  ): Promise<SendReceipt[]> {
    const idempotencyKey = options.idempotencyKey ?? envelope.idempotencyKey ?? envelope.id;
    const expiry = envelope.expiresAt
      ? new Date(envelope.expiresAt)
      : new Date(this.#now().getTime() + Math.max(60, envelope.ttlSeconds ?? 86_400) * 1000);
    if (!(await this.#idempotency.claim(idempotencyKey, expiry))) {
      await this.#emit({
        type: "notification.send.deduplicated",
        notificationId: envelope.id,
        idempotencyKey,
        at: this.#now().toISOString(),
      });
      return [];
    }

    const receipts: SendReceipt[] = [];
    const correlationId = options.correlationId ?? randomUUID();
    await this.#emit({
      type: "notification.send.started",
      notificationId: envelope.id,
      targetCount: targets.length,
      correlationId,
      at: this.#now().toISOString(),
    });
    for (let offset = 0; offset < targets.length; offset += 500) {
      const batch = targets.slice(offset, offset + 500);
      const batchReceipts = await Promise.all(
        batch.map((target) => this.#client.send(target, envelope, {
          ...options,
          correlationId,
        })),
      );
      receipts.push(...batchReceipts);
      await Promise.all(
        batchReceipts
          .filter((receipt) => receipt.staleToken && receipt.target.token)
          .map((receipt) => this.#registry.removeToken(receipt.target.token!)),
      );
    }
    await this.#emit({
      type: "notification.send.completed",
      notificationId: envelope.id,
      receipts,
      correlationId,
      at: this.#now().toISOString(),
    });
    return receipts;
  }

  async schedule(
    id: string,
    runAt: Date,
    target: FcmTarget,
    envelope: NotificationEnvelope,
    options: SendOptions = {},
  ): Promise<void> {
    if (!this.#jobs) throw new Error("A NotificationJobStore is required for scheduling");
    if (runAt <= this.#now()) throw new RangeError("runAt must be in the future");
    await this.#jobs.schedule({ id, runAt: runAt.toISOString(), target, envelope, options, attempts: 0 });
    await this.#emit({
      type: "notification.scheduled",
      jobId: id,
      runAt: runAt.toISOString(),
      target,
      envelope,
      at: this.#now().toISOString(),
    });
  }

  async cancelScheduled(id: string): Promise<boolean> {
    if (!this.#jobs) return false;
    return this.#jobs.cancel(id);
  }

  async drainDueJobs(limit = 100): Promise<number> {
    if (!this.#jobs) return 0;
    const jobs = await this.#jobs.due(this.#now(), limit);
    for (const job of jobs) await this.#executeJob(job);
    return jobs.length;
  }

  async #executeJob(job: NotificationJob): Promise<void> {
    try {
      const receipts = await this.#client.send(job.target, job.envelope, job.options);
      if (receipts.accepted) {
        await this.#jobs!.complete(job.id);
      } else if (job.attempts + 1 >= this.#maxJobAttempts || receipts.staleToken) {
        const reason = receipts.errorMessage ?? receipts.errorCode ?? "send failed";
        await this.#jobs!.deadLetter(job, reason);
        await this.#emit({ type: "notification.dead_lettered", jobId: job.id, reason, at: this.#now().toISOString() });
      } else {
        const delay = Math.min(3_600_000, 1000 * 2 ** job.attempts);
        await this.#jobs!.retry(job, new Date(this.#now().getTime() + delay), receipts.errorMessage ?? "send failed");
      }
    } catch (error) {
      if (job.attempts + 1 >= this.#maxJobAttempts) {
        const reason = String(error);
        await this.#jobs!.deadLetter(job, reason);
        await this.#emit({ type: "notification.dead_lettered", jobId: job.id, reason, at: this.#now().toISOString() });
      } else {
        await this.#jobs!.retry(job, new Date(this.#now().getTime() + 1000 * 2 ** job.attempts), String(error));
      }
    }
  }

  async #emit(event: NotificationServerEvent): Promise<void> {
    await this.#events?.emit(event);
  }
}
