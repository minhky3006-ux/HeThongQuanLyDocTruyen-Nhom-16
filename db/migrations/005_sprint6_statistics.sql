-- Migration 005 · Sprint 6: thống kê doanh thu gói đọc (US 26), doanh thu theo truyện (US 27), thống kê nội dung (US 28).
-- Chạy MỘT lần trong Supabase SQL Editor, SAU migration 004. Chạy lại nhiều lần vẫn an toàn.
-- Quy ước: doanh thu = tổng orders.amount của đơn 'paid', tính theo NGÀY THANH TOÁN, giờ Việt Nam. Hệ thống chưa ghi nhận hoàn tiền,
-- nên số liệu là doanh thu gộp. Đơn "mua lẻ trùng" (xem đối soát) vẫn được tính cho đến khi admin xử lý ngoài hệ thống.

-- ============================================================
-- 1) Hàm dùng chung
-- ============================================================
create or replace function vn_bucket(ts timestamptz, grp text) returns date language sql immutable as $$
  select date_trunc(grp, ts at time zone 'Asia/Ho_Chi_Minh')::date
$$;
create or replace function vn_day(ts timestamptz) returns date language sql immutable as $$
  select (ts at time zone 'Asia/Ho_Chi_Minh')::date
$$;
-- Các mốc thời gian của khoảng [p_from, p_to] theo ngày hoặc tháng (kể cả mốc không có dữ liệu, để biểu đồ liền mạch)
create or replace function stat_periods(p_from date, p_to date, p_group text) returns setof date language sql immutable as $$
  select generate_series(date_trunc(p_group, p_from::timestamp), p_to::timestamp,
                         case p_group when 'day' then interval '1 day' else interval '1 month' end)::date
$$;
create or replace function stat_check_range(p_from date, p_to date, p_group text) returns void language plpgsql immutable as $$
begin
  if p_group not in ('day','month') then raise exception 'Chỉ nhóm theo ngày hoặc tháng'; end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Khoảng thời gian không hợp lệ'; end if;
  if p_to - p_from > 800 then raise exception 'Khoảng thời gian quá dài (tối đa 800 ngày)'; end if;
end $$;
revoke execute on function stat_check_range(date, date, text) from public, anon, authenticated;

create index if not exists orders_paid_idx on orders (paid_at) where status = 'paid';

-- ============================================================
-- 2) US 26: doanh thu gói đọc theo loại gói và theo ngày/tháng
-- ============================================================
create or replace function admin_revenue_plans(p_from date, p_to date, p_group text default 'day') returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare res jsonb;
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên xem được thống kê doanh thu'; end if;
  perform stat_check_range(p_from, p_to, p_group);
  with o as (
    select ord.id, ord.user_id, ord.plan_id, ord.amount, vn_bucket(ord.paid_at, p_group) as period
    from orders ord
    where ord.status = 'paid' and ord.kind = 'plan' and vn_day(ord.paid_at) between p_from and p_to),
  pp as (select period, plan_id, sum(amount)::bigint as rev from o group by 1, 2),
  series as (
    select pe.period,
           coalesce((select sum(o.amount) from o where o.period = pe.period), 0)::bigint as revenue,
           (select count(*) from o where o.period = pe.period) as orders,
           coalesce((select jsonb_object_agg(pp.plan_id::text, pp.rev) from pp where pp.period = pe.period), '{}'::jsonb) as by_plan
    from (select stat_periods(p_from, p_to, p_group) as period) pe)
  select jsonb_build_object(
    'range', jsonb_build_object('from', p_from, 'to', p_to, 'group', p_group),
    'totals', jsonb_build_object(
      'revenue', coalesce((select sum(amount) from o), 0),
      'orders',  (select count(*) from o),
      'buyers',  (select count(distinct user_id) from o),
      'avg_order', coalesce((select round(avg(amount)) from o), 0)),
    'series', coalesce((select jsonb_agg(jsonb_build_object('period', period, 'revenue', revenue, 'orders', orders, 'by_plan', by_plan) order by period) from series), '[]'::jsonb),
    'by_plan', coalesce((
      select jsonb_agg(jsonb_build_object('plan_id', pl.id, 'name', pl.name, 'is_active', pl.is_active, 'price', pl.price,
               'revenue', coalesce((select sum(o.amount) from o where o.plan_id = pl.id), 0),
               'orders',  (select count(*) from o where o.plan_id = pl.id),
               'buyers',  (select count(distinct o.user_id) from o where o.plan_id = pl.id)) order by pl.id)
      from plans pl), '[]'::jsonb)
  ) into res;
  return res;
