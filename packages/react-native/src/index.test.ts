import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import {
  EVO_ATTRIBUTION_VERSION,
  configureEvoAttribution,
  getEvoInstallId,
  memoryStorage,
  trackInstall,
  trackPurchase,
  type InstallResult,
} from "./index.js";

const originalFetch = globalThis.fetch;
const originalWarn = console.warn;

afterEach(() => {
  globalThis.fetch = originalFetch;
  console.warn = originalWarn;
});

test("memoryStorage stores values and returns null for missing keys", async () => {
  const storage = memoryStorage({ existing: "value" });

  assert.equal(await storage.getItem("existing"), "value");
  assert.equal(await storage.getItem("missing"), null);
  await storage.setItem("new", "stored");
  assert.equal(await storage.getItem("new"), "stored");
});

test("trackInstall persists one id and sends the documented payload once", async () => {
  const storage = memoryStorage();
  const requests: Array<{ url: string; body: Record<string, unknown> }> = [];
  const resultBody: InstallResult = {
    ok: true,
    duplicate: false,
    install: {
      install_id: "returned-install-id",
      platform: "ios",
      attributed: true,
      resolution_method: "clipboard",
      confidence: 0.95,
      link: { id: 12, domain: "getdupe.app", slug: "" },
      code: null,
      creator: { id: "creator-id", name: "Jane Doe" },
    },
  };

  globalThis.fetch = (async (input, init) => {
    requests.push({
      url: String(input),
      body: JSON.parse(String(init?.body)) as Record<string, unknown>,
    });
    return Response.json(resultBody, { status: 201 });
  }) as typeof fetch;

  configureEvoAttribution({
    pixelKey: "pk_test",
    platform: "ios",
    storage,
    endpoint: "https://example.test/",
    appVersion: "1.4.0",
    getClipboard: async () => "  evc_click-token  ",
  });

  const result = await trackInstall(true, "  jane-10  ");
  const installId = await getEvoInstallId();

  assert.deepEqual(result, resultBody);
  assert.equal(requests.length, 1);
  assert.equal(requests[0]?.url, "https://example.test/api/public/attribution/installs");
  assert.equal(requests[0]?.body.pixel_key, "pk_test");
  assert.equal(requests[0]?.body.install_id, installId);
  assert.equal(requests[0]?.body.platform, "ios");
  assert.equal(requests[0]?.body.clipboard_token, "evc_click-token");
  assert.equal(requests[0]?.body.code, "jane-10");
  assert.equal(requests[0]?.body.app_version, "1.4.0");
  assert.equal(requests[0]?.body.sdk_version, EVO_ATTRIBUTION_VERSION);
  assert.match(String(requests[0]?.body.occurred_at), /^\d{4}-\d{2}-\d{2}T/);

  assert.equal(await trackInstall(true), null);
  assert.equal(requests.length, 1);
});

test("failed installs stay pending and never reject into host code", async () => {
  const storage = memoryStorage();
  const warnings: string[] = [];
  let attempts = 0;
  console.warn = (message?: unknown) => warnings.push(String(message));
  globalThis.fetch = (async () => {
    attempts += 1;
    if (attempts === 1) throw new Error("offline");
    return Response.json({ ok: true }, { status: 201 });
  }) as typeof fetch;

  configureEvoAttribution({ pixelKey: "pk_test", platform: "android", storage });

  assert.equal(await trackInstall(), null);
  assert.equal(await storage.getItem("evo_install_reported"), null);
  assert.equal(warnings.length, 1);

  assert.deepEqual(await trackInstall(), { ok: true });
  assert.equal(await storage.getItem("evo_install_reported"), "true");
  assert.equal(attempts, 2);
});

test("clipboard values without the evc_ prefix are omitted", async () => {
  let body: Record<string, unknown> | undefined;
  globalThis.fetch = (async (_input, init) => {
    body = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return Response.json({ ok: true }, { status: 201 });
  }) as typeof fetch;

  configureEvoAttribution({
    pixelKey: "pk_test",
    platform: "android",
    storage: memoryStorage(),
    getClipboard: async () => "not-an-evo-token",
  });

  await trackInstall(true);
  assert.equal(body?.clipboard_token, undefined);
});

test("trackPurchase reuses the install id, sends sdk_version, and swallows failures", async () => {
  const requests: Array<{ url: string; body: Record<string, unknown> }> = [];
  globalThis.fetch = (async (input, init) => {
    requests.push({
      url: String(input),
      body: JSON.parse(String(init?.body)) as Record<string, unknown>,
    });
    return new Response(null, { status: 204 });
  }) as typeof fetch;

  configureEvoAttribution({
    pixelKey: "pk_test",
    platform: "ios",
    storage: memoryStorage({ evo_install_id: "stable-install-id" }),
    endpoint: "https://example.test",
  });

  await trackPurchase("transaction-1", 49.99, "USD", " JANE10 ");

  assert.equal(requests[0]?.url, "https://example.test/api/public/attribution/events");
  assert.deepEqual(
    { ...requests[0]?.body, occurred_at: "<timestamp>" },
    {
      pixel_key: "pk_test",
      event_type: "purchase",
      source: "sdk",
      external_user_id: "stable-install-id",
      transaction_id: "transaction-1",
      amount: 49.99,
      currency: "USD",
      code: "JANE10",
      sdk_version: EVO_ATTRIBUTION_VERSION,
      occurred_at: "<timestamp>",
    },
  );

  console.warn = () => undefined;
  globalThis.fetch = (async () => {
    throw new Error("offline");
  }) as typeof fetch;
  await assert.doesNotReject(trackPurchase("transaction-2", 10));
});

test("trackPurchase marks sandbox events only when requested", async () => {
  const bodies: Array<Record<string, unknown>> = [];
  globalThis.fetch = (async (_input, init) => {
    bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
    return new Response(null, { status: 204 });
  }) as typeof fetch;

  configureEvoAttribution({
    pixelKey: "pk_test",
    platform: "ios",
    storage: memoryStorage({ evo_install_id: "stable-install-id" }),
  });

  await trackPurchase("production-transaction", 20);
  await trackPurchase("sandbox-transaction", 20, "USD", undefined, { sandbox: true });

  assert.equal(bodies[0]?.sandbox, undefined);
  assert.equal(bodies[1]?.sandbox, true);
});
