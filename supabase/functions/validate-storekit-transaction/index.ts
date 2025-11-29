// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface TransactionData {
  transactionId: string
  originalTransactionId: string
  productId: string
  purchaseDate: string
  expiresDate?: string
  isUpgraded?: boolean
  subscriptionGroupId?: string
  environment: string
  signedTransactionInfo: string
}

interface ValidationRequest {
  userId: string
  transactionData: TransactionData
}

// Send Telegram notification for new subscriptions
async function sendTelegramNotification(productId: string, environment: string): Promise<void> {
  const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN')
  const chatId = Deno.env.get('TELEGRAM_CHAT_ID')

  if (!botToken || !chatId) {
    console.log('Telegram credentials not configured, skipping notification')
    return
  }

  // Map product ID to friendly name
  const productNames: Record<string, string> = {
    'snipnote_pro_weekly03': 'Weekly (1.99 EUR)',
    'snipnote_pro_monthly03': 'Monthly (4.99 EUR)',
    'snipnote_pro_annual03': 'Annual (39.99 EUR)'
  }

  const productName = productNames[productId] || productId
  const envEmoji = environment === 'sandbox' ? '🧪' : '💰'
  const envLabel = environment === 'sandbox' ? 'SANDBOX' : 'PRODUCTION'

  const message = `${envEmoji} *New SnipNote Subscription!*

📦 *Plan:* ${productName}
🌍 *Environment:* ${envLabel}`

  try {
    const response = await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        text: message,
        parse_mode: 'Markdown'
      })
    })

    if (!response.ok) {
      console.error('Failed to send Telegram notification:', await response.text())
    } else {
      console.log('✅ Telegram notification sent successfully')
    }
  } catch (error) {
    console.error('Error sending Telegram notification:', error)
  }
}

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
    const { userId, transactionData }: ValidationRequest = await req.json()

    // Verify that the user is validating their own transaction
    // Note: Use case-insensitive comparison because Swift's UUID.uuidString returns uppercase
    // while Supabase auth returns lowercase UUIDs
    if (user.id.toLowerCase() !== userId.toLowerCase()) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized: Can only validate your own transactions' }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 403
        }
      )
    }

    console.log(`Validating StoreKit transaction for user: ${userId}`)
    console.log(`Transaction ID: ${transactionData.transactionId}`)
    console.log(`Product ID: ${transactionData.productId}`)
    console.log(`Environment: ${transactionData.environment}`)

    // Get user email for subscription record
    const userEmail = user.email || null

    // Check if this is a subscription product
    const isSubscription = transactionData.productId.includes('pro_weekly') ||
                          transactionData.productId.includes('pro_monthly') ||
                          transactionData.productId.includes('pro_annual')

    if (isSubscription) {
      // Handle subscription validation
      const expiresAt = transactionData.expiresDate ? new Date(transactionData.expiresDate) : null
      const purchaseDate = new Date(transactionData.purchaseDate)
      const isActive = expiresAt ? expiresAt > new Date() : true

      // Insert or update subscription record
      const { error: subscriptionError } = await supabaseClient
        .from('subscriptions')
        .upsert({
          user_id: userId,
          user_email: userEmail,
          original_transaction_id: transactionData.originalTransactionId,
          transaction_id: transactionData.transactionId,
          product_identifier: transactionData.productId,
          subscription_group_id: transactionData.subscriptionGroupId,
          purchase_date: purchaseDate.toISOString(),
          expires_at: expiresAt?.toISOString(),
          is_active: isActive,
          auto_renew_status: !transactionData.isUpgraded, // If upgraded, auto-renew is typically false
          store: 'app_store',
          environment: transactionData.environment,
          updated_at: new Date().toISOString()
        }, {
          onConflict: 'user_id'
        })

      if (subscriptionError) {
        console.error('Error upserting subscription:', subscriptionError)
        return new Response(
          JSON.stringify({
            error: 'Failed to update subscription',
            details: subscriptionError.message
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500
          }
        )
      }

      console.log(`✅ Subscription validated and updated: ${transactionData.productId}, active: ${isActive}`)

      // Send Telegram notification (non-blocking)
      sendTelegramNotification(transactionData.productId, transactionData.environment)
    }

    // For both subscriptions and consumables, we don't need to credit minutes here
    // The minutes crediting is handled by the iOS app's MinutesManager
    // This function just validates and records the subscription status

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Transaction validated successfully',
        isSubscription,
        environment: transactionData.environment
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200
      }
    )

  } catch (error) {
    console.error('Error in validate-storekit-transaction function:', error)
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

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/validate-storekit-transaction' \
    --header 'Authorization: Bearer YOUR_USER_TOKEN' \
    --header 'Content-Type: application/json' \
    --data '{
      "userId": "USER_UUID",
      "transactionData": {
        "transactionId": "2000000123456789",
        "originalTransactionId": "1000000123456789",
        "productId": "snipnote_pro_monthly03",
        "purchaseDate": "2025-01-01T12:00:00Z",
        "expiresDate": "2025-02-01T12:00:00Z",
        "environment": "sandbox",
        "signedTransactionInfo": "base64encodedstring"
      }
    }'

*/