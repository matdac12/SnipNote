// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

// Authenticated pass-through to the OpenAI API.
//
// The iOS app calls  <SUPABASE_URL>/functions/v1/openai-proxy/<openai-path>
// with the signed-in user's Supabase access token. This function verifies the
// user, swaps the token for the OpenAI key stored in Supabase secrets and
// forwards the request. The OpenAI key never leaves the server.
//
// Required secret:  supabase secrets set OPENAI_API_KEY=sk-...
//
// Model selection: when the app sends `X-SnipNote-Task: <task>`, the matching
// row in `public.ai_model_config` overrides model / reasoning effort / verbosity
// in the JSON body (or just the model field of a transcription upload), so
// models can be switched from the Supabase Table Editor without an app release.
// No header or no row = body forwarded as sent.

const OPENAI_BASE_URL = 'https://api.openai.com/v1'
const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')

const TRANSCRIPTION_PATH = '/audio/transcriptions'

// Only the endpoints the app actually uses (all POST).
const ALLOWED_PATHS = new Set(['/responses', '/conversations', TRANSCRIPTION_PATH])

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

// Service role: verifies user tokens and reads ai_model_config (RLS, no policies)
const serviceClient = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { autoRefreshToken: false, persistSession: false } }
)

let configRows = new Map<string, ModelConfig>()
let configLoadedAt = 0
let configLoading: Promise<void> | null = null

async function loadModelConfig(): Promise<void> {
  const { data, error } = await serviceClient
    .from('ai_model_config')
    .select('task, model, reasoning_effort, verbosity, fallback_model')

  if (error) {
    // Keep serving the last known config (or none) rather than failing the call
    console.error('Failed to load ai_model_config:', error.message)
  } else {
    configRows = new Map((data as ModelConfig[]).map((row) => [row.task, row]))
  }
  // Also set on failure so an unreachable table is retried once per TTL, not per request
  configLoadedAt = Date.now()
}

async function getModelConfig(task: string): Promise<ModelConfig | undefined> {
  if (Date.now() - configLoadedAt > CONFIG_TTL_MS) {
    // Concurrent requests share one in-flight load
    configLoading ??= loadModelConfig().finally(() => { configLoading = null })
    await configLoading
  }
  return configRows.get(task)
}

// Apply a config row to a Responses API body
// deno-lint-ignore no-explicit-any
function applyModelConfig(body: any, config: ModelConfig, model: string) {
  body.model = model
  const effort = config.reasoning_effort

  if (effort) body.reasoning = { ...(body.reasoning ?? {}), effort }
  if (config.verbosity) body.text = { ...(body.text ?? {}), verbosity: config.verbosity }

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

  if (!OPENAI_API_KEY) {
    console.error('OPENAI_API_KEY secret is not set')
    return jsonResponse({ error: { message: 'Server misconfigured' } }, 500)
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return jsonResponse({ error: { message: 'No authorization header' } }, 401)
  }

  // Resolve the OpenAI path: /openai-proxy/responses -> /responses
  const { pathname } = new URL(req.url)
  const openAIPath = pathname.replace(/^.*?\/openai-proxy/, '') || '/'
  const task = req.headers.get('X-SnipNote-Task')

  // Verify the user token and look up the task config in parallel
  const token = authHeader.replace('Bearer ', '')
  const [{ data: { user }, error: authError }, config] = await Promise.all([
    serviceClient.auth.getUser(token),
    task ? getModelConfig(task) : Promise.resolve(undefined),
  ])

  if (authError || !user) {
    return jsonResponse({ error: { message: 'Invalid token' } }, 401)
  }

  if (req.method !== 'POST' || !ALLOWED_PATHS.has(openAIPath)) {
    console.warn(`Blocked ${req.method} ${openAIPath} for user ${user.id}`)
    return jsonResponse({ error: { message: 'Endpoint not allowed' } }, 403)
  }

  const isTranscription = openAIPath === TRANSCRIPTION_PATH
  const forwardHeaders = new Headers({ Authorization: `Bearer ${OPENAI_API_KEY}` })

  // Parsed body when a config applies: FormData for transcription uploads, JSON otherwise.
  // Without a config the body is forwarded untouched.
  // deno-lint-ignore no-explicit-any
  let body: any
  if (config) {
    try {
      body = isTranscription ? await req.formData() : await req.json()
    } catch {
      return jsonResponse({ error: { message: 'Invalid request body' } }, 400)
    }
  }
  // fetch() sets the multipart boundary itself when sending the rebuilt form
  const contentType = req.headers.get('Content-Type')
  if (contentType && !(config && isTranscription)) {
    forwardHeaders.set('Content-Type', contentType)
  }

  const bodyWithModel = (model: string): BodyInit => {
    if (isTranscription) {
      // Only the model applies to transcription; effort/verbosity are ignored
      body.set('model', model)
      return body
    }
    applyModelConfig(body, config!, model)
    return JSON.stringify(body)
  }

  const callOpenAI = (requestBody: BodyInit) =>
    fetch(`${OPENAI_BASE_URL}${openAIPath}`, { method: 'POST', headers: forwardHeaders, body: requestBody })

  const startedAt = Date.now()
  let upstream: Response
  let usedModel = 'as-sent'

  try {
    if (config) {
      usedModel = config.model
      upstream = await callOpenAI(bodyWithModel(config.model))

      // One retry on the fallback model if OpenAI rejected the request
      const fallback = config.fallback_model
      if ((upstream.status === 400 || upstream.status === 404) && fallback && fallback !== config.model) {
        const errorText = await upstream.text()
        console.warn(`${openAIPath} task=${task} model=${config.model} rejected (${upstream.status}): ${errorText.slice(0, 300)} -> retrying with ${fallback}`)
        usedModel = fallback
        upstream = await callOpenAI(bodyWithModel(fallback))
      }
    } else {
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
