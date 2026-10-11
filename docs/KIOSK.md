# Gym Kiosk (front desk)

SQL: `supabase/migrations/0013_kiosk.sql` (`/workspace/bjj-bul-0013.sql`). Edge Function: `supabase/functions/kiosk-invite`.

## Setup
1. Run 0013 in the SQL Editor. Deploy the invite function: `supabase functions deploy kiosk-invite`
   (it uses the automatic SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY).
2. Supabase → Authentication → URL Configuration: add the app's redirect URL. The invite email is the standard
   "Invite user" template; customise it (bg/en) under Authentication → Email Templates.
3. On the iPad, sign in as an **owner or coach**. Open My gym → Kiosk, set an exit PIN (4–6 digits) and the waiver text,
   then tap **Start kiosk**.
   - The exit PIN is stored on the device as a salted SHA-256 hash.
   - "Also use as the gym staff PIN" saves a bcrypt hash in `gym_kiosk_settings`. The server uses it to confirm payments
     and new registrations. Keep it on: new-user check-ins need it.

## Lockdown
The app hides the home indicator and status bar (`.persistentSystemOverlays(.hidden)`, `.statusBarHidden`), keeps the screen awake,
returns home after 60 s idle and 5 s after a check-in, and needs the PIN to exit. An app can't stop the user from leaving it.
For a real lockdown use **Guided Access**:
Settings → Accessibility → Guided Access → On, set a passcode, then open BJJ Bul and triple-click the side/home button.
Optionally disable the hardware buttons and set a time limit. For many devices, an MDM in Single App Mode is better.

## Flows
- **Member, QR:** Profile → My QR shows a random token (valid 2 min, refreshed every 60 s) or a permanent member code.
  The kiosk scans it (front camera) and `kiosk_check_in` verifies it.
- **Member, name:** search needs at least 2 letters. It returns up to 8 members of this gym as "First L." + belt only.
  The member then types their 4-digit PIN (bcrypt, set in My QR). 5 wrong tries lock the PIN for 5 minutes.
- **BJJ Pass rules:**
  - An active subscription lets the member in.
  - Otherwise one credit is used.
  - With no credits the kiosk shows **Buy a pass** or **Pay later** (checks in flagged unpaid).
- **New user:** name, email, phone and belt create a `kiosk_leads` row. `kiosk-invite` sends a magic-link invite
  (or links an existing account), fills in the profile and adds a **pending** student membership. Then the person
  chooses a plan and pays; staff confirm with the PIN, which activates the membership.
- **Guest:** name, optional phone/email, waiver acceptance (a copy of the text is stored) and a drop-in plan, then pay or pay later.
  These are stored in `kiosk_guests` and `guest_attendance`.
- **Payment:** the price, then a QR of the gym's `revolut_url` plus the reference. revolut.me links don't reliably accept a
  prefilled amount or note, so the guest types the amount and the reference. Staff then tap **Paid cash** or **Paid Revolut**
  and enter the staff PIN (`kiosk_record_payment`): the payment is recorded and the pass is created at once.
- **Staff view:** My gym → Today's attendance lists members and guests, flags guests and unpaid check-ins, and refreshes every 15 s.

## Privacy & security
- The kiosk device is signed in as staff. Every kiosk RPC is `security definer` and checks `is_gym_staff(gym)`.
- The kiosk never shows emails or phones. Search shows only the first name, last initial and belt, needs at least 2 characters,
  and returns at most 8 rows. Member PIN and code hashes live in `member_secrets`, which clients can't read.
- The gym PIN hash is in `gym_kiosk_settings`, not in the public `gyms` table.
- Guest data (name, phone, email, waiver) is personal data. The privacy policy needs a "front-desk check-in" paragraph
  (TODO), and gyms should delete old guest rows they no longer need.
