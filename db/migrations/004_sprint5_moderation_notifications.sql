-- Migration 004 · Sprint 5: thảo luận theo chương (US 37), báo cáo bình luận (US 38), xử lý báo cáo + hạn chế tài khoản (US 23),
-- thông báo chương mới (US 39), đối soát giao dịch (US 24), thống kê thành viên & gói (US 25).
-- Chạy MỘT lần trong Supabase SQL Editor, SAU migration 003. Chạy lại nhiều lần vẫn an toàn.

-- ============================================================
-- 1) Hạn chế tài khoản + nhật ký kiểm duyệt (US 23)
--    Hạn chế = không được bình luận / báo cáo tới một ngày; vẫn đọc bình thường. Khóa tài khoản (is_locked) vẫn là mức nặng hơn.
--    Lưu ở bảng riêng (không để trong profiles vì profiles ai cũng đọc được).
-- ============================================================
create table if not exists user_restrictions (
  user_id uuid primary key references profiles(id) on delete cascade,
  until_at timestamptz not null,
  reason text,
  set_by uuid references profiles(id),
  created_at timestamptz not null default now()
);
alter table user_restrictions enable row level security;
drop policy if exists ur_read on user_restrictions;
create policy ur_read on user_restrictions for select using (user_id = auth.uid() or is_admin());
revoke insert, update, delete on user_restrictions from anon, authenticated;

create table if not exists moderation_log (
  id bigint generated always as identity primary key,
  admin_id uuid references profiles(id) on delete set null,
  target_user uuid references profiles(id) on delete set null,
  comment_id bigint,                                   -- không khóa ngoại: bình luận có thể bị xóa sau đó
  action text not null check (action in ('hide_comment','dismiss_reports','restrict','lift_restriction','lock','unlock')),
  reason text,
  until_at timestamptz,
  created_at timestamptz not null default now()
);
alter table moderation_log enable row level security;
drop policy if exists ml_read on moderation_log;
create policy ml_read on moderation_log for select using (is_admin());
revoke insert, update, delete on moderation_log from anon, authenticated;

create or replace function is_restricted() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from user_restrictions where user_id = auth.uid() and until_at > now())
$$;
grant execute on function is_restricted() to anon, authenticated;

-- ============================================================
-- 2) Thảo luận theo chương (US 37): bình luận có chapter_id. Chỉ người ĐỌC ĐƯỢC chương mới xem/viết được thảo luận của chương đó
--    (tránh lộ nội dung chương trả phí qua bình luận). Bình luận cấp truyện (chapter_id null) giữ nguyên.
-- ============================================================
create index if not exists comments_chapter_idx on comments (chapter_id, created_at desc) where chapter_id is not null;
drop policy if exists comments_read on comments;
create policy comments_read on comments for select using (
  (not is_hidden or user_id = auth.uid() or is_admin())
  and (chapter_id is null or can_read_chapter(chapter_id)));
drop policy if exists comments_insert on comments;
create policy comments_insert on comments for insert with check (
  user_id = auth.uid() and can_write() and not is_restricted()
  and (chapter_id is null or (
        can_read_chapter(chapter_id)
        and exists(select 1 from chapters c where c.id = chapter_id and c.story_id = comments.story_id))));

-- ============================================================
-- 3) Báo cáo bình luận vi phạm (US 38)
-- ============================================================
do $$ begin create type report_reason as enum ('spam','abuse','spoiler','other'); exception when duplicate_object then null; end $$;
do $$ begin create type report_status as enum ('open','resolved','dismissed'); exception when duplicate_object then null; end $$;

