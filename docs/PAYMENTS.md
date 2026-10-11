# Payments

There are two separate money flows. BJJ Bul doesn't process either one inside the iOS app.

## 1. Students → their gym (gym's own money)
Staff record payments the gym has already received (cash / Revolut / card) in **My gym → Payments**
(`member_payments`). The app only keeps a ledger and shows who has paid or is overdue this month (`gym_payment_status`).
No money moves through BJJ Bul.

## 2. Gyms → BJJ Bul (B2B subscription)
- **Plans:** `plans` (Basic / Pro, `price_monthly_eur`; edit in the Table Editor; prices seeded as placeholders).
- **Status:** `gym_subscriptions` per gym: `trialing | active | past_due | cancelled`, `trial_ends_at`, `current_period_end`, `method`.
- **Trial:** approving an owner claim (`admin_approve_gym_claim`) starts a **30-day trial**.
- **Gate:** management writes (classes, members, memberships, payments, attendance, promotions, invites, gym profile)
  require `gym_has_access(gym)` = trialing (not expired) or active (not past `current_period_end`). Reading stays available.

### Today: Revolut / cash, marked by an admin
1. The owner opens **My gym → BJJ Bul subscription**, which shows the status and *billing instructions*:
   the Revolut payment page **https://revolut.me/tavetoopk**, cash instructions and a billing email.
2. The payment **reference is the gym's slug** (`gyms.slug`), shown with a copy button. revolut.me links don't
   reliably accept a prefilled note, so the owner pastes the slug into the Revolut payment note.
3. When the money arrives, the admin runs in the SQL Editor:
   ```sql
   select public.admin_record_subscription_payment(
     (select id from gyms where slug = '<slug>'), 19.00, 'revolut', '<revolut tx id or note>', 1);
   ```
   This logs `subscription_payments`, sets the status to `active` and extends `current_period_end` by N months.
4. Optional housekeeping, daily: `select public.admin_expire_subscriptions();` (or schedule it with pg_cron).

### Later: Stripe Checkout + webhook (schema already prepared)
- Columns: `gym_subscriptions.stripe_customer_id`, `stripe_subscription_id`, `subscription_payments.stripe_invoice_id`, `method = 'stripe'`.
- Flow:
  1. A **web** billing page (not in the iOS app) calls an Edge Function `create-checkout` that creates a Stripe Customer
     (stored as `stripe_customer_id`) and a Checkout Session in `subscription` mode for the plan's Stripe Price,
     with `metadata.gym_id` set.
  2. An Edge Function `stripe-webhook` verifies the `Stripe-Signature` and handles:
     - `checkout.session.completed` → save `stripe_subscription_id`;
     - `invoice.paid` → insert into `subscription_payments` (method `stripe`, `stripe_invoice_id`), set `active`
       and `current_period_end = invoice.lines[0].period.end`;
     - `invoice.payment_failed` → `past_due`;
     - `customer.subscription.deleted` → `cancelled`.
  3. The Stripe Customer Portal handles card changes and cancellation.
- Secrets: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`. Make the webhook idempotent (check `stripe_invoice_id`).

## App Store notes (risk)
- Apple requires In-App Purchase for **digital content or features consumed in the app** (Guideline 3.1.1).
  There are exceptions for goods and services used outside the app, and Apple has generally accepted B2B /
  enterprise-style services billed directly to organisations. Whether a gym-management SaaS unlocked inside a
  consumer app qualifies is **a judgment call by App Review**.
- To reduce risk:
  - The iOS app has **no purchase or checkout button** and no prices shown as a purchase. The Subscription screen
    is a status page with **billing/contact instructions** (Revolut page link, cash, email). Consider removing even
    the Revolut link if Review objects; the reference and email are enough.
  - Consumer features (feed, directory, events, training log, Ask BJJ) are never paywalled.
  - Billing is set up with the gym owner (B2B), ideally with an invoice, and later through a web Stripe page.
  - In App Review notes, explain that subscriptions are B2B contracts with gyms, billed outside the app, and that
    the iOS app doesn't sell anything to consumers.
- If Apple insists, the fallback is an auto-renewable IAP subscription for the gym-management tier, or moving
  management to a web dashboard.

## Student "My payments" (0011)
- A gym can set its own `gyms.revolut_url` (`https://revolut.me/<name>`) in My gym → Gym profile.
- Students see their plan, price, status (paid / due within 7 days / overdue), next due date and history in Profile → My payments.
  Paid-until = the month of the last `member_payments.period_month` + the plan period (1/3/12 months).
- Reference format: `<gym-slug>-<first 6 chars of user id>-<YYYY-MM>`.
- "I've paid" creates a `payment_claims` row (pending). Staff see it in Payments and **Confirm** it (`confirm_payment_claim` → inserts `member_payments`) or **Reject** it (`reject_payment_claim`).
- No money moves through BJJ Bul. It's the gym's own Revolut account or cash.

## BJJ Pass (0012)
In the app, student payments are branded **BJJ Pass** (Profile → BJJ Pass).
- **Plans** (`memberships.kind`):
  - `subscription`: monthly, quarterly or yearly. Status is paid / due / overdue, based on subscription payments only.
  - `one_off`: `class_credits` (1 = drop-in, 10 = class card) plus `validity_days`.
- **Passes:** recording a payment for a one-off plan, whether staff record it or confirm a claim, creates a `student_passes` row
  (credits, `expires_at = now() + validity_days`) through a trigger on `member_payments`.
- **Check-in:** a student without an active subscription uses 1 credit from the pass that expires first.
  Undoing the check-in gives the credit back.
  - No credits, self check-in: blocked with `no_credits`, but only if the gym sells one-off passes.
  - Otherwise, including when staff check someone in: allowed, with `attendance.unpaid = true`, and the app shows a warning.
- **Visitors:** on a gym page, "Buy a drop-in / class pass" lists the gym's one-off plans (`gym_pass_plans`), the gym's Revolut link,
  the reference and cash instructions. "I've paid" creates a claim and a **pending** student membership. When staff confirm,
  the membership is activated and the pass is created.
- **Student overview:** RPC `my_bjj_pass()` returns the subscription status plus credits left and the nearest expiry per gym.
  `my_student_memberships()` from 0011 remains for older builds.
