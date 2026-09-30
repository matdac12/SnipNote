import { createClient } from "@supabase/supabase-js";
import { corsHeaders } from "../_shared/cors.ts";
import { createProxyHandler, type ModelConfig } from "./handler.ts";

const client = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { autoRefreshToken: false, persistSession: false } },
);

let configRows = new Map<string, ModelConfig>();
let loadedAt = 0;
let loading: Promise<void> | null = null;

async function modelConfig(task: string): Promise<ModelConfig | undefined> {
  if (Date.now() - loadedAt > 60000) {
    loading ??= (async () => {
      const { data, error } = await client.from("ai_model_config")
        .select("task, model, reasoning_effort, verbosity, fallback_model");
      if (error) throw new Error("Model configuration unavailable");
      configRows = new Map(data.map((row) => [row.task, row as ModelConfig]));
      loadedAt = Date.now();
    })().finally(() => {
      loading = null;
    });
    await loading;
  }
  return configRows.get(task);
}

Deno.serve(createProxyHandler({
  apiKey: Deno.env.get("OPENAI_API_KEY"),
  xaiApiKey: Deno.env.get("XAI_API_KEY"),
  // Public stored prompt ID, locked server-side. Optional override for deployments.
  promptID: Deno.env.get("OPENAI_EVE_PROMPT_ID") ??
    "pmpt_68ca79b240b88194874ccf374b434f0e070faf1e10d483e1",
  corsHeaders,
  authenticate: async (token) => {
    const { data, error } = await client.auth.getUser(token);
    return error || data.user?.is_anonymous ? null : data.user?.id ?? null;
  },
  modelConfig,
  reserveUsage: async (userID, textBytes, audioBytes) => {
    const { data, error } = await client.rpc("reserve_ai_proxy_usage", {
      p_user_id: userID,
      p_text_bytes: textBytes,
      p_audio_bytes: audioBytes,
    });
    if (error) throw new Error("Quota service unavailable");
    return data as string | null;
  },
  releaseUsage: async (id) => {
    const { error } = await client.from("ai_proxy_reservations").delete().eq(
      "id",
      id,
    );
    if (error) throw new Error("Reservation release failed");
  },
  claimConversation: async (userID, id) => {
    const { data, error } = await client.rpc("claim_ai_proxy_conversation", {
      p_user_id: userID,
      p_conversation_id: id,
    });
    if (error) throw new Error("Conversation registry unavailable");
    return data === true;
  },
  saveConversation: async (userID, id) => {
    const { error } = await client.from("ai_proxy_conversations").insert({
      id,
      user_id: userID,
    });
    if (error) throw new Error("Conversation registration failed");
  },
  upstream: (path, body, signal, provider = "openai") =>
    fetch(
      provider === "xai"
        ? "https://api.x.ai/v1/stt"
        : `https://api.openai.com/v1${path}`,
      {
        method: "POST",
        body,
        signal,
        headers: {
          Authorization: `Bearer ${
            Deno.env.get(provider === "xai" ? "XAI_API_KEY" : "OPENAI_API_KEY")
          }`,
          ...(body instanceof FormData
            ? {}
            : { "Content-Type": "application/json" }),
        },
      },
    ),
}));
