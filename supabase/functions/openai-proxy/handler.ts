export interface ModelConfig {
  model: string;
  reasoning_effort: string | null;
  verbosity: string | null;
  fallback_model: string | null;
}

interface Dependencies {
  apiKey: string | undefined;
  xaiApiKey?: string;
  promptID: string;
  corsHeaders: Record<string, string>;
  authenticate(token: string): Promise<string | null>;
  modelConfig(task: string): Promise<ModelConfig | undefined>;
  reserveUsage(
    userID: string,
    textBytes: number,
    audioBytes: number,
  ): Promise<string | null>;
  releaseUsage(id: string): Promise<void>;
  claimConversation(userID: string, id: string): Promise<boolean>;
  saveConversation(userID: string, id: string): Promise<void>;
  upstream(
    path: string,
    body: BodyInit,
    signal: AbortSignal,
    provider?: "openai" | "xai",
  ): Promise<Response>;
}

const TEXT_LIMIT = 512 * 1024;
const AUDIO_LIMIT = 12 * 1024 * 1024;
const RESPONSE_TASKS = new Set([
  "overview",
  "summary",
  "actions",
  "title",
  "text_summary",
  "eve_chat",
  "actions_report",
]);
const DEFAULT_TEXT: ModelConfig = {
  model: "gpt-6-luna",
  reasoning_effort: "low",
  verbosity: null,
  fallback_model: null,
};
const DEFAULT_AUDIO: ModelConfig = {
  model: "gpt-transcribe",
  reasoning_effort: null,
  verbosity: null,
  fallback_model: "gpt-4o-transcribe",
};

const DEFAULT_XAI: ModelConfig = {
  model: "grok-voice-transcribe-2.0",
  reasoning_effort: null,
  verbosity: null,
  fallback_model: null,
};

class RequestError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code?: string,
  ) {
    super(message);
  }
}

