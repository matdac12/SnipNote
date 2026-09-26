// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

// Authenticated pass-through to the OpenAI API.
//
// The iOS app calls  <SUPABASE_URL>/functions/v1/openai-proxy/<openai-path>
// with the signed-in user's Supabase access token. This function verifies the
// user, swaps the token for the OpenAI key stored in Supabase secrets and
// forwards the request unchanged. The OpenAI key never leaves the server.
//
// Required secret:  supabase secrets set OPENAI_API_KEY=sk-...
//
// Model selection: when the app sends `X-SnipNote-Task: <task>`, the matching
// row in `public.ai_model_config` overrides model / reasoning effort / verbosity
// in the JSON body (or just the model field of a transcription upload), so
// models can be switched from the Supabase Table Editor without an app release.
// No header or no row = body forwarded as sent.

const OPENAI_BASE_URL = 'https://api.openai.com/v1'

// Only the endpoints the app actually uses (all POST).
const ALLOWED_PATHS = new Set([
  '/audio/transcriptions',
  '/responses',
  '/conversations',
  '/chat/completions',
])

// Endpoints whose body carries a model we may override
const MODEL_PATHS = new Set(['/responses', '/chat/completions', '/audio/transcriptions'])
const TRANSCRIPTION_PATH = '/audio/transcriptions'

// Sampling params reasoning models reject unless effort is "none"
const SAMPLING_PARAMS = ['temperature', 'top_p', 'logprobs', 'top_logprobs']

const CONFIG_TTL_MS = 60_000

interface ModelConfig {
  task: string
  model: string
  reasoning_effort: string | null
  verbosity: string | null
  fallback_model: string | null
}

let configCache: { loadedAt: number; rows: Map<string, ModelConfig> } | null = null

const serviceClient = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { autoRefreshToken: false, persistSession: false } }
)

async function getModelConfig(task: string): Promise<ModelConfig | undefined> {
  if (!configCache || Date.now() - configCache.loadedAt > CONFIG_TTL_MS) {
    const { data, error } = await serviceClient
      .from('ai_model_config')
      .select('task, model, reasoning_effort, verbosity, fallback_model')

    if (error) {
      // Keep serving the last known config (or none) rather than failing the call
      console.error('Failed to load ai_model_config:', error.message)
    } else {
      configCache = {
        loadedAt: Date.now(),
        rows: new Map((data as ModelConfig[]).map((row) => [row.task, row])),
      }
    }
  }
  return configCache?.rows.get(task)
}

// Apply a config row to a request body. Responses API and Chat Completions
// spell the reasoning/verbosity fields differently.
// deno-lint-ignore no-explicit-any
function applyModelConfig(body: any, path: string, config: ModelConfig, model: string) {
  body.model = model
  const effort = config.reasoning_effort

  if (path === '/responses') {
    if (effort) body.reasoning = { ...(body.reasoning ?? {}), effort }
    if (config.verbosity) body.text = { ...(body.text ?? {}), verbosity: config.verbosity }
  } else {
    if (effort) body.reasoning_effort = effort
    if (config.verbosity) body.verbosity = config.verbosity
    // Reasoning models only take max_completion_tokens
    if ('max_tokens' in body) {
      body.max_completion_tokens ??= body.max_tokens
      delete body.max_tokens
    }
  }

  if (effort && effort !== 'none') {
    for (const param of SAMPLING_PARAMS) delete body[param]
  }
}

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

Deno.serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const openAIKey = Deno.env.get('OPENAI_API_KEY')
  if (!openAIKey) {
    console.error('OPENAI_API_KEY secret is not set')
    return jsonResponse({ error: { message: 'Server misconfigured' } }, 500)
  }

  // Verify the user token
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return jsonResponse({ error: { message: 'No authorization header' } }, 401)
  }

  const supabaseClient = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { auth: { autoRefreshToken: false, persistSession: false } }
  )

  const token = authHeader.replace('Bearer ', '')
  const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token)

  if (authError || !user) {
    return jsonResponse({ error: { message: 'Invalid token' } }, 401)
  }

  // Resolve the OpenAI path: /openai-proxy/responses -> /responses
  const { pathname } = new URL(req.url)
  const openAIPath = pathname.replace(/^.*?\/openai-proxy/, '') || '/'

  if (req.method !== 'POST' || !ALLOWED_PATHS.has(openAIPath)) {
    console.warn(`Blocked ${req.method} ${openAIPath} for user ${user.id}`)
    return jsonResponse({ error: { message: 'Endpoint not allowed' } }, 403)
  }

  const forwardHeaders = new Headers({ Authorization: `Bearer ${openAIKey}` })
  const contentType = req.headers.get('Content-Type')
  if (contentType) {
    forwardHeaders.set('Content-Type', contentType)
  }

  const callOpenAI = (body: BodyInit) =>
    fetch(`${OPENAI_BASE_URL}${openAIPath}`, { method: 'POST', headers: forwardHeaders, body })

  // Resolve per-task model config
  const task = req.headers.get('X-SnipNote-Task')
  const config = task && MODEL_PATHS.has(openAIPath) ? await getModelConfig(task) : undefined
  const isTranscription = openAIPath === TRANSCRIPTION_PATH

  // Parsed body when a config applies: FormData for transcription uploads, JSON otherwise
  // deno-lint-ignore no-explicit-any
  let body: any
  if (config) {
    try {
      body = isTranscription ? await req.formData() : await req.json()
    } catch {
      return jsonResponse({ error: { message: 'Invalid request body' } }, 400)
    }
    if (isTranscription) {
      // fetch() generates a new multipart boundary for the rebuilt form
      forwardHeaders.delete('Content-Type')
    }
  }

  const setModel = (model: string): BodyInit => {
    if (isTranscription) {
      // Only the model applies to transcription; effort/verbosity are ignored
      body.set('model', model)
      return body
    }
    applyModelConfig(body, openAIPath, config!, model)
    return JSON.stringify(body)
  }

  const startedAt = Date.now()
  let upstream: Response
  let usedModel = 'as-sent'

  try {
    if (config) {
      usedModel = config.model
      upstream = await callOpenAI(setModel(config.model))

      // One retry on the fallback model if OpenAI rejected the request
      const fallback = config.fallback_model
      if ((upstream.status === 400 || upstream.status === 404) && fallback && fallback !== config.model) {
        const errorText = await upstream.text()
        console.warn(`${openAIPath} task=${task} model=${config.model} rejected (${upstream.status}): ${errorText.slice(0, 300)} -> retrying with ${fallback}`)
        usedModel = fallback
        upstream = await callOpenAI(setModel(fallback))
      }
    } else {
      // Forward the body untouched (JSON or multipart audio upload).
      upstream = await callOpenAI(await req.arrayBuffer())
    }
  } catch (error) {
    console.error(`OpenAI request failed for ${openAIPath}:`, error)
    return jsonResponse({ error: { message: 'Upstream request failed' } }, 502)
  }

  console.log(`${openAIPath} task=${task ?? '-'} model=${usedModel} user=${user.id} status=${upstream.status} ${Date.now() - startedAt}ms`)

  // Relay OpenAI's status and body so the app's existing error handling keeps working.
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      ...corsHeaders,
      'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json',
    },
  })
})
