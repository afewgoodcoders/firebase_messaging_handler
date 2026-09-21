import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  encodeEnvelope,
  FcmClient,
  InMemoryIdempotencyStore,
  InMemoryNotificationJobStore,
  InMemoryTokenRegistry,
  NotificationAuthorizationError,
  NotificationRequestAuthorizer,
  NotificationServer,
  type NotificationServerEvent,
  type NotificationEnvelope,
} from "../src/index.ts";

const envelope: NotificationEnvelope = {
  schemaVersion: 2,
  id: "order-42",
  command: "display",
  title: "Order shipped",
  body: "Track your delivery",
  actions: [{ id: "open", title: "Open" }],
  ttlSeconds: 3600,
  sentAt: "2026-09-20T10:00:00.000Z",
};

test("envelope encoding produces string-only FCM data", () => {
  const encoded = encodeEnvelope(envelope);
  assert.ok(Object.values(encoded).every((value) => typeof value === "string"));
  assert.deepEqual(JSON.parse(encoded.actions), [{ id: "open", title: "Open" }]);
});

test("runtime validation rejects invalid enum, TTL, and timestamp values", () => {
  assert.throws(
    () => encodeEnvelope({
      ...envelope,
      remotePresentation: "automatic" as "client",
      ttlSeconds: 2_419_201,
      sentAt: "not-a-date",
    }),
    /remotePresentation must be client or system.*ttlSeconds.*sentAt must be an ISO-8601 date-time/,
  );
  assert.throws(
    () => encodeEnvelope({
      ...envelope,
      sentAt: "2026-09-20T10:00:00.000Z",
      expiresAt: "2026-09-20T10:00:00.000Z",
    }),
    /expiresAt must be later than sentAt/,
  );
});

test("published JSON Schema stays aligned with envelope v2", async () => {
  const schema = JSON.parse(await readFile(
    new URL("../../schema/notification-envelope-v2.schema.json", import.meta.url),
    "utf8",
  )) as Record<string, unknown>;
  const properties = schema.properties as Record<string, unknown>;
  assert.deepEqual(schema.required, ["schemaVersion", "id", "command"]);
  assert.deepEqual(properties.schemaVersion, { const: 2 });
  assert.deepEqual(
    (properties.remotePresentation as { enum: string[] }).enum,
    ["client", "system"],
  );
});

test("FCM client emits explicit client and system presentation payloads", async () => {
  const bodies: Array<Record<string, unknown>> = [];
  const client = new FcmClient({
    projectId: "demo",
    accessToken: async () => "token",
    fetch: async (_input, init) => {
      bodies.push(JSON.parse(init?.body?.toString() ?? "{}") as Record<string, unknown>);
      return Response.json({ name: `projects/demo/messages/${bodies.length}` });
    },
  });

  await client.send({ token: "device" }, envelope);
  await client.send(
    { topic: "orders" },
    { ...envelope, id: "order-43", remotePresentation: "system" },
  );

  const clientMessage = bodies[0].message as Record<string, unknown>;
  const clientApns = clientMessage.apns as Record<string, unknown>;
  const clientHeaders = clientApns.headers as Record<string, unknown>;
  const clientPayload = clientApns.payload as Record<string, unknown>;
  assert.equal(clientMessage.notification, undefined);
  assert.equal(clientHeaders["apns-push-type"], "background");
  assert.equal((clientPayload.aps as Record<string, unknown>)["content-available"], 1);

  const systemMessage = bodies[1].message as Record<string, unknown>;
  const systemHeaders = (systemMessage.apns as Record<string, unknown>)
    .headers as Record<string, unknown>;
  assert.deepEqual(systemMessage.notification, {
    title: envelope.title,
    body: envelope.body,
  });
  assert.equal(systemHeaders["apns-push-type"], "alert");
  assert.equal(systemHeaders["apns-priority"], "10");
});

test("FCM client rejects empty or ambiguous targets before sending", async () => {
  const client = new FcmClient({
    projectId: "demo",
    accessToken: async () => "token",
    fetch: async () => {
      throw new Error("fetch must not run");
    },
  });

  await assert.rejects(client.send({}, envelope), /exactly one/);
  await assert.rejects(
    client.send({ token: "device", topic: "news" }, envelope),
    /exactly one/,
  );
});

