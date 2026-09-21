import type { FcmTarget, NotificationEnvelope, SendOptions } from "./types.ts";

export interface NotificationJob {
  id: string;
  target: FcmTarget;
  envelope: NotificationEnvelope;
  options?: SendOptions;
  runAt: string;
  attempts: number;
  lastError?: string;
}

export interface NotificationJobStore {
  schedule(job: NotificationJob): Promise<void>;
  cancel(id: string): Promise<boolean>;
  due(now: Date, limit: number): Promise<NotificationJob[]>;
  complete(id: string): Promise<void>;
  retry(job: NotificationJob, runAt: Date, error: string): Promise<void>;
  deadLetter(job: NotificationJob, error: string): Promise<void>;
}

export class InMemoryNotificationJobStore implements NotificationJobStore {
  readonly jobs = new Map<string, NotificationJob>();
  readonly deadLetters: NotificationJob[] = [];

  async schedule(job: NotificationJob): Promise<void> { this.jobs.set(job.id, structuredClone(job)); }
  async cancel(id: string): Promise<boolean> { return this.jobs.delete(id); }
  async due(now: Date, limit: number): Promise<NotificationJob[]> {
    return [...this.jobs.values()]
      .filter((job) => new Date(job.runAt) <= now)
      .sort((a, b) => a.runAt.localeCompare(b.runAt))
      .slice(0, limit)
      .map((job) => structuredClone(job));
  }
  async complete(id: string): Promise<void> { this.jobs.delete(id); }
  async retry(job: NotificationJob, runAt: Date, error: string): Promise<void> {
    this.jobs.set(job.id, { ...job, attempts: job.attempts + 1, runAt: runAt.toISOString(), lastError: error });
  }
  async deadLetter(job: NotificationJob, error: string): Promise<void> {
    this.jobs.delete(job.id);
    this.deadLetters.push({ ...job, lastError: error });
  }
}
