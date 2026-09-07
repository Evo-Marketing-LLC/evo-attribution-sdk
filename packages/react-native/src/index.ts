/** The package version sent with every attribution request. */
export const EVO_ATTRIBUTION_VERSION = "0.1.0";

/** A mobile platform accepted by EVO's install attribution endpoint. */
export type EvoPlatform = "ios" | "android";

/** The storage surface used to persist EVO's installation state. */
export interface EvoStorage {
  getItem(key: string): Promise<string | null> | string | null;
  setItem(key: string, value: string): Promise<void> | void;
}

/** Options used to configure attribution once during app startup. */
export interface EvoAttributionOptions {
  pixelKey: string;
  platform: EvoPlatform;
  storage: EvoStorage;
  endpoint?: string;
  appVersion?: string;
  getClipboard?: () => Promise<string | null>;
}

/** Optional metadata for a purchase attribution event. */
export interface TrackPurchaseOptions {
  /** Mark a TestFlight or store-sandbox purchase so it is excluded from production totals. */
  sandbox?: boolean;
}

/** The successful install response returned by EVO's attribution API. */
export interface InstallResult {
  ok: boolean;
  duplicate: boolean;
  install: {
    install_id: string;
    platform: EvoPlatform;
    attributed: boolean;
    resolution_method: "clipboard" | "code" | "ip" | "unattributed";
    confidence: number;
    link: { id: number; domain: string; slug: string } | null;
    code: string | null;
    creator: { id: string; name: string | null } | null;
  };
}

const INSTALL_ID_KEY = "evo_install_id";
const INSTALL_REPORTED_KEY = "evo_install_reported";
let options: EvoAttributionOptions | null = null;

/** Configure EVO attribution once during app startup. */
export function configureEvoAttribution(next: EvoAttributionOptions): void {
  options = {
    ...next,
    endpoint: (next.endpoint ?? "https://dialedapi.evomarketing.co").replace(/\/$/, ""),
  };
}

/** Return the persistent installation UUID used by RevenueCat and Superwall. */
export async function getEvoInstallId(): Promise<string> {
  const config = options;
  if (!config) throw new Error("configureEvoAttribution must be called before getEvoInstallId");

  return persistentInstallId(config);
}

/**
 * Report this installation once. Pass true only when the app has permission to
 * read the clipboard. A network failure remains pending for the next launch.
 * Pass `code` when the new user typed a creator code in the app: it credits
 * that creator when no clipboard token is available.
 */
export async function trackInstall(
  readClipboard = false,
  code?: string,
): Promise<InstallResult | null> {
  const config = options;
  if (!config) {
    warn("configureEvoAttribution must be called before trackInstall");
    return null;
  }

  try {
    if ((await config.storage.getItem(INSTALL_REPORTED_KEY)) === "true") return null;

    const installId = await persistentInstallId(config);
    let clipboardToken: string | undefined;
    if (readClipboard && config.getClipboard) {
      const value = (await config.getClipboard())?.trim();
      if (value?.startsWith("evc_")) clipboardToken = value;
    }

    const response = await post(config, "api/public/attribution/installs", {
      pixel_key: config.pixelKey,
      install_id: installId,
      platform: config.platform,
      clipboard_token: clipboardToken,
      code: code?.trim() || undefined,
      app_version: config.appVersion,
      sdk_version: EVO_ATTRIBUTION_VERSION,
      occurred_at: new Date().toISOString(),
    });
    if (!response) return null;

    await config.storage.setItem(INSTALL_REPORTED_KEY, "true");
    return (await response.json()) as InstallResult;
  } catch (error) {
    warn(`Install attribution failed: ${messageFor(error)}`);
    return null;
  }
}

/**
 * Report a purchase. `transactionId` is the server-side deduplication key.
 * Pass `code` when the buyer entered a creator code at checkout. Set
 * `options.sandbox` for TestFlight or store-sandbox transactions.
 */
export async function trackPurchase(
  transactionId: string,
  amount: number,
  currency = "USD",
  code?: string,
  purchaseOptions?: TrackPurchaseOptions,
): Promise<void> {
  const config = options;
  if (!config) {
    warn("configureEvoAttribution must be called before trackPurchase");
    return;
  }

  try {
    const installId = await persistentInstallId(config);
    await post(config, "api/public/attribution/events", {
      pixel_key: config.pixelKey,
      event_type: "purchase",
      source: "sdk",
      external_user_id: installId,
      transaction_id: transactionId,
      amount,
      currency,
      code: code?.trim() || undefined,
      sandbox: purchaseOptions?.sandbox || undefined,
      sdk_version: EVO_ATTRIBUTION_VERSION,
      occurred_at: new Date().toISOString(),
    });
  } catch (error) {
    warn(`Purchase attribution failed: ${messageFor(error)}`);
  }
}

/** Create a non-persistent storage adapter for tests, examples, and demos. */
export function memoryStorage(initialValues: Record<string, string> = {}): EvoStorage {
  const values = new Map(Object.entries(initialValues));

  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => {
      values.set(key, value);
    },
  };
}

async function persistentInstallId(config: EvoAttributionOptions): Promise<string> {
  const existing = await config.storage.getItem(INSTALL_ID_KEY);
  if (existing) return existing;

  const created = createUuid();
  await config.storage.setItem(INSTALL_ID_KEY, created);
  return created;
}

async function post(
  config: EvoAttributionOptions,
  path: string,
  payload: Record<string, unknown>,
): Promise<Response | null> {
  const response = await fetch(`${config.endpoint}/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    warn(`Attribution request failed with HTTP ${response.status}`);
    return null;
  }
  return response;
}

function createUuid(): string {
  const randomUuid = globalThis.crypto?.randomUUID;
  if (randomUuid) return randomUuid.call(globalThis.crypto);
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (character) => {
    const random = Math.floor(Math.random() * 16);
    const value = character === "x" ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}

function messageFor(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function warn(message: string): void {
  console.warn(`[EVOAttribution] ${message}`);
}
