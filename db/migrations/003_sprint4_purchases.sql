-- Migration 003 · Sprint 4: giá từng truyện (US 22), hẹn giờ phát hành chương + trạng thái truyện (US 20),
-- đăng ký gói / mua lẻ cấp quyền (US 33, 34), gộp quyền (US 35), lịch sử mua (US 36), ghi nhận lượt đọc (US 40).
-- Chạy MỘT lần trong Supabase SQL Editor, SAU migration 002. Chạy lại nhiều lần vẫn an toàn.

-- ============================================================
-- 1) US 22: mức phí từng truyện. Giá đơn hàng được CHỐT vào orders.amount lúc tạo đơn, nên đổi giá sau đó không ảnh hưởng đơn cũ.
-- ============================================================
alter table stories add column if not exists price int check (price is null or price > 0);   -- VND; null = chưa bán lẻ

create table if not exists story_price_log (
  id bigint generated always as identity primary key,
  story_id bigint not null references stories(id) on delete cascade,
  old_price int, new_price int,
  changed_by uuid references profiles(id),
  changed_at timestamptz not null default now()
);
alter table story_price_log enable row level security;
drop policy if exists price_log_read on story_price_log;
create policy price_log_read on story_price_log for select using (is_admin());
revoke insert, update, delete on story_price_log from anon, authenticated;

-- p_price null = ngừng bán lẻ. Cột price không nằm trong quyền UPDATE của client nên phải đi qua hàm này.
create or replace function admin_set_story_price(p_story bigint, p_price int) returns void language plpgsql security definer set search_path=public as $$
declare old int;
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên được đặt giá truyện'; end if;
  if p_price is not null and p_price <= 0 then raise exception 'violates check constraint: giá phải lớn hơn 0'; end if;
  select price into old from stories where id = p_story for update;
  if not found then raise exception 'Không tìm thấy truyện'; end if;
  if old is distinct from p_price then
    update stories set price = p_price where id = p_story;
    insert into story_price_log(story_id, old_price, new_price, changed_by) values (p_story, old, p_price, auth.uid());
  end if;
end $$;
grant execute on function admin_set_story_price(bigint, int) to authenticated;

-- ============================================================
-- 2) US 20: trạng thái truyện (đang ra / hoàn thành / tạm ngưng) và hẹn giờ phát hành chương
--    Lưu ý: stories.status (nháp/chờ duyệt/đã đăng/gỡ) vẫn là trạng thái kiểm duyệt; progress là tiến độ ra chương.
-- ============================================================
do $$ begin
  create type story_progress as enum ('ongoing','completed','paused');
exception when duplicate_object then null; end $$;
alter table stories add column if not exists progress story_progress not null default 'ongoing';
grant update (progress) on stories to authenticated;

alter table chapters add column if not exists publish_at timestamptz;      -- null = phát hành ngay; tương lai = ẩn với độc giả tới giờ đó
create index if not exists chapters_publish_idx on chapters (story_id, publish_at);

-- Độc giả chỉ thấy chương đã tới giờ; tác giả (chủ truyện) và admin thấy tất cả
drop policy if exists chapters_read on chapters;
create policy chapters_read on chapters for select using (
  is_admin() or owns_story(story_id)
  or (exists(select 1 from stories s where s.id = story_id and s.status = 'published')
      and (publish_at is null or publish_at <= now())));

-- Quyền đọc: thêm điều kiện chương đã phát hành (tác giả/admin không bị ảnh hưởng)
create or replace function can_read_chapter(p_chapter bigint) returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from chapters c join stories s on s.id = c.story_id
    where c.id = p_chapter and (
      is_admin()
      or s.author_id = auth.uid()
      or (s.status = 'published' and (c.publish_at is null or c.publish_at <= now()) and (
            s.access_policy = 'free'
         or (s.access_policy = 'mixed' and c.is_free_preview)
         or has_story_access(s.id)
      ))
    ))
$$;

