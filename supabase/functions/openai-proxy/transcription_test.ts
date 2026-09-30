import { createProxyHandler } from "./handler.ts";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

function fixture(xaiKey: string | undefined = "xai-test-key", status = 200) {
  const calls: { path: string; provider: string | undefined; form: FormData }[] = [];
  const tasks: string[] = [];
  const handler = createProxyHandler({
    apiKey: "openai-test-key",
    xaiApiKey: xaiKey,
    promptID: "unused",
    corsHeaders: {},
    authenticate: () => Promise.resolve("user-id"),
    modelConfig: (task) => {
      tasks.push(task);
      return Promise.resolve({ model: task === "transcription_xai" ? "configured-grok" : "configured-gpt", reasoning_effort: null, verbosity: null, fallback_model: null });
    },
    reserveUsage: () => Promise.resolve("reservation"),
    releaseUsage: () => Promise.resolve(),
    claimConversation: () => Promise.resolve(false),
    saveConversation: () => Promise.resolve(),
    upstream: (path, body, _signal, provider) => {
      calls.push({ path, provider, form: body as FormData });
      return Promise.resolve(new Response(JSON.stringify({ text: "Meeting transcript", language: "it", duration: 10 }), { status }));
    },
  });
  const send = (provider?: string, language?: string) => {
    const form = new FormData();
    form.set("file", new File(["audio"], "meeting.m4a", { type: "audio/mp4" }));
    form.set("model", "caller-controlled-model");
    if (language) form.set("language", language);
    return handler(new Request("https://test.invalid/openai-proxy/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: "Bearer token", ...(provider ? { "X-SnipNote-Transcription-Provider": provider } : {}) },
      body: form,
    }));
  };
  return { calls, tasks, send };
}

Deno.test("xAI transcription uses its configured model and sends the file last", async () => {
  const f = fixture();
  const response = await f.send("xai", "it");
  assert(response.status === 200, `Expected 200, got ${response.status}`);
  assert((await response.json()).text === "Meeting transcript", "Transcript response lost");
  assert(f.tasks[0] === "transcription_xai", "Wrong configuration row");
  const call = f.calls[0];
  assert(call.path === "/stt" && call.provider === "xai", "Wrong provider endpoint");
  assert(call.form.get("model") === "configured-grok", "Caller bypassed configured model");
  assert(call.form.get("language") === "it" && call.form.get("format") === "true", "Language formatting missing");
  assert(!call.form.has("response_format"), "OpenAI-only field reached xAI");
  assert([...call.form.keys()].at(-1) === "file", "xAI options must precede file");
});

Deno.test("older transcription clients default to OpenAI", async () => {
  const f = fixture();
  assert((await f.send()).status === 200, "Legacy client rejected");
  assert(f.tasks[0] === "transcription", "Legacy configuration changed");
  assert(f.calls[0].path === "/audio/transcriptions", "Legacy endpoint changed");
  assert(f.calls[0].form.get("model") === "configured-gpt", "Configured OpenAI model lost");
});

Deno.test("unknown transcription providers are rejected before upstream calls", async () => {
  const f = fixture();
  assert((await f.send("unknown")).status === 400, "Invalid provider accepted");
  assert(f.calls.length === 0, "Invalid provider reached upstream");
});

Deno.test("missing xAI credentials fail without falling back to OpenAI", async () => {
  const f = fixture(undefined);
  assert((await f.send("xai")).status === 503, "Missing credential accepted");
  assert(f.calls.length === 0, "Request silently switched providers");
});

Deno.test("xAI failures surface without switching providers", async () => {
  const f = fixture("key", 429);
  assert((await f.send("xai")).status === 429, "Provider error hidden");
  assert(f.calls.length === 1 && f.calls[0].provider === "xai", "Provider switched on failure");
});
