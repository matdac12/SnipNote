This is a guide on some OpenAI commands we can use to set up the application. 

The API key is saved under openAIAPIKey in the @Config file. 


Upload a File: https://platform.openai.com/docs/api-reference/files/create

curl https://api.openai.com/v1/files \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F purpose="fine-tune" \
  -F file="@mydata.jsonl"
  -F expires_after[anchor]="created_at"
  -F expires_after[seconds]=2592000

response:

{
  "id": "file-abc123",
  "object": "file",
  "bytes": 120000,
  "created_at": 1677610602,
  "expires_at": 1677614202,
  "filename": "mydata.jsonl",
  "purpose": "fine-tune",
}


Delete a file:

curl https://api.openai.com/v1/files/file-abc123 \
  -X DELETE \
  -H "Authorization: Bearer $OPENAI_API_KEY"
  
  
Create vector store file

Create a vector store file by attaching a File to a vector store.

vector store ID to ue: vs_68bab4cb23008191826c1a26c2e0347c

curl https://api.openai.com/v1/vector_stores/vs_abc123/files \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -H "OpenAI-Beta: assistants=v2" \
    -d '{
      "file_id": "file-abc123"
    }'

response:

{
  "id": "file-abc123",
  "object": "vector_store.file",
  "created_at": 1699061776,
  "usage_bytes": 1234,
  "vector_store_id": "vs_abcd",
  "status": "completed",
  "last_error": null
}



For now, we will use this code to get responsed:

curl https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4.1",
    "tools": [{
      "type": "file_search",
      "vector_store_ids": ["vs_1234567890"],
      "max_num_results": 20
    }],
    "input": "What can you tell me about my documents"
  }'


