// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"

interface WebhookPayload {
  type: 'INSERT'
  table: string
  record: {
    id: string
    email?: string
    created_at: string
  }
  schema: string
}

// Send Telegram notification for new user signups
async function sendTelegramNotification(email: string | undefined): Promise<void> {
  const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN')
  const chatId = Deno.env.get('TELEGRAM_CHAT_ID')

  if (!botToken || !chatId) {
    console.log('Telegram credentials not configured, skipping notification')
    return
  }

  const displayEmail = email || 'Unknown email'
  const message = `👤 *New SnipNote User!*

📧 *Email:* ${displayEmail}`

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
      console.log('✅ Telegram notification sent for new user signup')
    }
  } catch (error) {
    console.error('Error sending Telegram notification:', error)
  }
}

Deno.serve(async (req) => {
  try {
    const payload: WebhookPayload = await req.json()

    console.log(`New user signup: ${payload.record.email || payload.record.id}`)

    // Send Telegram notification
    await sendTelegramNotification(payload.record.email)

    return new Response(
      JSON.stringify({ success: true }),
      { headers: { 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    console.error('Error in on-user-signup function:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: error.message }),
      { headers: { 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
