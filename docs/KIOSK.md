# Gym Kiosk (front desk)

SQL: `supabase/migrations/0013_kiosk.sql`. Edge Function: `supabase/functions/kiosk-invite`.

## Setup
1. Run 0013. Deploy the function: `supabase functions deploy kiosk-invite`. It uses the automatic SUPABASE_URL,
   SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY secrets.
2. Supabase → Auth → Email templates → "Invite user": the template members receive from the desk. Set the Site URL / redirect URLs.
3. On the iPad: sign in as an owner or coach → Profile → My gym → (gym) → Kiosk. Set a 4–6 digit exit PIN.
   "Also use as the gym staff PIN" (on by default) stores a bcrypt hash in `gym_kiosk_settings`. That staff PIN confirms
   desk payments and new registrations. Edit the guest waiver text here.
4. Start the kiosk. The device stays signed in as that staff member; every kiosk call is a security-definer RPC that checks
   `is_gym_staff(gym)`.

## True lockdown: Guided Access
The app hides the home indicator (`persistentSystemOverlays(.hidden)`), hides the status bar and keeps the screen awake,
but iOS doesn't let an app stop someone from leaving it. For a real kiosk:
- Settings → Accessibility → Guided Access → On; set a passcode and enable Accessibility Shortcut.
- Open the kiosk, triple-click the side/home button → Start. Triple-click and enter the passcode to end.
- Optional: Settings → Display → Auto-Lock → Never; keep the iPad plugged in. For many devices, use MDM "Single App Mode".

## Flows
- **Home:** today's classes (the one starting within 30 min or in progress is highlighted) plus "Open mat / other".
- **Member:**
  - Scan QR: Profile → My QR shows `bjjbul:t:<token>`, a random token valid 2 min that rotates every 60 s, or the static member code `bjjbul:c:<code>`.
  - Or search by name: at least 2 characters, max 8 results, "First L." plus belt only, no emails or phones. Then enter the 4-digit member PIN
    (bcrypt in `member_secrets`; 5 wrong tries lock it for 5 minutes).
- **Check-in:** follows the BJJ Pass rules:
  - A subscription covers it; otherwise one credit is used.
  - With no credits the kiosk shows "Buy a pass" or "Pay later" (checked in, marked unpaid).
- **New user:** name, email, phone, belt → `kiosk_create_lead` → `kiosk-invite` (magic-link invite email, profile name/belt,
  pending student membership; if the email already has an account it's just linked) → choose a plan → pay. Check-in uses the staff PIN as proof.
- **Guest:** name, optional phone/email, waiver acceptance → drop-in plan → pay → check in. Stored in `kiosk_guests` and `guest_attendance`.
- **Payment step:**
  - Shows the price, a QR of the gym's `revolut_url` (CoreImage) and the reference. Revolut.me links don't reliably
    accept a prefilled amount or note, so the amount and reference are shown as text.
  - "Paid cash" or "Paid Revolut" plus the staff PIN → `kiosk_record_payment`. This creates the member payment immediately,
    which creates the pass, and activates a pending membership.
  - "Pay later" checks in as unpaid.
- Success screen returns home after 5 s. Any other screen returns home after 60 s idle. The lock icon (top right) plus the exit PIN closes the kiosk.

## Staff
My gym → Today's attendance: members and guests, unpaid flagged, refreshed every 15 s and on pull to refresh.

## Privacy
- The kiosk never shows emails or phones. Name search needs 2+ characters and returns short names.
- Leads and guests are readable only by that gym's staff. PIN hashes and member codes live in tables with no client access.
- Guests accept the waiver text, and a snapshot of it is stored with the guest row.
