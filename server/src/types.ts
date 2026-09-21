export type NotificationCommand =
  | "display"
  | "cancel"
  | "replace"
  | "markRead"
  | "silent";

export interface NotificationAction {
  id: string;
  title: string;
  destructive?: boolean;
  foreground?: boolean;
  requiresAuthentication?: boolean;
  cancelNotification?: boolean;
  textInput?: boolean;
  inputLabel?: string;
  inputButtonTitle?: string;
  inputChoices?: string[];
  allowFreeFormInput?: boolean;
  payload?: Record<string, unknown>;
}

export interface NotificationEnvelope {
  schemaVersion: 2;
  id: string;
  idempotencyKey?: string;
  command: NotificationCommand;
  title?: string;
  body?: string;
  titleLocKey?: string;
  titleLocArgs?: string[];
  bodyLocKey?: string;
  bodyLocArgs?: string[];
  category?: string;
  route?: string;
  image?: string;
  sound?: string;
  channelId?: string;
  actions?: NotificationAction[];
  ttlSeconds?: number;
  priority?: "normal" | "high";
  remotePresentation?: "client" | "system";
  collapseKey?: string;
  dedupeKey?: string;
  sentAt?: string;
  expiresAt?: string;
  storeInInbox?: boolean;
  updateBadge?: boolean;
  presentInApp?: boolean;
  analytics?: Record<string, unknown>;
  platform?: {
    android?: Record<string, unknown>;
    apple?: Record<string, unknown>;
    web?: Record<string, unknown>;
  };
  data?: Record<string, unknown>;
}

export type DevicePlatform = "android" | "ios" | "macos" | "web";

export interface TokenRegistration {
  installationId: string;
  token: string;
  userId?: string;
  platform: DevicePlatform;
  appVersion?: string;
  locale?: string;
  timezone?: string;
  permission?: "authorized" | "provisional" | "denied" | "unknown";
  topics?: string[];
  preferences?: Record<string, boolean>;
  updatedAt: string;
}

export interface FcmTarget {
  token?: string;
  topic?: string;
  condition?: string;
}

export interface SendOptions {
  dryRun?: boolean;
  idempotencyKey?: string;
  correlationId?: string;
}

export interface SendReceipt {
  target: FcmTarget;
  accepted: boolean;
  messageName?: string;
  errorCode?: string;
  errorMessage?: string;
  attempts: number;
  staleToken: boolean;
  correlationId?: string;
}
