# Ask BJJ (AI chat)

The app calls the Edge Function `ask-bjj` with `supabase.functions.invoke` (the user's JWT is sent automatically).
The function checks the user, takes one message from today's quota (`ai_usage`, Europe/Sofia day), looks up matching
gyms / events / open mats, calls an OpenAI-compatible `/chat/completions` endpoint and stores the exchange in
`ai_conversations` / `ai_messages` (users can read and delete only their own history).

## Deploy
1. Apply `supabase/migrations/0008_ai_chat.sql` in the SQL Editor (0007 is optional; missing tables are skipped).
2. Deploy and configure:
   ```bash
   supabase functions deploy ask-bjj
   supabase secrets set AI_API_KEY=xai-...                # required
   # optional:
   supabase secrets set AI_BASE_URL=https://api.x.ai/v1   # or https://api.openai.com/v1
   supabase secrets set AI_MODEL=grok-4                   # any chat model the provider offers
   supabase secrets set AI_DAILY_LIMIT=30
   ```
   JWT verification stays on (the default), and the function also validates the token itself.
3. Test:
   ```bash
   curl -X POST https://<project-ref>.supabase.co/functions/v1/ask-bjj \
     -H "Authorization: Bearer <user access token>" -H "content-type: application/json" \
     -d '{"message":"Кои зали има в Пловдив?","locale":"bg"}'
   ```
   Errors: 401 not signed in, 429 daily limit, 503 `AI_API_KEY` missing, 502 provider error (the message is refunded).

## Cost notes
- Each message = one completion: system prompt + up to 12 previous messages + retrieved data (capped at ~12k chars) + up to 900 output tokens.
  Roughly 2–5k input tokens and ≤900 output tokens per message.
- Worst case per day = active users × `AI_DAILY_LIMIT` messages. Lower the limit or pick a cheaper/faster model via `AI_MODEL` to control spend.
- Set a monthly spending cap in the provider console (xAI / OpenAI).
- Responses are not streamed (more reliable with `functions.invoke`); the app shows a typing indicator meanwhile.

## Privacy
Messages are sent to the AI provider and kept in `ai_messages`. Mention this in the Privacy Policy before release
(processor: xAI or OpenAI, purpose: answering questions; users can delete conversations). Old rows can be purged with e.g.
`delete from ai_conversations where updated_at < now() - interval '180 days';`
