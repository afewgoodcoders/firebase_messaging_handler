export interface NotificationPrincipal {
  subject: string;
  roles: string[];
  claims?: Record<string, unknown>;
}

export interface NotificationRequestCredentials {
  authorization?: string;
  appCheckToken?: string;
}

export interface NotificationRequestAuthorizerOptions {
  verifyAccessToken: (token: string) => Promise<NotificationPrincipal>;
  verifyAppCheckToken?: (token: string) => Promise<void>;
  requireAppCheck?: boolean;
  requiredRoles?: string[];
}

export class NotificationAuthorizationError extends Error {
  readonly status: 401 | 403;
  readonly code: "missing_access_token" | "invalid_access_token" | "missing_app_check" | "invalid_app_check" | "insufficient_role";

  constructor(
    message: string,
    status: 401 | 403,
    code: "missing_access_token" | "invalid_access_token" | "missing_app_check" | "invalid_app_check" | "insufficient_role",
  ) {
    super(message);
    this.name = "NotificationAuthorizationError";
    this.status = status;
    this.code = code;
  }
}

/**
 * Validates a caller before it can register tokens or enqueue notification
 * work. Keep Firebase service-account credentials behind this boundary.
 */
export class NotificationRequestAuthorizer {
  readonly #options: NotificationRequestAuthorizerOptions;

  constructor(options: NotificationRequestAuthorizerOptions) {
    this.#options = options;
  }

  async authorize(credentials: NotificationRequestCredentials): Promise<NotificationPrincipal> {
    const authorization = credentials.authorization?.trim() ?? "";
    const match = /^Bearer\s+(.+)$/i.exec(authorization);
    if (!match) {
      throw new NotificationAuthorizationError("A bearer access token is required", 401, "missing_access_token");
    }

    let principal: NotificationPrincipal;
    try {
      principal = await this.#options.verifyAccessToken(match[1]);
    } catch {
      throw new NotificationAuthorizationError("The access token is invalid", 401, "invalid_access_token");
    }

    if (this.#options.requireAppCheck ?? true) {
      if (!credentials.appCheckToken) {
        throw new NotificationAuthorizationError("An App Check token is required", 401, "missing_app_check");
      }
      if (!this.#options.verifyAppCheckToken) {
        throw new TypeError("verifyAppCheckToken is required when App Check enforcement is enabled");
      }
      try {
        await this.#options.verifyAppCheckToken(credentials.appCheckToken);
      } catch {
        throw new NotificationAuthorizationError("The App Check token is invalid", 401, "invalid_app_check");
      }
    }

    const required = this.#options.requiredRoles ?? [];
    if (required.length > 0 && !required.some((role) => principal.roles.includes(role))) {
      throw new NotificationAuthorizationError("The caller is not allowed to send notifications", 403, "insufficient_role");
    }
    return principal;
  }
}