create table if not exists comment_reports (
  id bigint generated always as identity primary key,
  comment_id bigint not null references comments(id) on delete cascade,
  reporter_id uuid not null references profiles(id) on delete cascade,
  reason report_reason not null,
  note text check (note is null or length(note) <= 500),
  status report_status not null default 'open',
  created_at timestamptz not null default now(),
  handled_by uuid references profiles(id) on delete set null,
  handled_at timestamptz,
  handler_note text,
  unique (comment_id, reporter_id)                     -- mỗi người báo cáo một bình luận tối đa 1 lần
);
create index if not exists comment_reports_status_idx on comment_reports (status, created_at desc);
alter table comment_reports enable row level security;
drop policy if exists cr_read on comment_reports;   drop policy if exists cr_insert on comment_reports;
create policy cr_read on comment_reports for select using (reporter_id = auth.uid() or is_admin());
-- Chỉ báo cáo được bình luận mình THẤY (RLS comments áp dụng trong truy vấn con) và không phải của chính mình
create policy cr_insert on comment_reports for insert with check (
  reporter_id = auth.uid() and can_write() and not is_restricted()
  and exists(select 1 from comments c where c.id = comment_id and c.user_id <> auth.uid()));
revoke update, delete on comment_reports from anon, authenticated;

create or replace function trg_report_limit() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if (select count(*) from comment_reports where reporter_id = new.reporter_id and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'Bạn báo cáo quá nhiều trong 1 giờ, vui lòng thử lại sau.';
  end if;
  return new;
end $$;
drop trigger if exists comment_reports_limit on comment_reports;
create trigger comment_reports_limit before insert on comment_reports for each row execute function trg_report_limit();

-- ============================================================
-- 4) Xử lý báo cáo + hạn chế/khóa tài khoản (US 23). Mọi hành động của admin được ghi vào moderation_log.
-- ============================================================
-- Hàng đợi báo cáo, gộp theo bình luận. p_open=true: đang chờ; false: đã xử lý
create or replace function admin_report_queue(p_open boolean default true, p_limit int default 20, p_offset int default 0)
returns table(comment_id bigint, body text, is_hidden boolean, story_id bigint, story_title text, chapter_number int,
              author_id uuid, author_name text, author_locked boolean, author_restricted_until timestamptz,
              report_count bigint, reasons text[], notes text[], last_reported_at timestamptz)
language plpgsql stable security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên xem được hàng đợi báo cáo'; end if;
  return query
  select c.id, c.body, c.is_hidden, c.story_id, s.title, ch.number, c.user_id, pr.display_name, pr.is_locked,
         (select ur.until_at from user_restrictions ur where ur.user_id = c.user_id and ur.until_at > now()),
         count(r.id), array_agg(distinct r.reason::text), array_remove(array_agg(distinct r.note), null), max(r.created_at)
  from comment_reports r
  join comments c on c.id = r.comment_id
  join stories s on s.id = c.story_id
  left join chapters ch on ch.id = c.chapter_id
  join profiles pr on pr.id = c.user_id
  where (r.status = 'open') = p_open
  group by c.id, s.title, ch.number, pr.display_name, pr.is_locked
  order by max(r.created_at) desc
  limit p_limit offset p_offset;
end $$;
grant execute on function admin_report_queue(boolean, int, int) to authenticated;

-- p_action: 'hide' (ẩn bình luận, báo cáo -> resolved) | 'dismiss' (bỏ qua, báo cáo -> dismissed)
create or replace function admin_handle_reports(p_comment bigint, p_action text, p_note text default null)
returns void language plpgsql security definer set search_path=public as $$
declare n int; au uuid;
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên được xử lý báo cáo'; end if;
  if p_action not in ('hide','dismiss') then raise exception 'Hành động không hợp lệ'; end if;
  select user_id into au from comments where id = p_comment;
  if not found then raise exception 'Không tìm thấy bình luận'; end if;
  update comment_reports
     set status = (case p_action when 'hide' then 'resolved' else 'dismissed' end)::report_status,
         handled_by = auth.uid(), handled_at = now(), handler_note = p_note
   where comment_id = p_comment and status = 'open';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Bình luận này không còn báo cáo nào đang chờ'; end if;
  if p_action = 'hide' then update comments set is_hidden = true where id = p_comment; end if;
  insert into moderation_log(admin_id, target_user, comment_id, action, reason)
  values (auth.uid(), au, p_comment, case p_action when 'hide' then 'hide_comment' else 'dismiss_reports' end, p_note);