function object(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function fields(value: Record<string, unknown>, allowed: string[]) {
  if (Object.keys(value).some((key) => !allowed.includes(key))) {
    throw new RequestError(400, "Unsupported request field");
  }
}

// Read streams incrementally; Content-Length can be absent or misleading.
async function limitedBytes(
  body: ReadableStream<Uint8Array> | null,
  limit: number,
): Promise<Uint8Array<ArrayBuffer>> {
  if (!body) throw new RequestError(400, "Missing request body");
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        await reader.cancel();
        throw new RequestError(413, "Request is too large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function textInput(input: unknown): unknown {
  if (typeof input === "string" && input.length > 0) return input;
  if (!Array.isArray(input) || input.length === 0 || input.length > 32) {
    throw new RequestError(400, "Invalid text input");
  }
  return input.map((message) => {
    if (!object(message)) throw new RequestError(400, "Invalid message");
    fields(message, ["role", "content"]);
    if (
      !["system", "developer", "user", "assistant"].includes(
        String(message.role),
      )
    ) throw new RequestError(400, "Invalid message role");
    if (typeof message.content === "string") {
      return { role: message.role, content: message.content };
    }
    if (!Array.isArray(message.content) || message.content.length === 0) {
      throw new RequestError(400, "Invalid message content");
    }
    return {
      role: message.role,
      content: message.content.map((content) => {
        if (!object(content)) throw new RequestError(400, "Invalid content");
        fields(content, ["type", "text"]);
        if (
          content.type !== "input_text" || typeof content.text !== "string"
        ) throw new RequestError(400, "Only text input is supported");
        return { type: "input_text", text: content.text };
      }),
    };
  });
}

function responseBody(
  raw: unknown,
  task: string,
  promptID: string,
): Record<string, unknown> {
  if (!object(raw)) throw new RequestError(400, "Expected a JSON object");
  fields(raw, [
    "model",
    "input",
    "max_output_tokens",
    "reasoning",
    "text",
    "prompt",
    "conversation",
  ]);
  const body: Record<string, unknown> = {
    input: textInput(raw.input),
    max_output_tokens: 4096,
    tools: [],
  };
  if (raw.max_output_tokens !== undefined) {
    if (
      !Number.isInteger(raw.max_output_tokens) ||
      Number(raw.max_output_tokens) <= 0
    ) throw new RequestError(400, "Invalid output limit");
    body.max_output_tokens = Math.min(Number(raw.max_output_tokens), 4096);
  }
  if (
    object(raw.text) &&
    ["low", "medium", "high"].includes(String(raw.text.verbosity))
  ) body.text = { verbosity: raw.text.verbosity };
  if (task === "eve_chat") {
    if (
      typeof raw.conversation !== "string" ||
      !/^conv_[a-zA-Z0-9_-]+$/.test(raw.conversation)
    ) throw new RequestError(400, "Invalid conversation");
    body.conversation = raw.conversation;
    const variables = object(raw.prompt) && object(raw.prompt.variables)
      ? raw.prompt.variables
      : {};
    fields(variables, [
      "meeting_overview",
      "meeting_summary",
      "meeting_transcription",
    ]);
    if (Object.values(variables).some((value) => typeof value !== "string")) {
      throw new RequestError(400, "Invalid prompt variables");
    }
    // The template and tools are chosen by the server, never by the caller.
    body.prompt = { id: promptID, variables };
    body.text = { ...(body.text as object ?? {}), format: { type: "text" } };
  } else {
    if (raw.conversation !== undefined || raw.prompt !== undefined) {
      throw new RequestError(400, "Conversation and prompt require Eve");
    }
    body.store = false;
  }
  return body;
}

export function createProxyHandler(
  deps: Dependencies,
): (request: Request) => Promise<Response> {
  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: {
        ...deps.corsHeaders,
        "Content-Type": "application/json",
        ...(status === 429 ? { "Retry-After": "60" } : {}),
      },
    });
  return async (req) => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: deps.corsHeaders });
    }
    let reservation: string | null = null;
    try {
      const token = req.headers.get("Authorization")?.match(/^Bearer (\S+)$/i)
        ?.[1];
      if (!token) throw new RequestError(401, "Sign in to use AI");
      const userID = await deps.authenticate(token);
      if (!userID) throw new RequestError(401, "Invalid token");
      const path = new URL(req.url).pathname.replace(/^.*?\/openai-proxy/, "");
      if (
        req.method !== "POST" ||
        !["/responses", "/conversations", "/audio/transcriptions"].includes(
          path,
        )
      ) throw new RequestError(403, "Endpoint not allowed");
      const audio = path === "/audio/transcriptions";
      const providerHeader = req.headers.get(
        "X-SnipNote-Transcription-Provider",
      );
      if (
        providerHeader !== null &&
        (!audio || !["openai", "xai"].includes(providerHeader))
      ) {
        throw new RequestError(400, "Invalid transcription provider");
      }
      const provider: "openai" | "xai" = providerHeader === "xai"
        ? "xai"
        : "openai";
      if (provider === "xai" ? !deps.xaiApiKey : !deps.apiKey) {
        throw new RequestError(
          503,
          provider === "xai"
            ? "xAI transcription is not configured"
            : "AI service is not configured",
        );
      }
      const task = req.headers.get("X-SnipNote-Task") ||
        (audio ? "transcription" : "text_summary");
      if (
        path !== "/conversations" &&
        (audio ? task !== "transcription" : !RESPONSE_TASKS.has(task))
      ) throw new RequestError(400, "Task does not match endpoint");
      const bytes = await limitedBytes(
        req.body,
        audio ? AUDIO_LIMIT + 65536 : TEXT_LIMIT,
      );
      let body: Record<string, unknown> | FormData;
      let audioBytes = 0;
      if (audio) {
        const form = await new Response(bytes, {
          headers: { "Content-Type": req.headers.get("Content-Type") ?? "" },
        }).formData();
        const file = form.get("file");
        if (
          !(file instanceof File) || file.size === 0 || file.size > AUDIO_LIMIT
        ) throw new RequestError(400, "Invalid audio upload");
        const keys = [...form.keys()];
        if (
          keys.length !== new Set(keys).size ||
          keys.some((key) =>
            !["file", "model", "language", "response_format"].includes(key)
          )
        ) throw new RequestError(400, "Unsupported audio field");
        body = new FormData();
        body.set("file", file, file.name);
        body.set("response_format", "json");
        const language = form.get("language");
        if (language !== null) {
          if (
            typeof language !== "string" ||
            !/^[a-z]{2,3}(-[A-Za-z]{2,4})?$/.test(language)
          ) throw new RequestError(400, "Invalid language");
          body.set("language", language);
        }
        audioBytes = file.size;
      } else {
        let raw: unknown;
        try {
          raw = JSON.parse(new TextDecoder().decode(bytes));
        } catch {
          throw new RequestError(400, "Invalid JSON");
        }
        if (path === "/conversations") {
          if (!object(raw)) {
            throw new RequestError(400, "Expected a JSON object");
          }
          fields(raw, ["metadata"]);
          body = { metadata: { source: "SnipNote", user_id: userID } };
        } else body = responseBody(raw, task, deps.promptID);
      }
      reservation = await deps.reserveUsage(
        userID,
        audio ? 0 : bytes.byteLength,
        audioBytes,
      );
      if (!reservation) {
        throw new RequestError(429, "AI usage limit reached. Try again later.");
      }
      if (!(body instanceof FormData) && body.conversation) {
        if (!await deps.claimConversation(userID, String(body.conversation))) {
          throw new RequestError(
            403,
            "Start a new Eve conversation",
            "conversation_not_owned",
          );
        }
      }
      const config = path === "/conversations"
        ? undefined
        : (await deps.modelConfig(
          audio && provider === "xai" ? "transcription_xai" : task,
        ) ??
          (audio
            ? (provider === "xai" ? DEFAULT_XAI : DEFAULT_AUDIO)
            : DEFAULT_TEXT));
      const encoded = (model: string): BodyInit => {
        if (body instanceof FormData) {
          // Rebuild on every attempt: options must precede the file for xAI.
          const form = new FormData();
          form.set("model", model);
          const language = body.get("language");
          if (typeof language === "string") {
            form.set("language", language);
            if (provider === "xai") form.set("format", "true");
          }
          if (provider === "openai") form.set("response_format", "json");
          const file = body.get("file") as File;
          form.set("file", file, file.name);
          return form;
        }
        const configured: Record<string, unknown> = {
          ...body,
          model,
          ...(config?.reasoning_effort
            ? { reasoning: { effort: config.reasoning_effort } }
            : {}),
        };
        if (config?.verbosity) {
          configured.text = {
            ...(object(body.text) ? body.text : {}),
            verbosity: config.verbosity,
          };
        }
        return JSON.stringify(configured);
      };
      const signal = AbortSignal.timeout(120000);
      const upstreamPath = audio && provider === "xai" ? "/stt" : path;
      let upstream = await deps.upstream(
        upstreamPath,
        config ? encoded(config.model) : JSON.stringify(body),
        signal,
        provider,
      );
      if (
        config?.fallback_model && config.fallback_model !== config.model &&
        [400, 404].includes(upstream.status)
      ) {
        await upstream.body?.cancel();
        upstream = await deps.upstream(
          upstreamPath,
          encoded(config.fallback_model),
          signal,
          provider,
        );
      }
      console.log(
        `${path} task=${task} user=${userID} status=${upstream.status}`,
      );
      if (!upstream.ok) {
        await upstream.body?.cancel();
        // Upstream errors can contain credential fragments or submitted content.
        return json({
          error: { message: `AI service returned HTTP ${upstream.status}` },
        }, upstream.status);
      }
      const output = await limitedBytes(upstream.body, 2 * 1024 * 1024);
      if (audio && provider === "xai") {
        let result: unknown;
        try {
          result = JSON.parse(new TextDecoder().decode(output));
        } catch {
          throw new RequestError(502, "Invalid transcription response");
        }
        if (
          !object(result) || typeof result.text !== "string" ||
          !result.text.trim()
        ) {
          throw new RequestError(502, "Invalid transcription response");
        }
        return json({ text: result.text }, 200);
      }
      if (path === "/conversations") {
        const conversation = JSON.parse(new TextDecoder().decode(output));
        if (
          typeof conversation.id !== "string" ||
          !/^conv_[a-zA-Z0-9_-]+$/.test(conversation.id)
        ) throw new Error("Invalid upstream conversation");
        await deps.saveConversation(userID, conversation.id);
      }
      return new Response(output, {
        status: upstream.status,
        headers: { ...deps.corsHeaders, "Content-Type": "application/json" },
      });
    } catch (error) {
      if (error instanceof RequestError) {
        return json(
          { error: { message: error.message, code: error.code } },
          error.status,
        );
      }
      console.error("Proxy dependency or upstream failure");
      return json({
        error: { message: "AI service is temporarily unavailable" },
      }, 503);
    } finally {
      if (reservation) {
        try {
          await deps.releaseUsage(reservation);
        } catch {
          console.error("Quota reservation will expire automatically");
        }
      }
    }
  };
}
