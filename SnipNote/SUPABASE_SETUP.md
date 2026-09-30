# Supabase Setup Instructions

## OpenAI proxy and model configuration

OpenAI credentials are stored only in Edge Function secrets as `OPENAI_API_KEY`.
Never put an OpenAI key in `Config.swift` or the app Keychain. The public Supabase
anon key below authenticates the project and is safe to ship; it is not a service key.

See `../OPENAI_PROXY_SETUP.md` for deployment order, model configuration, server
quotas, conversation ownership, verification, and key rotation. Apply the model
configuration migration and the proxy security migration before deploying `openai-proxy`.
The proxy safety budgets are separate from purchased transcription minutes.

## Add Supabase Package Dependency

1. Open SnipNote.xcodeproj in Xcode
2. Select the project in the navigator
3. Select the SnipNote target
4. Go to the "Package Dependencies" tab
5. Click the "+" button
6. Enter the package URL: https://github.com/supabase/supabase-swift
7. Click "Add Package"
8. Select "Supabase" from the package products
9. Click "Add Package"

## Supabase Project Details

- Project URL: https://bndbnqtvicvynzkyygte.supabase.co
- Anon Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJuZGJucXR2aWN2eW56a3l5Z3RlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI0MTgyNDUsImV4cCI6MjA2Nzk5NDI0NX0.KJR2WxJBeTY4diMjXISBsFwFiYsniX1r0xjDIF0sgY8

## Enable Email Authentication in Supabase Dashboard

1. Go to https://supabase.com/dashboard/project/bndbnqtvicvynzkyygte/auth/providers
2. Enable "Email" provider if not already enabled
3. Configure email settings as needed