end $$;
grant execute on function admin_handle_reports(bigint, text, text) to authenticated;

-- Hạn chế bình luận p_days ngày (1–365). p_days = 0: gỡ hạn chế.
create or replace function admin_restrict_user(p_user uuid, p_days int, p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare r user_role;
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên được hạn chế tài khoản'; end if;
  if p_days is null or p_days < 0 or p_days > 365 then raise exception 'Số ngày hạn chế phải từ 0 đến 365'; end if;
  select role into r from profiles where id = p_user;
  if not found then raise exception 'Không tìm thấy người dùng'; end if;
  if r = 'admin' then raise exception 'Không thể hạn chế quản trị viên'; end if;
  if p_days = 0 then
    delete from user_restrictions where user_id = p_user;
    insert into moderation_log(admin_id, target_user, action, reason) values (auth.uid(), p_user, 'lift_restriction', p_reason);
  else
    insert into user_restrictions(user_id, until_at, reason, set_by) values (p_user, now() + make_interval(days => p_days), p_reason, auth.uid())
    on conflict (user_id) do update set until_at = excluded.until_at, reason = excluded.reason, set_by = excluded.set_by, created_at = now();
    insert into moderation_log(admin_id, target_user, action, reason, until_at)
    values (auth.uid(), p_user, 'restrict', p_reason, now() + make_interval(days => p_days));
  end if;
end $$;
grant execute on function admin_restrict_user(uuid, int, text) to authenticated;

-- Khóa/mở khóa (tạm ngừng tài khoản): giữ cách gọi cũ admin_set_locked(uid, locked), thêm lý do và nhật ký, không khóa được admin
drop function if exists admin_set_locked(uuid, boolean);
create or replace function admin_set_locked(uid uuid, locked boolean, p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  if (select role from profiles where id = uid) = 'admin' then raise exception 'Không thể khóa quản trị viên'; end if;
  update profiles set is_locked = locked where id = uid;
  insert into moderation_log(admin_id, target_user, action, reason) values (auth.uid(), uid, case when locked then 'lock' else 'unlock' end, p_reason);
end $$;
grant execute on function admin_set_locked(uuid, boolean, text) to authenticated;

-- ============================================================
-- 5) Thông báo chương mới (US 39). Sinh khi chương được PHÁT HÀNH (đăng ngay hoặc tới giờ hẹn), mỗi người theo dõi nhận tối đa 1 lần/chương.
-- ============================================================
alter table chapters add column if not exists notified_at timestamptz;
-- Chương có sẵn không báo lại
update chapters set notified_at = now() where notified_at is null and (publish_at is null or publish_at <= now());

create table if not exists notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  kind text not null default 'new_chapter',
  story_id bigint references stories(id) on delete cascade,
  chapter_id bigint references chapters(id) on delete cascade,
  story_title text not null,
  chapter_number int,
  chapter_title text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique (user_id, kind, chapter_id)
);
create index if not exists notifications_user_idx on notifications (user_id, created_at desc);
create index if not exists notifications_unread_idx on notifications (user_id) where read_at is null;
alter table notifications enable row level security;
drop policy if exists notif_own on notifications;  drop policy if exists notif_update on notifications;  drop policy if exists notif_delete on notifications;
create policy notif_own    on notifications for select using (user_id = auth.uid());
create policy notif_update on notifications for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notif_delete on notifications for delete using (user_id = auth.uid());
revoke insert, update on notifications from anon, authenticated;
grant update (read_at) on notifications to authenticated;

create or replace function notify_chapter(p_chapter bigint) returns void language plpgsql security definer set search_path=public as $$
declare c chapters%rowtype; s stories%rowtype;
begin
  select * into c from chapters where id = p_chapter for update skip locked;
  if not found or c.notified_at is not null then return; end if;
  if not (c.publish_at is null or c.publish_at <= now()) then return; end if;          -- chưa tới giờ
  select * into s from stories where id = c.story_id;
  if s.status = 'published' then
    insert into notifications(user_id, story_id, chapter_id, story_title, chapter_number, chapter_title)
    select f.user_id, s.id, c.id, s.title, c.number, c.title from follows f
    where f.story_id = s.id and f.user_id <> s.author_id
    on conflict (user_id, kind, chapter_id) do nothing;
  end if;                                                                                  -- truyện chưa duyệt: không báo nhưng coi như đã xử lý
  update chapters set notified_at = now() where id = c.id;
