// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyAppleTransaction } from '../_shared/apple_jws.ts'
import { APPLE_ROOT_CA_G3_BASE64 } from '../_shared/apple_root.ts'

const BUNDLE_ID = 'com.mattianalytics.snipnote'
const rootCertDER = Uint8Array.from(atob(APPLE_ROOT_CA_G3_BASE64), (c) => c.charCodeAt(0))

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

    // Trust only what Apple signed: every field below comes from the verified payload, not the request body
    let verified
    try {
      verified = await verifyAppleTransaction(transactionData.signedTransactionInfo, { rootCertDER })
    } catch (verifyError) {
      console.error('Transaction verification failed:', (verifyError as Error).message)
      return new Response(
        JSON.stringify({ error: 'Transaction could not be verified' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 }
      )
    }
    if (verified.bundleId !== BUNDLE_ID) {
      return new Response(
        JSON.stringify({ error: 'Wrong bundle' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 }
      )
    }
    const verifiedData = {
      transactionId: String(verified.transactionId),
      originalTransactionId: String(verified.originalTransactionId),
      productId: verified.productId,
      purchaseDate: new Date(verified.purchaseDate).toISOString(),
      expiresDate: verified.expiresDate ? new Date(verified.expiresDate).toISOString() : undefined,
      isUpgraded: verified.isUpgraded === true,
      subscriptionGroupId: verified.subscriptionGroupId as string | undefined,
      environment: (verified.environment as string).toLowerCase(),
    }

    console.log(`Validating StoreKit transaction for user: ${userId}`)
    console.log(`Transaction ID: ${verifiedData.transactionId}`)
    console.log(`Product ID: ${verifiedData.productId}`)
    console.log(`Environment: ${verifiedData.environment}`)

    // Get user email for subscription record
    const userEmail = user.email || null

    // Check if this is a subscription product
    const isSubscription = verifiedData.productId.includes('pro_weekly') ||
                          verifiedData.productId.includes('pro_monthly') ||
                          verifiedData.productId.includes('pro_annual')

    if (isSubscription) {
      // Handle subscription validation
      const expiresAt = verifiedData.expiresDate ? new Date(verifiedData.expiresDate) : null
      const purchaseDate = new Date(verifiedData.purchaseDate)
      const isActive = expiresAt ? expiresAt > new Date() : true

      // A valid receipt can be replayed by another account: refuse if this subscription belongs to someone else
      const { data: owner } = await supabaseClient
        .from('subscriptions')
        .select('user_id')
        .eq('original_transaction_id', verifiedData.originalTransactionId)
        .neq('user_id', userId)
        .limit(1)
        .maybeSingle()
      if (owner) {
        return new Response(
          JSON.stringify({ error: 'Subscription belongs to another account' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 409 }
        )
      }

      // Insert or update subscription record
      const { error: subscriptionError } = await supabaseClient
        .from('subscriptions')
        .upsert({
          user_id: userId,
          user_email: userEmail,
          original_transaction_id: verifiedData.originalTransactionId,
          transaction_id: verifiedData.transactionId,
          product_identifier: verifiedData.productId,
          subscription_group_id: verifiedData.subscriptionGroupId,
          purchase_date: purchaseDate.toISOString(),
          expires_at: expiresAt?.toISOString(),
          is_active: isActive,
          auto_renew_status: !verifiedData.isUpgraded, // If upgraded, auto-renew is typically false
          store: 'app_store',
          environment: verifiedData.environment,
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

      console.log(`✅ Subscription validated and updated: ${verifiedData.productId}, active: ${isActive}`)

      // Send Telegram notification (non-blocking)
      sendTelegramNotification(verifiedData.productId, verifiedData.environment)
    }

    // For both subscriptions and consumables, we don't need to credit minutes here
    // The minutes crediting is handled by the iOS app's MinutesManager
    // This function just validates and records the subscription status

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Transaction validated successfully',
        isSubscription,
        environment: verifiedData.environment
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
        details: (error as Error).message
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