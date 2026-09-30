import { createProxyHandler } from "./handler.ts";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

function fixture(
  options: { allowed?: boolean; owned?: boolean; saveFails?: boolean } = {},
) {
  const calls: { path: string; body: unknown }[] = [];
  let released = 0;
  const handler = createProxyHandler({
    apiKey: "test-key",
    promptID: "pmpt_server",
    corsHeaders: {},
    authenticate: (token: string) =>
      Promise.resolve(token === "user-token" ? "user-b" : null),
    modelConfig: () => Promise.resolve(undefined),
    reserveUsage: () =>
      Promise.resolve(options.allowed === false ? null : "reservation-id"),
    releaseUsage: () => {
      released++;
      return Promise.resolve();
    },
    claimConversation: (_user: string, id: string) =>
      Promise.resolve(options.owned === true && id === "conv_owned"),
    saveConversation: () =>
      options.saveFails
        ? Promise.reject(new Error("DB unavailable"))
        : Promise.resolve(),
    upstream: (path: string, body: BodyInit) => {
      calls.push({
        path,
        body: body instanceof FormData ? body : JSON.parse(body as string),
      });
      return Promise.resolve(
        new Response(
          JSON.stringify(
            path === "/conversations"
              ? { id: "conv_new" }
              : { id: "resp_new", output: [] },
          ),
          { status: 200 },
        ),
      );
    },
  });
  const send = (
    body: unknown,
    task = "summary",
    path = "/responses",
    token = "user-token",
  ) =>
    handler(
      new Request(
        `https://test.invalid/functions/v1/openai-proxy${path}`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
            "X-SnipNote-Task": task,
          },
          body: JSON.stringify(body),
        },
      ),
    );
  return { calls, handler, send, releases: () => released };
}

Deno.test("multipart transcription uses the configured model and preserves audio and language", async () => {
  const f = fixture();
  const form = new FormData();
  form.set(
    "file",
    new File(["audio fixture"], "meeting.m4a", { type: "audio/mp4" }),
  );
  form.set("model", "caller-model");
  form.set("language", "it");
  const result = await f.handler(
    new Request("https://test.invalid/openai-proxy/audio/transcriptions", {
      method: "POST",
      headers: {
        Authorization: "Bearer user-token",
        "X-SnipNote-Task": "transcription",
      },
      body: form,
    }),
  );
  assert(result.status === 200, `Expected 200, got ${result.status}`);
  const sent = f.calls[0].body as FormData;
  assert(
    sent.get("model") === "gpt-transcribe",
    "Caller selected transcription model",
  );
  assert(sent.get("language") === "it", "Language lost");
  assert(sent.get("response_format") === "json", "Unexpected response format");
  assert(
    await (sent.get("file") as File).text() === "audio fixture",
    "Audio changed",
  );
  assert(f.releases() === 1, "Audio reservation leaked");
});

Deno.test("rejects another user or legacy conversation before calling OpenAI", async () => {
  const f = fixture();
  const result = await f.send({
    input: [{ role: "user", content: "Recall history" }],
    conversation: "conv_other",
  }, "eve_chat");
  assert(result.status === 403, `Expected 403, got ${result.status}`);
  assert(
    (await result.json()).error.code === "conversation_not_owned",
    "Missing recoverable ownership error",
  );
  assert(f.calls.length === 0, "Private context reached OpenAI");
});

Deno.test("rejects project resource references and paid tools including nested file input", async () => {
  for (
    const body of [
      { input: "hello", previous_response_id: "resp_other" },
      {
        input: "hello",
        tools: [{ type: "file_search", vector_store_ids: ["vs_other"] }],
      },
      {
        input: [{
          role: "user",
          content: [{ type: "input_file", file_id: "file_other" }],
        }],
      },
      { input: [{ type: "item_reference", id: "item_other" }] },
    ]
  ) {
    const f = fixture();
    assert(
      (await f.send(body)).status === 400,
      "Unsupported resource body accepted",
    );
    assert(f.calls.length === 0, "Resource reached OpenAI");
  }
});

Deno.test("quota exhaustion and authentication failures never reach OpenAI", async () => {
  const f = fixture({ allowed: false });
  assert(
    (await f.send({ input: "hello" })).status === 429,
    "Quota not enforced",
  );
  assert(
    (await f.send({ input: "hello" }, "summary", "/responses", "invalid"))
      .status === 401,
    "Invalid token accepted",
  );
  assert(f.calls.length === 0, "Denied request billed");
});

Deno.test("bounds output and overrides models and template tools server-side", async () => {
  const f = fixture({ owned: true });
  const result = await f.send({
    model: "expensive-model",
    input: [{ role: "user", content: [{ type: "input_text", text: "hello" }] }],
    conversation: "conv_owned",
    prompt: {
      id: "pmpt_attacker",
      variables: { meeting_transcription: "notes" },
    },
    max_output_tokens: 100000,
  }, "eve_chat");
  assert(result.status === 200, "Valid Eve request rejected");
  const body = f.calls[0].body as Record<string, unknown>;
  assert(body.model === "gpt-6-luna", "Caller controlled model");
  assert(body.max_output_tokens === 4096, "Output unbounded");
  assert(
    (body.prompt as { id: string }).id === "pmpt_server",
    "Caller controlled template",
  );
  assert(
    Array.isArray(body.tools) && body.tools.length === 0,
    "Template tools not disabled",
  );
  assert(f.releases() === 1, "Reservation not released");
});

Deno.test("rejects oversized streamed JSON without relying on content-length", async () => {
  const f = fixture();
  const result = await f.send({ input: "a".repeat(524289) });
  assert(result.status === 413, `Expected 413, got ${result.status}`);
  assert(f.calls.length === 0, "Oversized input billed");
});

Deno.test("does not expose a conversation if its ownership cannot be saved", async () => {
  const f = fixture({ saveFails: true });
  const result = await f.send(
    { metadata: { user_id: "attacker" } },
    "",
    "/conversations",
  );
  assert(result.status === 503, "Untracked conversation exposed");
  assert(f.releases() === 1, "Reservation leaked on failure");
});

Deno.test("rejects endpoint/task mismatch and malformed bodies", async () => {
  const f = fixture();
  for (const body of [null, [], { input: 1 }]) {
    assert((await f.send(body)).status === 400, "Malformed JSON accepted");
  }
  assert(
    (await f.send({ input: "hello" }, "transcription")).status === 400,
    "Task mismatch accepted",
  );
});
