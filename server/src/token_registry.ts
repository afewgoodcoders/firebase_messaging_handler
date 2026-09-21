import type { TokenRegistration } from "./types.ts";

export interface TokenRegistry {
  upsert(registration: TokenRegistration): Promise<void>;
  getByInstallation(installationId: string): Promise<TokenRegistration | undefined>;
  listByUser(userId: string): Promise<TokenRegistration[]>;
  removeInstallation(installationId: string): Promise<void>;
  removeToken(token: string): Promise<void>;
  pruneStale(before: Date): Promise<number>;
}

export class InMemoryTokenRegistry implements TokenRegistry {
  readonly #registrations = new Map<string, TokenRegistration>();

  async upsert(registration: TokenRegistration): Promise<void> {
    for (const [installationId, existing] of this.#registrations) {
      if (existing.token === registration.token && installationId !== registration.installationId) {
        this.#registrations.delete(installationId);
      }
    }
    this.#registrations.set(registration.installationId, structuredClone(registration));
  }

  async getByInstallation(installationId: string): Promise<TokenRegistration | undefined> {
    const value = this.#registrations.get(installationId);
    return value ? structuredClone(value) : undefined;
  }

  async listByUser(userId: string): Promise<TokenRegistration[]> {
    return [...this.#registrations.values()]
      .filter((registration) => registration.userId === userId)
      .map((registration) => structuredClone(registration));
  }

  async removeInstallation(installationId: string): Promise<void> {
    this.#registrations.delete(installationId);
  }

  async removeToken(token: string): Promise<void> {
    for (const [installationId, registration] of this.#registrations) {
      if (registration.token === token) this.#registrations.delete(installationId);
    }
  }

  async pruneStale(before: Date): Promise<number> {
    let removed = 0;
    for (const [installationId, registration] of this.#registrations) {
      if (new Date(registration.updatedAt) < before) {
        this.#registrations.delete(installationId);
        removed += 1;
      }
    }
    return removed;
  }
}
