# Moderation runbook (Apple Guideline 1.2)

Goal: act on every report **within 24 hours**. Contact for users: admin@bjjbul.com (check this inbox daily too).

## 1. Find open reports
Supabase Dashboard → **SQL Editor**:
```sql
select r.id, r.created_at, r.reason, r.post_id, r.comment_id, r.reported_user_id,
       p.body as post_body, c.body as comment_body, pr.display_name as reported_name
from reports r
left join posts p on p.id = r.post_id
left join comments c on c.id = r.comment_id
left join profiles pr on pr.id = coalesce(r.reported_user_id, p.author_id, c.author_id)
where r.status = 'needs_review'
order by r.created_at;
```
(Or use **Table Editor → reports** and filter `status = needs_review`.) Photos for a post are at Storage → `post-media` → `<author-id>/<post-id>/`.

## 2. Decide and act
- **Violates the Terms** (harassment, hate, sexual content, spam…):
  - Remove the post: `delete from posts where id = '<post_id>';` (the photo files are left behind; delete them under Storage → post-media → `<author-id>/<post-id>/`).
  - Remove the comment: `delete from comments where id = '<comment_id>';`
  - For serious or repeat abuse, ban the user: Dashboard → **Authentication → Users** → select the user → **Ban user**, or delete them. Deleting a user cascades to their content.
- **Doesn't violate:** no action.

## 3. Close the report
```sql
update reports set status = 'verified' where id = '<report_id>';   -- action taken
update reports set status = 'rejected' where id = '<report_id>';   -- no violation
```

## 4. Routine
- Check open reports at least once a day (a shared calendar reminder helps), and check admin@bjjbul.com.
- Count of open reports: `select count(*) from reports where status = 'needs_review';`
- Keep notes on banned users and repeat offenders.