end $$;
grant execute on function admin_revenue_plans(date, date, text) to authenticated;

-- ============================================================
-- 3) US 27: lượt mua và doanh thu theo từng truyện theo thời gian (p_story null = tất cả truyện)
-- ============================================================
create or replace function admin_revenue_stories(p_from date, p_to date, p_group text default 'day', p_story bigint default null) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare res jsonb;
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên xem được thống kê doanh thu'; end if;
  perform stat_check_range(p_from, p_to, p_group);
  with o as (
    select ord.id, ord.user_id, ord.story_id, ord.amount, vn_bucket(ord.paid_at, p_group) as period
    from orders ord
    where ord.status = 'paid' and ord.kind = 'story' and vn_day(ord.paid_at) between p_from and p_to
      and (p_story is null or ord.story_id = p_story)),
  series as (
    select pe.period,
           coalesce((select sum(o.amount) from o where o.period = pe.period), 0)::bigint as revenue,
           (select count(*) from o where o.period = pe.period) as purchases
    from (select stat_periods(p_from, p_to, p_group) as period) pe),
  top as (
    select s.id, s.title, s.price, s.access_policy, count(o.id) as purchases, sum(o.amount)::bigint as revenue, count(distinct o.user_id) as buyers
    from o join stories s on s.id = o.story_id
    group by s.id, s.title, s.price, s.access_policy
    order by sum(o.amount) desc, count(o.id) desc limit 50)
  select jsonb_build_object(
    'range', jsonb_build_object('from', p_from, 'to', p_to, 'group', p_group, 'story_id', p_story),
    'totals', jsonb_build_object(
      'revenue',   coalesce((select sum(amount) from o), 0),
      'purchases', (select count(*) from o),
      'buyers',    (select count(distinct user_id) from o),
      'stories',   (select count(distinct story_id) from o)),
    'series', coalesce((select jsonb_agg(jsonb_build_object('period', period, 'revenue', revenue, 'purchases', purchases) order by period) from series), '[]'::jsonb),
    'top', coalesce((select jsonb_agg(jsonb_build_object('story_id', id, 'title', title, 'price', price, 'access_policy', access_policy,
                       'purchases', purchases, 'revenue', revenue, 'buyers', buyers) order by revenue desc, purchases desc) from top), '[]'::jsonb)
  ) into res;
  return res;
end $$;
grant execute on function admin_revenue_stories(date, date, text, bigint) to authenticated;