end $$;
revoke execute on function notify_chapter(bigint) from public, anon, authenticated;

create or replace function trg_chapter_notify() returns trigger language plpgsql security definer set search_path=public as $$
begin
  perform notify_chapter(new.id);
  return null;
end $$;
drop trigger if exists chapters_notify on chapters;
create trigger chapters_notify after insert or update of publish_at on chapters for each row execute function trg_chapter_notify();

-- Chương hẹn giờ tới hạn: cập nhật số chương (như Sprint 4) VÀ gửi thông báo
create or replace function release_due_chapters() returns int language plpgsql security definer set search_path=public as $$
declare n int; r record;
begin
  with x as (
    select s.id, (select count(*) from chapters c where c.story_id = s.id and (c.publish_at is null or c.publish_at <= now())) as cnt
    from stories s where exists(select 1 from chapters c where c.story_id = s.id and c.publish_at is not null))
  update stories s set chapter_count = x.cnt, updated_at = case when x.cnt > s.chapter_count then now() else s.updated_at end
  from x where s.id = x.id and s.chapter_count <> x.cnt;
  get diagnostics n = row_count;
  for r in select id from chapters where publish_at is not null and publish_at <= now() and notified_at is null order by publish_at limit 200 loop
    perform notify_chapter(r.id);
  end loop;
  return n;
end $$;
grant execute on function release_due_chapters() to anon, authenticated;

-- ============================================================
-- 6) Theo dõi & đối soát giao dịch (US 24)
--    Bất thường: paid_no_entitlement (đã thu tiền nhưng chưa có quyền), pending_stale (chờ > 30 phút), amount_mismatch (sai số tiền),
--    duplicate_purchase (mua lẻ trùng, nên hoàn tiền ngoài hệ thống). Mọi thao tác của admin ghi vào order_audit.
-- ============================================================
create table if not exists order_audit (
  id bigint generated always as identity primary key,
  order_id uuid not null references orders(id) on delete cascade,
  admin_id uuid references profiles(id) on delete set null,
  action text not null check (action in ('regrant','cancel','manual_confirm','ignore')),
  note text,
  created_at timestamptz not null default now()
);
create index if not exists order_audit_order_idx on order_audit (order_id, created_at desc);
alter table order_audit enable row level security;
drop policy if exists oa_read on order_audit;
create policy oa_read on order_audit for select using (is_admin());
revoke insert, update, delete on order_audit from anon, authenticated;

create or replace function order_issue(p_order uuid) returns text language sql stable security definer set search_path=public as $$
  select case
    when exists(select 1 from order_audit a where a.order_id = o.id and a.action = 'ignore') then null
    -- Mua lẻ trùng: đơn paid thứ hai trở đi của cùng người + truyện (thứ tự theo thời điểm thanh toán)
    when o.status = 'paid' and o.kind = 'story' and exists(
           select 1 from orders o2 where o2.user_id = o.user_id and o2.story_id = o.story_id and o2.status = 'paid'
             and o2.id <> o.id and (o2.paid_at, o2.id) < (o.paid_at, o.id)) then 'duplicate_purchase'
    -- Đã thu tiền nhưng chưa có quyền (gói: chưa có dòng subscriptions của đơn; mua lẻ: người dùng chưa sở hữu truyện)
    when o.status = 'paid' and (
           (o.kind = 'plan'  and not exists(select 1 from subscriptions sb where sb.order_id = o.id))
        or (o.kind = 'story' and not exists(select 1 from story_purchases sp where sp.user_id = o.user_id and sp.story_id = o.story_id))
         ) then 'paid_no_entitlement'
    when o.status = 'failed' and o.fail_reason like 'Sai số tiền%' then 'amount_mismatch'
    when o.status = 'pending' and o.created_at < now() - interval '30 minutes' then 'pending_stale'
  end
  from orders o where o.id = p_order
