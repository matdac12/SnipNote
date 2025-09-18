# Complete Supabase Edge Function Deployment Guide

## Prerequisites Check

### 1. Verify Supabase CLI is installed
```bash
supabase --version
```
✅ You have v2.24.3 installed (consider updating to latest version)

### 2. Update Supabase CLI (Optional but recommended)
```bash
brew upgrade supabase
```

## Step-by-Step Deployment

### Step 1: Login to Supabase
```bash
supabase login
```
This will open your browser to authenticate. Click "Generate token" and paste it back in the terminal.

### Step 2: Link your project
You need your project reference ID from Supabase dashboard.

1. Go to https://supabase.com/dashboard
2. Select your SnipNote project
3. Go to Settings > General
4. Copy your "Reference ID" (looks like: `abcdefghijklmnop`)

Now link it:
```bash
cd /Users/mattia/Documents/Projects/Xcodestuff/SnipNote/SnipNote
supabase link --project-ref YOUR_PROJECT_REF_HERE
```

Example:
```bash
supabase link --project-ref abcdefghijklmnop
```

### Step 3: Verify the link
```bash
supabase status
```
This should show your linked project details.

### Step 4: Deploy the delete-account function
```bash
supabase functions deploy delete-account
```

You should see output like:
```
Deploying Function: delete-account
Deployed Function: delete-account
URL: https://YOUR_PROJECT_REF.supabase.co/functions/v1/delete-account
```

### Step 5: Verify deployment
Check if the function is deployed:
```bash
supabase functions list
```

You should see:
```
┌─────────────────┬─────────┬─────────────────────┐
│ NAME            │ VERSION │ CREATED AT          │
├─────────────────┼─────────┼─────────────────────┤
│ delete-account  │ 1       │ 2025-08-28 12:00:00 │
└─────────────────┴─────────┴─────────────────────┘
```

## Testing the Deployed Function

### Option 1: Test with curl (Advanced)
First, get a test user token from your app, then:

```bash
# Replace these values:
# YOUR_PROJECT_REF: your project reference ID
# YOUR_USER_TOKEN: a valid user JWT token
# USER_UUID: the user's UUID to delete

curl -i --location --request POST \
  'https://YOUR_PROJECT_REF.supabase.co/functions/v1/delete-account' \
  --header 'Authorization: Bearer YOUR_USER_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"user_id":"USER_UUID"}'
```

### Option 2: Test from the app (Recommended)
1. Create a test account in your app
2. Add some test data (meetings, notes)
3. Go to Settings > Account
4. Click "Delete Account"
5. Follow the confirmation steps
6. Verify the account is deleted

## Monitoring and Logs

### View function logs
```bash
supabase functions logs delete-account
```

### View recent invocations
```bash
supabase functions logs delete-account --tail 10
```

## Troubleshooting

### If deployment fails:

1. **Check you're in the right directory:**
```bash
pwd
# Should output: /Users/mattia/Documents/Projects/Xcodestuff/SnipNote/SnipNote
```

2. **Check the function exists:**
```bash
ls supabase/functions/delete-account/
# Should show: index.ts and deno.json
```

3. **Check you're logged in:**
```bash
supabase login
```

4. **Check project is linked:**
```bash
supabase status
```

### Common Issues:

**Issue: "Project not linked"**
```bash
supabase link --project-ref YOUR_PROJECT_REF
```

**Issue: "Not authenticated"**
```bash
supabase login
```

**Issue: "Function not found"**
Make sure you're in the project root directory where the `supabase` folder exists.

## Updating the Function

If you need to make changes to the function:

1. Edit `/supabase/functions/delete-account/index.ts`
2. Deploy again:
```bash
supabase functions deploy delete-account
```

## Security Notes

⚠️ **Important**: The delete-account function uses the service role key to delete auth users. This is automatically available in the edge function environment - you don't need to set it manually.

The function verifies:
- User is authenticated
- User can only delete their own account
- All operations are logged

## Verify in Supabase Dashboard

After deployment, you can also verify in the dashboard:

1. Go to https://supabase.com/dashboard
2. Select your project
3. Navigate to "Edge Functions" in the sidebar
4. You should see `delete-account` listed
5. Click on it to see invocation history and logs

## Next Steps

Once deployed successfully:
1. ✅ The account deletion feature will work in your app
2. ✅ You're compliant with App Store requirements
3. ✅ Users can delete their accounts and all data

## Need Help?

- Supabase Docs: https://supabase.com/docs/guides/functions
- Edge Functions Guide: https://supabase.com/docs/guides/functions/quickstart
- CLI Reference: https://supabase.com/docs/reference/cli/introduction