-- chapter_count / updated_at chỉ tính chương ĐÃ phát hành
create or replace function trg_chapter_count() returns trigger language plpgsql security definer set search_path=public as $$
declare sid bigint := coalesce(new.story_id, old.story_id); due boolean := false;
begin
  if tg_op <> 'DELETE' then due := (new.publish_at is null or new.publish_at <= now()); end if;
  update stories set
    chapter_count = (select count(*) from chapters c where c.story_id = sid and (c.publish_at is null or c.publish_at <= now())),
    updated_at = case when due and (tg_op = 'INSERT' or old.publish_at is distinct from new.publish_at) then now() else updated_at end
  where id = sid;
  return null;
end $$;
drop trigger if exists chapters_count on chapters;
create trigger chapters_count after insert or update of publish_at or delete on chapters for each row execute function trg_chapter_count();

-- Chương hẹn giờ đến hạn không có sự kiện DB nào kích hoạt, nên cần gọi định kỳ để cập nhật số chương và "mới cập nhật".
-- Cách 1 (khuyên dùng): bật extension pg_cron rồi  select cron.schedule('release-chapters','*/5 * * * *','select release_due_chapters()');
-- Cách 2 (dự phòng, đã có sẵn): trang chủ gọi API.releaseDueChapters() tối đa 1 lần/5 phút mỗi trình duyệt.
create or replace function release_due_chapters() returns int language plpgsql security definer set search_path=public as $$
declare n int;
begin
  with x as (
    select s.id, (select count(*) from chapters c where c.story_id = s.id and (c.publish_at is null or c.publish_at <= now())) as cnt
    from stories s where exists(select 1 from chapters c where c.story_id = s.id and c.publish_at is not null))
  update stories s set chapter_count = x.cnt, updated_at = case when x.cnt > s.chapter_count then now() else s.updated_at end
  from x where s.id = x.id and s.chapter_count <> x.cnt;
  get diagnostics n = row_count;
  return n;
end $$;
grant execute on function release_due_chapters() to anon, authenticated;

-- ============================================================
-- 3) US 33, 34, 35: cấp quyền sau thanh toán và xác định quyền gộp
-- ============================================================
-- Quyền của MỘT người dùng bất kỳ (dùng cho Edge Function chạy bằng service role, nơi auth.uid() rỗng)
create or replace function has_story_access_for(p_user uuid, p_story bigint) returns boolean language sql stable security definer set search_path=public as $$
  select p_user is not null and (
    exists(select 1 from story_purchases sp where sp.user_id = p_user and sp.story_id = p_story)
    or exists(
      select 1 from subscriptions sub join plans pl on pl.id = sub.plan_id
      where sub.user_id = p_user and now() >= sub.starts_at and now() < sub.expires_at
        and (pl.scope = 'all' or exists(select 1 from plan_stories ps where ps.plan_id = pl.id and ps.story_id = p_story))
    ))
$$;
revoke execute on function has_story_access_for(uuid, bigint) from public, anon, authenticated;
grant  execute on function has_story_access_for(uuid, bigint) to service_role;
create or replace function has_story_access(p_story bigint) returns boolean language sql stable security definer set search_path=public as $$
  select has_story_access_for(auth.uid(), p_story)
$$;

-- US 35: nguồn quyền để giao diện nói rõ "bạn đọc được nhờ gói X đến ngày Y" / "bạn đã mua truyện này" / cả hai
create or replace function story_access_info(p_story bigint) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'purchased', exists(select 1 from story_purchases sp where sp.user_id = auth.uid() and sp.story_id = p_story),
    'subscription', (
      select jsonb_build_object('plan_name', pl.name, 'expires_at', sub.expires_at)
      from subscriptions sub join plans pl on pl.id = sub.plan_id
      where sub.user_id = auth.uid() and now() >= sub.starts_at and now() < sub.expires_at
        and (pl.scope = 'all' or exists(select 1 from plan_stories ps where ps.plan_id = pl.id and ps.story_id = p_story))
      order by sub.expires_at desc limit 1))
$$;
grant execute on function story_access_info(bigint) to anon, authenticated;