$$;
revoke execute on function order_issue(uuid) from public, anon, authenticated;

create or replace function admin_orders_list(p_status text default null, p_only_issues boolean default false, p_limit int default 20, p_offset int default 0)
returns table(id uuid, created_at timestamptz, paid_at timestamptz, status order_status, kind order_kind, amount int, provider text,
              provider_txn text, fail_reason text, user_id uuid, user_name text, item_name text, issue text, last_audit text)
language plpgsql stable security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên xem được giao dịch'; end if;
  return query
  select * from (
    select o.id, o.created_at, o.paid_at, o.status, o.kind, o.amount, o.provider, o.provider_txn, o.fail_reason, o.user_id,
           pr.display_name, coalesce(pl.name, 'Truyện: ' || st.title), order_issue(o.id),
           (select a.action || coalesce(': ' || a.note, '') from order_audit a where a.order_id = o.id order by a.created_at desc, a.id desc limit 1)
    from orders o
    join profiles pr on pr.id = o.user_id
    left join plans pl on pl.id = o.plan_id
    left join stories st on st.id = o.story_id
    where (p_status is null or o.status::text = p_status)
  ) q(id, created_at, paid_at, status, kind, amount, provider, provider_txn, fail_reason, user_id, user_name, item_name, issue, last_audit)
  where (not p_only_issues or q.issue is not null)
  order by q.created_at desc
  limit p_limit offset p_offset;
end $$;
grant execute on function admin_orders_list(text, boolean, int, int) to authenticated;

create or replace function admin_order_summary() returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên xem được giao dịch'; end if;
  return jsonb_build_object(
    'by_status', coalesce((select jsonb_object_agg(status, n) from (select status::text, count(*) n from orders group by status) t), '{}'::jsonb),
    'issues',    coalesce((select jsonb_object_agg(i, n) from (select order_issue(id) i, count(*) n from orders group by 1) t where i is not null), '{}'::jsonb));
end $$;
grant execute on function admin_order_summary() to authenticated;

-- Xử lý một đơn bất thường. Luôn ghi order_audit.
create or replace function admin_fix_order(p_order uuid, p_action text, p_note text default null)
returns text language plpgsql security definer set search_path=public as $$
declare o orders%rowtype; iss text;
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên được xử lý giao dịch'; end if;
  if p_action not in ('regrant','cancel','manual_confirm','ignore') then raise exception 'Hành động không hợp lệ'; end if;
  if p_action in ('manual_confirm','ignore') and length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'Cần ghi chú lý do (ít nhất 3 ký tự) cho thao tác này';
  end if;
  select * into o from orders where id = p_order for update;
  if not found then raise exception 'Không tìm thấy đơn hàng'; end if;
  iss := order_issue(p_order);
  if p_action = 'regrant' then
    if o.status <> 'paid' or iss is distinct from 'paid_no_entitlement' then raise exception 'Đơn này không ở trạng thái "đã thu tiền nhưng chưa có quyền"'; end if;
    perform grant_entitlement(p_order);
  elsif p_action = 'cancel' then
    if o.status <> 'pending' then raise exception 'Chỉ hủy được đơn đang chờ thanh toán'; end if;
    update orders set status = 'cancelled', fail_reason = 'Quản trị viên hủy' || coalesce(': ' || p_note, '') where id = p_order;
  elsif p_action = 'manual_confirm' then
    if o.status not in ('pending','failed') then raise exception 'Chỉ xác nhận thủ công đơn đang chờ hoặc thất bại'; end if;
    perform fulfill_order(p_order, 'MANUAL-' || p_order, o.amount, jsonb_build_object('manual', true, 'by', auth.uid(), 'note', p_note));
  end if;
  insert into order_audit(order_id, admin_id, action, note) values (p_order, auth.uid(), p_action, p_note);
  return (select status::text from orders where id = p_order);
