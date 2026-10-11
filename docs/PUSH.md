# Push notifications (APNs)

## How it works
1. The app asks for permission (Profile → Notification settings → Enable push), registers with APNs and calls `register_device(p_token, p_environment)`; tokens live in `device_tokens`.
2. Triggers create rows in `notifications` (shown in-app under the bell):
   - new row in `events` → everyone with `notification_prefs.new_events` (default on);
   - new row in `open_mats` → followers of that gym (`gym_follows`) with `open_mats_followed` on.
3. A trigger on `notifications` queues a row in `notifications_outbox` when the user has a device token.
4. The Edge Function `send-push` sends pending outbox rows through APNs and marks them `sent` / `failed`.

Without step 4 configured, everything still works in-app; only the remote push is missing.

## APNs key setup
1. developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → `com.bjjbul.app` → enable **Push Notifications** → Save.
2. Keys → **+** → name "BJJ Bul APNs" → tick **Apple Push Notifications service (APNs)** → Continue → Register → **Download** the `.p8` (only downloadable once). Note the **Key ID** and your **Team ID** (top right / Membership).
3. In Xcode, the target already has the Push Notifications capability through `project.yml` (`aps-environment`). Run `xcodegen` again after pulling.
4. Deploy and configure the function:
   ```bash
   supabase functions deploy send-push
   supabase secrets set APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=YYYYYYYYYY APNS_BUNDLE_ID=com.bjjbul.app
   supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
   ```
5. Schedule it (SQL Editor; requires the `pg_cron` and `pg_net` extensions, enable under Database → Extensions):
   ```sql
   select cron.schedule('send-push', '* * * * *', $$
     select net.http_post(
       url := 'https://<project-ref>.supabase.co/functions/v1/send-push',
       headers := jsonb_build_object('Authorization', 'Bearer <SERVICE_ROLE_KEY>')
     );
   $$);
   ```
   Keep the service role key out of git.

Debug builds register as `development` (APNs sandbox); TestFlight/App Store builds as `production`.
