# Marketplace (Shop)

Migration: `supabase/migrations/0015_marketplace.sql` (safe to re-run). App entry points: Explore → toolbar **Shop**, and Profile → **Shop / My orders / My partner store**. No extra tab.

## Model
| Table | Purpose |
|---|---|
| `partners` | Store/brand. `status` pending/approved/suspended, `commission_pct` (default 10), `revolut_url`, `seeded` (added by BJJ Bul before the brand agreed). |
| `partner_members` | Users who manage a partner (owner/staff). |
| `products` | Title bg/en, category, `price_eur`, `compare_at_price`, `image_urls` (bucket `product-media`, folder `<partner_id>/`), `sizes`/`variants` jsonb, `stock`, `external_url`, `fulfillment` = `affiliate_link` \| `order_request`. |
| `affiliate_clicks` | One row per "Buy on website" tap (`track_affiliate_click` RPC returns `…?ref=bjjbul-<code>&utm_source=bjjbul&utm_medium=app&utm_campaign=marketplace`). |
| `marketplace_orders` | Order requests. Prices are taken from `products` server-side; `commission_pct`/`commission_amount` are snapshotted. Status requested → confirmed → paid → shipped → completed (or cancelled). |
| `commission_payouts` | Commission paid by a partner to BJJ Bul. |
| `partner_commission_ledger` (view, admin only) | Per partner per month: orders, sales, commission, paid, owed. Partners read theirs via `partner_ledger(partner)`. |

RLS: products of approved **and pending** partners are public (pending shows an "Unconfirmed partner" badge); partner members CRUD their products; buyers see their own orders, partner members see their partner's orders. Order writes go only through `create_marketplace_order` and `set_marketplace_order_status` (buyers may cancel only while `requested`; stock decrements when the partner confirms).

## Admin (SQL editor)
```sql
-- pending applications
select id, name, website, contact_email, owner_user_id, created_at from partners where status = 'pending' and not seeded;
-- approve (optionally attach an owner account or a custom commission)
select admin_approve_partner('<partner id>');
select admin_approve_partner('<seeded partner id>', '<owner user id>', 8);
-- suspend (hides products)
select admin_set_partner_status('<partner id>', 'suspended', 'reason');
-- monthly ledger
select * from partner_commission_ledger order by month desc;
-- record a payout from a partner
select admin_record_commission_payout('<partner id>', '2026-10-01', 61.50, 'revolut', 'Oct 2026');
-- affiliate clicks per partner this month
select partner_id, count(*) from affiliate_clicks where created_at >= date_trunc('month', now()) group by 1;
```

## Seeded brands (unconfirmed)
Art of Flow (artofflow.eu), Mata Leão (mataleao.shop) and RUSH / RushguardBJJ (rushguardbjj.com) are seeded as `pending`, `seeded = true`, with affiliate-link products checked on their official shops on 2026-10-11 (see `data/marketplace_seed.csv`). Image URLs point to the shops' own product images (not copied). **Before launch:** contact each brand, get consent (or remove them: `update partners set status = 'suspended' where seeded`), agree on commission/ref tracking, and re-check prices – they change. Affiliate commission for link-outs is tracked only by our `ref` parameter, so it needs a written agreement with the brand.

## Payments & delivery
- **Affiliate link:** the purchase happens on the partner's site.
- **Order request:** buyer submits name, phone, Econt/Speedy office or address, payment method (Revolut / cash on delivery / card link from the partner). The partner confirms, collects payment (their Revolut link is shown) and ships. BJJ Bul doesn't handle money for orders; commission is invoiced monthly and recorded with `admin_record_commission_payout`.

## App Store notes
Selling **physical goods** (gis, rashguards, supplements) with payment outside Apple IAP is allowed (App Review Guideline 3.1.3(e) / 3.1.5: goods and services consumed outside the app). Don't sell digital content (courses, instructionals) through this flow – that would need IAP. Keep the "sold by partner" disclaimer visible, and ensure product listings follow guideline 1.4/5 (no prohibited supplements/claims).

## Privacy
Order details (name, phone, delivery) go to that partner only, as an independent controller for fulfilment; covered in Privacy Policy v1.2 §4. Affiliate clicks store product, time, random code and user id (nullable). Keep orders for accounting retention; partners must not use buyer data for marketing without consent.

## Future
Stripe Connect for in-app card payments with automatic commission split; Econt/Speedy API for office pickers and labels; variants with per-size stock.