test("FCM client honors Retry-After and retries transient failures", async () => {
  let calls = 0;
  const sleeps: number[] = [];
  const client = new FcmClient({
    projectId: "demo",
    accessToken: async () => "token",
    fetch: async () => {
      calls += 1;
      return calls === 1
        ? new Response(JSON.stringify({ error: { message: "busy" } }), {
            status: 429,
            headers: { "retry-after": "2", "content-type": "application/json" },
          })
        : Response.json({ name: "projects/demo/messages/1" });
    },
    sleep: async (milliseconds) => { sleeps.push(milliseconds); },
  });

  const receipt = await client.send({ token: "device" }, envelope);
  assert.equal(receipt.accepted, true);
  assert.equal(receipt.attempts, 2);
  assert.deepEqual(sleeps, [2000]);
});

test("server prunes an unregistered token and suppresses duplicate sends", async () => {
  const registry = new InMemoryTokenRegistry();
  await registry.upsert({
    installationId: "installation-1",
    token: "stale",
    userId: "user-1",
    platform: "android",
    updatedAt: new Date().toISOString(),
  });
  const client = new FcmClient({
    projectId: "demo",
    accessToken: async () => "token",
    maxAttempts: 1,
    fetch: async () => new Response(JSON.stringify({
      error: {
        message: "Requested entity was not found.",
        details: [{ errorCode: "UNREGISTERED" }],
      },
    }), { status: 404, headers: { "content-type": "application/json" } }),
  });
  const server = new NotificationServer({
    client,
    registry,
    idempotency: new InMemoryIdempotencyStore(),
  });

  const first = await server.sendToUser("user-1", envelope);
  const second = await server.sendToUser("user-1", envelope);
  assert.equal(first[0].staleToken, true);
  assert.deepEqual(second, []);
  assert.deepEqual(await registry.listByUser("user-1"), []);
});

test("scheduled jobs can be cancelled and due failures enter the DLQ", async () => {
  let now = new Date("2026-09-20T10:00:00.000Z");
  const jobs = new InMemoryNotificationJobStore();
  const client = new FcmClient({
    projectId: "demo",
    accessToken: async () => "token",
    maxAttempts: 1,
    fetch: async () => new Response(JSON.stringify({ error: { message: "bad" } }), {
      status: 400,
      headers: { "content-type": "application/json" },
    }),
  });
  const server = new NotificationServer({
    client,
    registry: new InMemoryTokenRegistry(),
    jobs,
    maxJobAttempts: 1,
    now: () => now,
  });

  await server.schedule("cancel-me", new Date(now.getTime() + 1000), { topic: "news" }, envelope);
  assert.equal(await server.cancelScheduled("cancel-me"), true);
  await server.schedule("fail-me", new Date(now.getTime() + 1000), { topic: "news" }, {
    ...envelope,
    id: "scheduled-order-42",
  });
  now = new Date(now.getTime() + 2000);
  assert.equal(await server.drainDueJobs(), 1);
  assert.equal(jobs.deadLetters.length, 1);
  assert.equal(jobs.deadLetters[0].id, "fail-me");
});

test("request authorization enforces bearer, App Check, and roles", async () => {
  const authorizer = new NotificationRequestAuthorizer({
    verifyAccessToken: async (token) => {
      assert.equal(token, "valid-user");
      return { subject: "user-1", roles: ["notifications.send"] };
    },
    verifyAppCheckToken: async (token) => assert.equal(token, "valid-app"),
    requiredRoles: ["notifications.send"],
  });

  await assert.rejects(
    authorizer.authorize({}),
    (error: unknown) => error instanceof NotificationAuthorizationError && error.code === "missing_access_token",
  );
  const principal = await authorizer.authorize({
    authorization: "Bearer valid-user",
    appCheckToken: "valid-app",
  });
  assert.equal(principal.subject, "user-1");
});

test("server emits correlation-safe audit events", async () => {
  const events: NotificationServerEvent[] = [];
  const server = new NotificationServer({
    client: new FcmClient({
      projectId: "demo",
      accessToken: async () => "token",
      fetch: async () => Response.json({ name: "projects/demo/messages/1" }),
    }),
    registry: new InMemoryTokenRegistry(),
    events: { emit: async (event) => { events.push(event); } },
    now: () => new Date("2026-09-20T10:00:00.000Z"),
  });

  await server.sendToTopic("news", envelope, { correlationId: "corr-1" });
  assert.deepEqual(events.map(({ type }) => type), [
    "notification.send.started",
    "notification.send.completed",
  ]);
  assert.equal(events[0].type === "notification.send.started" && events[0].correlationId, "corr-1");
});