end $$;
grant execute on function admin_fix_order(uuid, text, text) to authenticated;

-- ============================================================
-- 7) Thống kê thành viên & gói (US 25)
--    "Đăng ký mới" = lần mua ĐẦU TIÊN của một người với một loại gói; "gia hạn" = các lần mua sau đó của cùng người, cùng gói.
--    Ngày tính theo giờ Việt Nam.
-- ============================================================
create or replace function admin_member_stats(p_from date, p_to date, p_group text default 'day') returns jsonb language plpgsql stable security definer set search_path=public as $$
declare tz text := 'Asia/Ho_Chi_Minh'; res jsonb;
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên xem được thống kê'; end if;
  if p_group not in ('day','month') then raise exception 'Chỉ nhóm theo ngày hoặc tháng'; end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Khoảng thời gian không hợp lệ'; end if;
  if p_to - p_from > 800 then raise exception 'Khoảng thời gian quá dài (tối đa 800 ngày)'; end if;
  with sub as (
    select s.id, s.user_id, s.plan_id, s.starts_at, s.expires_at,
           (coalesce(o.paid_at, s.starts_at) at time zone tz) as bought_local,
           row_number() over (partition by s.user_id, s.plan_id order by coalesce(o.paid_at, s.starts_at), s.id) as rn
    from subscriptions s left join orders o on o.id = s.order_id),
  periods as (
    select generate_series(date_trunc(p_group, p_from::timestamp), p_to::timestamp,
                           case p_group when 'day' then interval '1 day' else interval '1 month' end)::date as period),
  series as (
    select pe.period,
      (select count(*) from profiles p where (p.created_at at time zone tz)::date between p_from and p_to
         and date_trunc(p_group, p.created_at at time zone tz)::date = pe.period) as new_members,
      (select count(*) from sub where sub.rn = 1 and sub.bought_local::date between p_from and p_to
         and date_trunc(p_group, sub.bought_local)::date = pe.period) as new_subs,
      (select count(*) from sub where sub.rn > 1 and sub.bought_local::date between p_from and p_to
         and date_trunc(p_group, sub.bought_local)::date = pe.period) as renewals
    from periods pe)
  select jsonb_build_object(
    'range', jsonb_build_object('from', p_from, 'to', p_to, 'group', p_group),
    'totals', jsonb_build_object(
      'members',    (select count(*) from profiles where role = 'member'),
      'authors',    (select count(*) from profiles where role = 'author'),
      'admins',     (select count(*) from profiles where role = 'admin'),
      'locked',     (select count(*) from profiles where is_locked),
      'restricted', (select count(*) from user_restrictions where until_at > now()),
      'active_subscribers', (select count(distinct user_id) from subscriptions where now() >= starts_at and now() < expires_at),
      'new_members', (select coalesce(sum(new_members), 0) from series),
      'new_subs',    (select coalesce(sum(new_subs), 0) from series),
      'renewals',    (select coalesce(sum(renewals), 0) from series)),
    'series', coalesce((select jsonb_agg(jsonb_build_object('period', period, 'new_members', new_members, 'new_subs', new_subs, 'renewals', renewals) order by period) from series), '[]'::jsonb),
    'by_plan', coalesce((
      select jsonb_agg(jsonb_build_object('plan_id', pl.id, 'name', pl.name, 'is_active', pl.is_active,
               'active_users', (select count(distinct sb.user_id) from subscriptions sb where sb.plan_id = pl.id and now() >= sb.starts_at and now() < sb.expires_at),
               'new_subs', (select count(*) from sub where sub.plan_id = pl.id and sub.rn = 1 and sub.bought_local::date between p_from and p_to),
               'renewals', (select count(*) from sub where sub.plan_id = pl.id and sub.rn > 1 and sub.bought_local::date between p_from and p_to))
             order by pl.id) from plans pl), '[]'::jsonb)
  ) into res;
  return res;
end $$;
grant execute on function admin_member_stats(date, date, text) to authenticated;