-- Cấp quyền cho đơn đã thanh toán. Được gọi trong CÙNG giao dịch với fulfill_order: lỗi ở đây thì đơn vẫn 'pending' và cổng sẽ gọi lại.
--   plan : thêm dòng subscriptions; nếu đang có gói CÙNG LOẠI còn hạn thì nối tiếp sau ngày hết hạn (gia hạn), không mất ngày.
--   story: thêm story_purchases (mua lại đã sở hữu thì bỏ qua).
create or replace function grant_entitlement(p_order uuid) returns void language plpgsql security definer set search_path=public as $$
declare o orders%rowtype; pl plans%rowtype; s_at timestamptz;
begin
  select * into o from orders where id = p_order;
  if not found then raise exception 'Không tìm thấy đơn hàng'; end if;
  if o.kind = 'plan' then
    select * into pl from plans where id = o.plan_id;
    select coalesce(max(expires_at), now()) into s_at from subscriptions where user_id = o.user_id and plan_id = o.plan_id and expires_at > now();
    insert into subscriptions(user_id, plan_id, order_id, starts_at, expires_at)
    values (o.user_id, o.plan_id, o.id, s_at, s_at + make_interval(days => pl.duration_days))
    on conflict (order_id) where order_id is not null do nothing;
  else
    insert into story_purchases(user_id, story_id, order_id) values (o.user_id, o.story_id, o.id) on conflict do nothing;
  end if;
end $$;
create unique index if not exists subscriptions_order_uq on subscriptions (order_id) where order_id is not null;
revoke execute on function grant_entitlement(uuid) from public, anon, authenticated;
grant  execute on function grant_entitlement(uuid) to service_role;

-- Đơn đã 'paid' từ Sprint 3 (lúc grant_entitlement còn trống) nhưng chưa có quyền: cấp bù một lần
select grant_entitlement(o.id) from orders o
where o.status = 'paid'
  and not exists(select 1 from subscriptions s where s.order_id = o.id)
  and not exists(select 1 from story_purchases p where p.order_id = o.id);

-- US 36: thành viên xem được tên gói/truyện của chính mình kể cả khi gói đã ngừng bán
drop policy if exists plans_read on plans;
create policy plans_read on plans for select using (
  is_active or is_admin()
  or exists(select 1 from subscriptions s where s.plan_id = plans.id and s.user_id = auth.uid())
  or exists(select 1 from orders o where o.plan_id = plans.id and o.user_id = auth.uid()));

-- ============================================================
-- 4) US 40: ghi nhận lượt đọc theo chương theo ngày (phục vụ thống kê story 28) và chỉ tính khi THỰC SỰ đọc được
-- ============================================================
create table if not exists chapter_views_daily (
  chapter_id bigint references chapters(id) on delete cascade,
  day date not null,
  views int not null default 0,
  primary key (chapter_id, day)
);
alter table chapter_views_daily enable row level security;
drop policy if exists cvd_read on chapter_views_daily;
create policy cvd_read on chapter_views_daily for select using (
  is_admin() or exists(select 1 from chapters c where c.id = chapter_id and owns_story(c.story_id)));
revoke insert, update, delete on chapter_views_daily from anon, authenticated;

create or replace function track_view(p_story bigint, p_chapter bigint default null) returns void language plpgsql security definer set search_path=public as $$
declare hdr json; who text; n int;
begin
  perform 1 from stories where id = p_story and status = 'published';
  if not found then return; end if;
  if p_chapter is not null then
    -- Chương phải thuộc truyện này VÀ người xem đọc được thật (chặn việc "bơm" lượt xem chương trả phí/chưa phát hành)
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
    insert into chapter_views_daily(chapter_id, day, views) values (p_chapter, current_date, 1)
    on conflict (chapter_id, day) do update set views = chapter_views_daily.views + 1;
  end if;
  insert into story_views_daily(story_id, day, views) values (p_story, current_date, 1)
  on conflict (story_id, day) do update set views = story_views_daily.views + 1;
end $$;
