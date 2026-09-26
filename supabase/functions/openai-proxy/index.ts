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

const OPENAI_BASE_URL = 'https://api.openai.com/v1'

// Only the endpoints the app actually uses (all POST).
const ALLOWED_PATHS = new Set([
  '/audio/transcriptions',
  '/responses',
  '/conversations',
  '/chat/completions',
])

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

  // Forward the body untouched (JSON or multipart audio upload).
  const forwardHeaders = new Headers({ Authorization: `Bearer ${openAIKey}` })
  const contentType = req.headers.get('Content-Type')
  if (contentType) {
    forwardHeaders.set('Content-Type', contentType)
  }

  const startedAt = Date.now()

  let upstream: Response
  try {
    upstream = await fetch(`${OPENAI_BASE_URL}${openAIPath}`, {
      method: 'POST',
      headers: forwardHeaders,
      body: await req.arrayBuffer(),
    })
  } catch (error) {
    console.error(`OpenAI request failed for ${openAIPath}:`, error)
    return jsonResponse({ error: { message: 'Upstream request failed' } }, 502)
  }

  console.log(`${openAIPath} user=${user.id} status=${upstream.status} ${Date.now() - startedAt}ms`)

  // Relay OpenAI's status and body so the app's existing error handling keeps working.
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      ...corsHeaders,
      'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json',
    },
  })
})
