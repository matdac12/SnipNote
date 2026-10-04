import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  try {
    // Create Supabase client with service role key for admin operations
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    // Verify internal secret header for security (since JWT is disabled).
    // The secret lives in Vault and is shared with cleanup_audio_on_job_completion().
    const internalSecret = req.headers.get('x-internal-secret')
    const { data: expectedSecret, error: secretError } = await supabase.rpc('get_cleanup_internal_secret')
    if (secretError || !expectedSecret || internalSecret !== expectedSecret) {
      console.error('Unauthorized: Invalid internal secret')
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const { meeting_id, user_id } = await req.json()
    
    if (!meeting_id) {
      return new Response(
        JSON.stringify({ error: 'meeting_id is required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Starting cleanup for meeting: ${meeting_id}`)

    // 1. Get file paths from audio_chunks table
    const { data: chunks, error: chunksError } = await supabase
      .from('audio_chunks')
      .select('file_path')
      .eq('meeting_id', meeting_id)
    
    if (chunksError) {
      console.error('Error fetching chunks:', chunksError)
    }

    const filesToDelete: string[] = []
    
    // Add chunk file paths
    if (chunks && chunks.length > 0) {
      for (const chunk of chunks) {
        if (chunk.file_path) {
          filesToDelete.push(chunk.file_path)
        }
      }
    }

    // Also add the main recording file pattern (for non-chunked uploads)
    // Pattern: userId/meetingId.m4a
    if (user_id) {
      filesToDelete.push(`${user_id}/${meeting_id}.m4a`)
    }

    console.log(`Files to delete: ${JSON.stringify(filesToDelete)}`)

    // 2. Delete files from Storage
    let storageDeletedCount = 0
    if (filesToDelete.length > 0) {
      const { data: deleteData, error: deleteError } = await supabase
        .storage
        .from('recordings')
        .remove(filesToDelete)
      
      if (deleteError) {
        console.error('Error deleting from storage:', deleteError)
      } else {
        storageDeletedCount = deleteData?.length || 0
        console.log(`Deleted ${storageDeletedCount} files from storage`)
      }
    }

    // 3. Delete audio_chunks records from database
    const { error: dbDeleteError, count } = await supabase
      .from('audio_chunks')
      .delete({ count: 'exact' })
      .eq('meeting_id', meeting_id)
    
    if (dbDeleteError) {
      console.error('Error deleting audio_chunks records:', dbDeleteError)
    } else {
      console.log(`Deleted ${count} audio_chunks records`)
    }

    // 4. Also delete from recordings table
    const { error: recordingsDeleteError } = await supabase
      .from('recordings')
      .delete()
      .eq('meeting_id', meeting_id)
    
    if (recordingsDeleteError) {
      console.error('Error deleting recordings record:', recordingsDeleteError)
    }

    return new Response(
      JSON.stringify({ 
        success: true,
        meeting_id,
        storage_files_deleted: storageDeletedCount,
        chunks_records_deleted: count || 0
      }),
      { 
        status: 200, 
        headers: { 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Error in cleanup-audio-storage:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