-- ============================================================
-- 4) US 28: thống kê nội dung. Lượt xem lấy từ bảng theo ngày (US 40), lọc theo khoảng ngày; số người theo dõi là tổng hiện tại.
-- ============================================================
create or replace function admin_content_stats(p_from date, p_to date, p_limit int default 10) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare res jsonb; n int := least(greatest(coalesce(p_limit, 10), 1), 50);
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên xem được thống kê nội dung'; end if;
  perform stat_check_range(p_from, p_to, 'day');
  with sv as (
    select v.story_id, sum(v.views)::bigint as views from story_views_daily v join stories s on s.id = v.story_id and s.status = 'published'
    where v.day between p_from and p_to group by v.story_id),
  fl as (
    select f.story_id, count(*)::bigint as followers, count(*) filter (where vn_day(f.created_at) between p_from and p_to)::bigint as new_followers
    from follows f join stories s on s.id = f.story_id and s.status = 'published' group by f.story_id),
  cv as (
    select c.chapter_id, sum(c.views)::bigint as views from chapter_views_daily c
    join chapters ch on ch.id = c.chapter_id join stories s on s.id = ch.story_id and s.status = 'published'
    where c.day between p_from and p_to group by c.chapter_id),
  cd as (
    select cm.chapter_id, count(*)::bigint as comments from comments cm
    join chapters ch on ch.id = cm.chapter_id join stories s on s.id = ch.story_id and s.status = 'published'
    where cm.chapter_id is not null and not cm.is_hidden and vn_day(cm.created_at) between p_from and p_to group by cm.chapter_id),
  gv as (
    select g.id, g.name, count(distinct sg.story_id) as stories,
           coalesce(sum(sv.views), 0)::bigint as views, coalesce(sum(fl.followers), 0)::bigint as followers
    from genres g
    left join story_genres sg on sg.genre_id = g.id
    left join stories s on s.id = sg.story_id and s.status = 'published'
    left join sv on sv.story_id = s.id
    left join fl on fl.story_id = s.id
    group by g.id, g.name)
  select jsonb_build_object(
    'range', jsonb_build_object('from', p_from, 'to', p_to),
    'totals', jsonb_build_object(
      'published_stories', (select count(*) from stories where status = 'published'),
      'views',      coalesce((select sum(views) from sv), 0),
      'chapter_views', coalesce((select sum(views) from cv), 0),
      'new_followers', coalesce((select sum(new_followers) from fl), 0),
      'chapter_comments', coalesce((select sum(comments) from cd), 0)),
    'top_viewed', coalesce((select jsonb_agg(t order by (t->>'views')::bigint desc) from (
        select jsonb_build_object('story_id', s.id, 'title', s.title, 'views', sv.views, 'total_views', s.view_count) as t
        from sv join stories s on s.id = sv.story_id where s.status = 'published' order by sv.views desc limit n) x), '[]'::jsonb),
    'top_followed', coalesce((select jsonb_agg(t order by (t->>'followers')::bigint desc) from (
        select jsonb_build_object('story_id', s.id, 'title', s.title, 'followers', fl.followers, 'new_followers', fl.new_followers) as t
        from fl join stories s on s.id = fl.story_id where s.status = 'published' order by fl.followers desc, s.id limit n) x), '[]'::jsonb),
    'top_chapters_read', coalesce((select jsonb_agg(t order by (t->>'views')::bigint desc) from (
        select jsonb_build_object('chapter_id', ch.id, 'story_id', s.id, 'story_title', s.title, 'number', ch.number, 'title', ch.title, 'views', cv.views) as t
        from cv join chapters ch on ch.id = cv.chapter_id join stories s on s.id = ch.story_id order by cv.views desc limit n) x), '[]'::jsonb),
    'top_chapters_discussed', coalesce((select jsonb_agg(t order by (t->>'comments')::bigint desc) from (
        select jsonb_build_object('chapter_id', ch.id, 'story_id', s.id, 'story_title', s.title, 'number', ch.number, 'title', ch.title, 'comments', cd.comments) as t
        from cd join chapters ch on ch.id = cd.chapter_id join stories s on s.id = ch.story_id order by cd.comments desc limit n) x), '[]'::jsonb),
    'genres', coalesce((select jsonb_agg(jsonb_build_object('genre_id', id, 'name', name, 'stories', stories, 'views', views, 'followers', followers)
                                           order by views desc, followers desc, name) from gv), '[]'::jsonb)
  ) into res;
  return res;
end $$;
grant execute on function admin_content_stats(date, date, int) to authenticated;

-- ============================================================
-- 5) Lượt xem theo ngày tính theo giờ Việt Nam (trước đây theo UTC, lệch 7 giờ so với báo cáo)
-- ============================================================
create or replace function track_view(p_story bigint, p_chapter bigint default null) returns void language plpgsql security definer set search_path=public as $$
declare hdr json; who text; n int; today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  perform 1 from stories where id = p_story and status = 'published';
  if not found then return; end if;
  if p_chapter is not null then
    perform 1 from chapters where id = p_chapter and story_id = p_story;
    if not found or not can_read_chapter(p_chapter) then return; end if;
  end if;
  begin hdr := nullif(current_setting('request.headers', true), '')::json; exception when others then hdr := null; end;
  who := coalesce(auth.uid()::text,
                  nullif(trim(split_part(coalesce(hdr->>'cf-connecting-ip', hdr->>'x-forwarded-for', ''), ',', 1)), ''),
                  'unknown');
  insert into view_dedupe(story_id, chapter_id, viewer, bucket)
  values (p_story, coalesce(p_chapter, 0), who, date_trunc('hour', now())) on conflict do nothing;
  get diagnostics n = row_count;
  if n = 0 then return; end if;
  if random() < 0.01 then delete from view_dedupe where bucket < now() - interval '2 days'; end if;
  update stories set view_count = view_count + 1 where id = p_story;
  if p_chapter is not null then
    update chapters set view_count = view_count + 1 where id = p_chapter and story_id = p_story;
    insert into chapter_views_daily(chapter_id, day, views) values (p_chapter, today, 1)
    on conflict (chapter_id, day) do update set views = chapter_views_daily.views + 1;
  end if;
  insert into story_views_daily(story_id, day, views) values (p_story, today, 1)
  on conflict (story_id, day) do update set views = story_views_daily.views + 1;
end $$;
