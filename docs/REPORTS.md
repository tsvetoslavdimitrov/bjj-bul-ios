# Gym reports (0014)

My gym → Reports (owners/coaches). SQL: `supabase/migrations/0014_reports.sql`. All functions are `security definer`
and check `is_gym_staff(gym)`. Dates are Europe/Sofia calendar days, and both ends of the range are included.

| RPC | Returns |
|---|---|
| `gym_report_visits(gym, from, to, bucket)` | jsonb `{buckets:[{bucket_start, checkins, unique_members, guests, unpaid}], totals:{…}}`; bucket = day/week/month |
| `gym_report_classes(gym, from, to)` | jsonb `{top_classes:[…10], heatmap:[{weekday 1–7, hour, visits}]}`; hour = class start, or check-in time for open mat |
| `gym_report_revenue(gym, from, to, bucket)` | jsonb `{rows:[{bucket_start, plan_kind, method, amount, payments}], total, payments, confirmed_claims}` |
| `gym_report_members(gym)` | jsonb `{active, new_this_month, churned, overdue, mrr, overdue_list:[…]}` |
| `gym_report_visits_list` / `gym_report_payments_list` | rows used for the CSV exports |

Definitions:
- **Visits** = member `attendance` + `guest_attendance`.
- **Revenue** = `member_payments` (by `paid_at`, Sofia) + paid guest drop-ins. plan_kind: `subscription`, `one_off` (class card), or `drop_in` (one-off plan with 1 credit, or a guest).
- **Churned** = an active student with no visit in the last 30 days (or never, if they joined more than 30 days ago).
- **Overdue** = an active student on a subscription plan with no current paid period, more than 7 days after the due date.
- **MRR** = sum of active subscribers' plan price ÷ months in the plan period (1/3/12).
- **CSV** files are UTF-8 with a BOM so Excel shows Cyrillic correctly. They contain names, so share them only with staff.
