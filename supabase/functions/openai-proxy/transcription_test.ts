import { createProxyHandler } from "./handler.ts";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

function fixture(
  xaiKey: string | null = "xai-test-key",
  status = 200,
  options: {
    authenticated?: boolean;
    quota?: boolean;
    output?: string;
    fallback?: string;
    statuses?: number[];
  } = {},
) {
  const calls: {
    path: string;
    provider: string | undefined;
    form: FormData;
  }[] = [];
  const tasks: string[] = [];
  const releases: string[] = [];
  const handler = createProxyHandler({
    apiKey: "openai-test-key",
    xaiApiKey: xaiKey ?? undefined,
    promptID: "unused",
    corsHeaders: {},
    authenticate: () =>
      Promise.resolve(options.authenticated === false ? null : "user-id"),
    modelConfig: (task) => {
      tasks.push(task);
      return Promise.resolve({
        model: task === "transcription_xai"
          ? "configured-grok"
          : "configured-gpt",
        reasoning_effort: null,
        verbosity: null,
        fallback_model: options.fallback ?? null,
      });
    },
    reserveUsage: () =>
      Promise.resolve(options.quota === false ? null : "reservation"),
    releaseUsage: (id) => {
      releases.push(id);
      return Promise.resolve();
    },
    claimConversation: () => Promise.resolve(false),
    saveConversation: () => Promise.resolve(),
    upstream: (path, body, _signal, provider) => {
      calls.push({ path, provider, form: body as FormData });
      return Promise.resolve(
        new Response(
          options.output ??
            JSON.stringify({
              text: "Meeting transcript",
              language: "it",
              duration: 10,
            }),
          { status: options.statuses?.[calls.length - 1] ?? status },
        ),
      );
    },
  });
  const send = (provider?: string, language?: string) => {
    const form = new FormData();
    form.set("file", new File(["audio"], "meeting.m4a", { type: "audio/mp4" }));
    form.set("model", "caller-controlled-model");
    if (language) form.set("language", language);
    return handler(
      new Request("https://test.invalid/openai-proxy/audio/transcriptions", {
        method: "POST",
        headers: {
          Authorization: "Bearer token",
          ...(provider
            ? { "X-SnipNote-Transcription-Provider": provider }
            : {}),
        },
        body: form,
      }),
    );
  };
  return { calls, tasks, send, handler, releases };
}

Deno.test("xAI transcription uses its configured model and sends the file last", async () => {
  const f = fixture();
  const response = await f.send("xai", "it");
  assert(response.status === 200, `Expected 200, got ${response.status}`);
  assert(
    (await response.json()).text === "Meeting transcript",
    "Transcript response lost",
  );
  assert(f.tasks[0] === "transcription_xai", "Wrong configuration row");
  const call = f.calls[0];
  assert(
    call.path === "/stt" && call.provider === "xai",
    "Wrong provider endpoint",
  );
  assert(
    call.form.get("model") === "configured-grok",
    "Caller bypassed configured model",
  );
  assert(
    call.form.get("language") === "it" && call.form.get("format") === "true",
    "Language formatting missing",
  );
  assert(!call.form.has("response_format"), "OpenAI-only field reached xAI");
  assert(
    [...call.form.keys()].at(-1) === "file",
    "xAI options must precede file",
  );
});

Deno.test("older transcription clients default to OpenAI", async () => {
  const f = fixture();
  assert((await f.send()).status === 200, "Legacy client rejected");
  assert(f.tasks[0] === "transcription", "Legacy configuration changed");
  assert(
    f.calls[0].path === "/audio/transcriptions",
    "Legacy endpoint changed",
  );
  assert(
    f.calls[0].form.get("model") === "configured-gpt",
    "Configured OpenAI model lost",
  );
});

Deno.test("unknown transcription providers are rejected before upstream calls", async () => {
  const f = fixture();
  assert((await f.send("unknown")).status === 400, "Invalid provider accepted");
  assert(f.calls.length === 0, "Invalid provider reached upstream");
});

Deno.test("missing xAI credentials fail without falling back to OpenAI", async () => {
  const f = fixture(null);
  assert((await f.send("xai")).status === 503, "Missing credential accepted");
  assert(f.calls.length === 0, "Request silently switched providers");
});

Deno.test("xAI failures surface without switching providers", async () => {
  const f = fixture("key", 429);
  assert((await f.send("xai")).status === 429, "Provider error hidden");
  assert(
    f.calls.length === 1 && f.calls[0].provider === "xai",
    "Provider switched on failure",
  );
});
Deno.test("test_xai_preserves_auth_and_quota", async () => {
  for (
    const [options, status] of [[{ authenticated: false }, 401], [{
      quota: false,
    }, 429]] as const
  ) {
    const f = fixture("key", 200, options);
    assert((await f.send("xai")).status === status, "Auth/quota bypassed");
    assert(f.calls.length === 0, "Denied request reached upstream");
  }
  const f = fixture("key", 429);
  await f.send("xai");
  assert(f.releases.length === 1, "Reservation leaked on error");
});
Deno.test("test_xai_header_rejected_on_text_endpoint", async () => {
  const f = fixture();
  const response = await f.handler(
    new Request("https://test.invalid/openai-proxy/responses", {
      method: "POST",
      headers: {
        Authorization: "Bearer token",
        "X-SnipNote-Transcription-Provider": "xai",
      },
      body: JSON.stringify({ input: "summary" }),
    }),
  );
  assert(
    response.status === 400 && f.calls.length === 0,
    "Transcription header affected text routing",
  );
});
Deno.test("test_xai_auto_language_omits_format", async () => {
  const f = fixture();
  await f.send("xai");
  assert(
    !f.calls[0].form.has("language") && !f.calls[0].form.has("format"),
    "Auto language forced formatting",
  );
});
Deno.test("test_xai_rejects_malformed_or_blank_text", async () => {
  for (
    const output of [
      "not-json xai-test-key",
      "{}",
      '{"text":"  "}',
      '{"text":3}',
    ]
  ) {
    const f = fixture("xai-test-key", 200, { output });
    const response = await f.send("xai");
    assert(response.status === 502, "Invalid transcript accepted");
    assert(
      !(await response.text()).includes("xai-test-key"),
      "Upstream content leaked",
    );
    assert(f.releases.length === 1, "Reservation leaked on malformed response");
  }
});
Deno.test("test_xai_fallback_resends_audio", async () => {
  const f = fixture("key", 200, {
    fallback: "fallback-grok",
    statuses: [400, 200],
  });
  assert((await f.send("xai")).status === 200, "Fallback failed");
  assert(
    f.calls.length === 2 && f.calls.every((c) => c.provider === "xai"),
    "Provider changed",
  );
  assert(f.calls[0].form !== f.calls[1].form, "Multipart body reused");
  assert(
    f.calls[0].form.get("model") === "configured-grok" &&
      f.calls[1].form.get("model") === "fallback-grok",
    "Fallback model lost",
  );
  for (const call of f.calls) {
    assert(
      await (call.form.get("file") as File).text() === "audio",
      "Audio exhausted",
    );
  }
});
Deno.test("xAI status errors are sanitized", async () => {
  const f = fixture("xai-test-key", 403, {
    output: "xai-test-key private-content",
  });
  const response = await f.send("xai");
  const text = await response.text();
  assert(response.status === 403, "Status lost");
  assert(
    !text.includes("xai-test-key") && !text.includes("private-content"),
    "Provider content leaked",
  );
});
