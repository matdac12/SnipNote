// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Create Supabase client with service role key for admin operations
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    // Get the authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'No authorization header' }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 401
        }
      )
    }

    // Verify the user token
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token)
    
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid token', details: authError?.message }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 401
        }
      )
    }

    // Parse the request body
    const { user_id } = await req.json()
    
    // Verify that the user is deleting their own account
    if (user.id !== user_id) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized: Can only delete your own account' }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 403
        }
      )
    }

    console.log(`Starting account deletion for user: ${user_id}`)

    // Delete user data in the correct order (respecting foreign key constraints)
    
    // 1. Delete actions (references meetings and notes)
    const { error: actionsError } = await supabaseClient
      .from('actions')
      .delete()
      .eq('user_id', user_id)
    
    if (actionsError) {
      console.error('Error deleting actions:', actionsError)
    }

    // 2. Delete meetings
    const { error: meetingsError } = await supabaseClient
      .from('meetings')
      .delete()
      .eq('user_id', user_id)
    
    if (meetingsError) {
      console.error('Error deleting meetings:', meetingsError)
    }

    // 3. Delete notes
    const { error: notesError } = await supabaseClient
      .from('notes')
      .delete()
      .eq('user_id', user_id)
    
    if (notesError) {
      console.error('Error deleting notes:', notesError)
    }

    // 4. Delete eve_messages (chat history)
    const { error: eveMessagesError } = await supabaseClient
      .from('eve_messages')
      .delete()
      .eq('user_id', user_id)
    
    if (eveMessagesError) {
      console.error('Error deleting eve messages:', eveMessagesError)
    }

    // 5. Delete usage_metrics
    const { error: usageMetricsError } = await supabaseClient
      .from('usage_metrics')
      .delete()
      .eq('user_id', user_id)
    
    if (usageMetricsError) {
      console.error('Error deleting usage metrics:', usageMetricsError)
    }

    // 6. Delete subscriptions
    const { error: subscriptionsError } = await supabaseClient
      .from('subscriptions')
      .delete()
      .eq('user_id', user_id)
    
    if (subscriptionsError) {
      console.error('Error deleting subscriptions:', subscriptionsError)
    }

    // 7. Delete user profile
    const { error: profileError } = await supabaseClient
      .from('profiles')
      .delete()
      .eq('id', user_id)
    
    if (profileError) {
      console.error('Error deleting profile:', profileError)
    }

    // 8. Finally, delete the auth user account
    // This requires admin privileges via service role key
    const { error: deleteUserError } = await supabaseClient.auth.admin.deleteUser(user_id)
    
    if (deleteUserError) {
      console.error('Error deleting auth user:', deleteUserError)
      return new Response(
        JSON.stringify({ 
          error: 'Failed to delete auth account',
          details: deleteUserError.message 
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 500
        }
      )
    }

    console.log(`Successfully deleted account for user: ${user_id}`)

    return new Response(
      JSON.stringify({ 
        success: true,
        message: 'Account and all associated data deleted successfully'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200
      }
    )

  } catch (error) {
    console.error('Error in delete-account function:', error)
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error',
        details: error.message 
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500
      }
    )
  }
})

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/delete-account' \
    --header 'Authorization: Bearer YOUR_USER_TOKEN' \
    --header 'Content-Type: application/json' \
    --data '{"user_id":"USER_UUID"}'

*/