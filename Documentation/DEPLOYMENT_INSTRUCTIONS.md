# Deployment Instructions for Account Deletion Feature

## Edge Function Deployment

The account deletion feature requires deploying a Supabase Edge Function. Follow these steps:

### 1. Deploy the delete-account function

```bash
# Deploy the function to your Supabase project
supabase functions deploy delete-account

# The function should be accessible at:
# https://[PROJECT_ID].supabase.co/functions/v1/delete-account
```

### 2. Test the function locally (optional)

```bash
# Start Supabase locally
supabase start

# Test the function
curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/delete-account' \
  --header 'Authorization: Bearer YOUR_USER_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"user_id":"USER_UUID"}'
```

### 3. Verify the deployment

After deployment, the delete-account function will:
1. Verify user authentication
2. Delete all user data in the correct order:
   - Actions
   - Meetings
   - Notes
   - Eve messages (chat history)
   - Usage metrics
   - Monthly usage
   - Subscriptions
   - Profile
   - Auth user account
3. Return success or error status

## App Store Compliance

The implementation now includes:

✅ **Account Deletion Button**: Located in Settings > Account section
✅ **Two-Step Confirmation**: 
   - First alert with warning
   - Second confirmation requires typing "DELETE"
✅ **Complete Data Removal**: Edge function deletes all user data and auth account
✅ **Manage Subscription**: Button for pro users to manage their subscription

## Testing the Account Deletion Flow

1. Open the app and sign in
2. Navigate to Settings
3. Scroll to the Account section
4. Tap "Delete Account"
5. Confirm the first warning
6. Type "DELETE" in the confirmation dialog
7. Tap "Delete Account" to complete

The account and all associated data will be permanently deleted.

## Notes

- The edge function requires the `SUPABASE_SERVICE_ROLE_KEY` to delete auth users
- CORS is configured to allow requests from the app
- All deletions are logged for debugging purposes
- Users can only delete their own accounts (verified by token)