-- Migration 002 · Sprint 3: chính sách truy cập (US 19), gói đọc (US 21), kiểm tra quyền đọc (US 31),
-- ghi nhận giao dịch (US 32), mốc "mới phát hành" (US 29), trạng thái chương (US 30).
-- Chạy MỘT lần trong Supabase SQL Editor, SAU schema.sql (và sau 001 nếu DB cũ). Chạy lại nhiều lần vẫn an toàn.
-- !! Gói Free không có backup: xuất dữ liệu (Dashboard > Database > Backups hoặc pg_dump) TRƯỚC khi chạy,
--    vì file này chuyển nội dung chương sang bảng riêng rồi xóa cột chapters.content.

-- ============================================================
-- 1) Chính sách truy cập truyện/chương (US 19)
--    free  : mọi chương miễn phí (mặc định, truyện cũ giữ nguyên)
--    paid  : mọi chương trả phí
--    mixed : chương đánh dấu is_free_preview đọc thử miễn phí, các chương còn lại trả phí
-- ============================================================
do $$ begin
  create type access_policy as enum ('free','paid','mixed');
exception when duplicate_object then null; end $$;

alter table stories  add column if not exists access_policy access_policy not null default 'free';
alter table chapters add column if not exists is_free_preview boolean not null default false;

-- "Mới phát hành" (US 29) = thời điểm truyện được duyệt lần đầu, khác created_at (lúc tạo) và updated_at (lúc có chương mới)
alter table stories add column if not exists published_at timestamptz;
update stories set published_at = coalesce(updated_at, created_at) where status = 'published' and published_at is null;
create index if not exists stories_published_idx on stories (status, published_at desc);
create or replace function trg_story_published_at() returns trigger language plpgsql as $$
begin
  if new.status = 'published' and new.published_at is null then new.published_at := now(); end if;
  return new;
end $$;
drop trigger if exists stories_published_at on stories;
create trigger stories_published_at before insert or update on stories for each row execute function trg_story_published_at();

-- ============================================================
-- 2) Gói đọc theo tháng (US 21) + quyền sở hữu (dùng cho US 31, điền dữ liệu ở Sprint 4: US 33–35)
-- ============================================================
do $$ begin
  create type plan_scope as enum ('all','selected');   -- all: mọi truyện trả phí · selected: chỉ truyện trong plan_stories
exception when duplicate_object then null; end $$;

create table if not exists plans (
  id int generated always as identity primary key,
  name text not null check (length(name) between 1 and 80),
  description text,
  price int not null check (price > 0),                -- VND, số nguyên
  duration_days int not null check (duration_days between 1 and 3660),
  scope plan_scope not null default 'all',
  is_active boolean not null default true,             -- false = ngừng bán; người đã mua vẫn dùng đến hết hạn
  created_at timestamptz not null default now()
);
create table if not exists plan_stories (
  plan_id int references plans(id) on delete cascade,
  story_id bigint references stories(id) on delete cascade,
  primary key (plan_id, story_id)
);
create index if not exists plan_stories_story_idx on plan_stories (story_id);

-- ============================================================
-- 3) Đơn hàng / giao dịch (US 32). Client chỉ ĐỌC đơn của mình; mọi thao tác ghi do Edge Function (service role).
-- ============================================================
do $$ begin
  create type order_status as enum ('pending','paid','failed','cancelled');
exception when duplicate_object then null; end $$;
do $$ begin
  create type order_kind as enum ('plan','story');
exception when duplicate_object then null; end $$;

create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id),
  kind order_kind not null,
  plan_id int references plans(id),
  story_id bigint references stories(id),
  amount int not null check (amount > 0),              -- giá CHỐT tại thời điểm tạo đơn (lấy từ DB, không tin client)
  currency text not null default 'VND',
  provider text not null,                              -- 'mock' | 'vnpay' | ...
  status order_status not null default 'pending',
  provider_txn text,                                   -- mã giao dịch phía cổng
  fail_reason text,
  raw jsonb,                                           -- dữ liệu cổng trả về, giữ để đối soát (US 24)
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  check ((kind = 'plan' and plan_id is not null and story_id is null)
      or (kind = 'story' and story_id is not null and plan_id is null))
);
create index if not exists orders_user_idx on orders (user_id, created_at desc);
create unique index if not exists orders_provider_txn_uq on orders (provider, provider_txn) where provider_txn is not null;

create table if not exists subscriptions (             -- điền ở Sprint 4 (US 33)
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  plan_id int not null references plans(id),
  order_id uuid references orders(id),
  starts_at timestamptz not null default now(),
  expires_at timestamptz not null,
  check (expires_at > starts_at)
);
create index if not exists subscriptions_user_idx on subscriptions (user_id, expires_at desc);
create table if not exists story_purchases (           -- điền ở Sprint 4 (US 34)
  user_id uuid references profiles(id) on delete cascade,
  story_id bigint references stories(id) on delete cascade,
  order_id uuid references orders(id),
  created_at timestamptz not null default now(),
  primary key (user_id, story_id)
);

-- ============================================================
-- 4) Quyền đọc (US 31). Đây là nơi DUY NHẤT quyết định ai được đọc; giao diện chỉ hiển thị theo kết quả.
-- ============================================================
-- Người dùng hiện tại có gói còn hạn bao phủ truyện này, hoặc đã mua lẻ truyện này?
create or replace function has_story_access(p_story bigint) returns boolean language sql stable security definer set search_path=public as $$
  select auth.uid() is not null and (
    exists(select 1 from story_purchases sp where sp.user_id = auth.uid() and sp.story_id = p_story)
    or exists(
      select 1 from subscriptions sub join plans pl on pl.id = sub.plan_id
      where sub.user_id = auth.uid() and now() >= sub.starts_at and now() < sub.expires_at
        and (pl.scope = 'all' or exists(select 1 from plan_stories ps where ps.plan_id = pl.id and ps.story_id = p_story))
    ))
$$;

-- Người dùng hiện tại đọc được nội dung chương này không?
create or replace function can_read_chapter(p_chapter bigint) returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from chapters c join stories s on s.id = c.story_id
    where c.id = p_chapter and (
      is_admin()
      or s.author_id = auth.uid()
      or (s.status = 'published' and (
            s.access_policy = 'free'
         or (s.access_policy = 'mixed' and c.is_free_preview)
         or has_story_access(s.id)
      ))
    ))
$$;
grant execute on function has_story_access(bigint), can_read_chapter(bigint) to anon, authenticated;

-- ============================================================
-- 5) Tách nội dung chương sang bảng riêng để RLS chặn được (chapters_read chỉ cho xem tiêu đề/số chương)
-- ============================================================
create table if not exists chapter_contents (
  chapter_id bigint primary key references chapters(id) on delete cascade,
  content text not null
);
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='chapters' and column_name='content') then
    insert into chapter_contents(chapter_id, content)
      select id, content from chapters where content is not null on conflict (chapter_id) do nothing;
    alter table chapters drop column content;
  end if;
end $$;

alter table chapter_contents enable row level security;
drop policy if exists cc_read  on chapter_contents;
drop policy if exists cc_write on chapter_contents;
create policy cc_read  on chapter_contents for select using (can_read_chapter(chapter_id));
create policy cc_write on chapter_contents for all
  using (exists(select 1 from chapters c where c.id = chapter_id and owns_story(c.story_id)))
  with check (exists(select 1 from chapters c where c.id = chapter_id and owns_story(c.story_id)) and is_author());

-- Ảnh trang truyện tranh: chỉ trả danh sách key khi có quyền đọc (xem "Giới hạn đã biết" trong db/README.md về link ảnh R2)
drop policy if exists pages_read on chapter_pages;
create policy pages_read on chapter_pages for select using (can_read_chapter(chapter_id));

-- ============================================================
-- 6) RLS cho bảng mới
-- ============================================================
alter table plans enable row level security;          alter table plan_stories enable row level security;
alter table orders enable row level security;         alter table subscriptions enable row level security;
alter table story_purchases enable row level security;

drop policy if exists plans_read  on plans;           drop policy if exists plans_admin on plans;
create policy plans_read  on plans for select using (is_active or is_admin());
create policy plans_admin on plans for all using (is_admin()) with check (is_admin());
drop policy if exists ps_read on plan_stories;        drop policy if exists ps_admin on plan_stories;
create policy ps_read  on plan_stories for select using (true);
create policy ps_admin on plan_stories for all using (is_admin()) with check (is_admin());

drop policy if exists orders_read on orders;
create policy orders_read on orders for select using (user_id = auth.uid() or is_admin());
drop policy if exists subs_read on subscriptions;
create policy subs_read on subscriptions for select using (user_id = auth.uid() or is_admin());
drop policy if exists purchases_read on story_purchases;
create policy purchases_read on story_purchases for select using (user_id = auth.uid() or is_admin());
-- Không có policy ghi: client không thể tự tạo đơn, gói hay quyền sở hữu. Thêm lớp chặn ở mức quyền bảng:
revoke insert, update, delete on orders, subscriptions, story_purchases from anon, authenticated;

-- ============================================================
-- 7) Hàm cho admin (cột access_policy/is_free_preview không nằm trong quyền UPDATE của client, nên đi qua hàm)
-- ============================================================
-- US 19: đặt chính sách + danh sách chương đọc thử trong MỘT giao dịch (p_preview_ids null = giữ nguyên danh sách)
create or replace function admin_set_story_access(p_story bigint, p_policy access_policy, p_preview_ids bigint[] default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'row-level security: chỉ quản trị viên được đặt chính sách truy cập'; end if;
  update stories set access_policy = p_policy where id = p_story;
  if not found then raise exception 'Không tìm thấy truyện'; end if;
  if p_preview_ids is not null then
    update chapters set is_free_preview = (id = any(p_preview_ids)) where story_id = p_story;
  end if;
end $$;
grant execute on function admin_set_story_access(bigint, access_policy, bigint[]) to authenticated;

-- ============================================================
-- 8) Ghi nhận thanh toán (US 32). CHỈ Edge Function (service role) được gọi, người dùng không gọi được.
--    Idempotent: cổng gọi lại nhiều lần vẫn chỉ tính một lần.
-- ============================================================
create or replace function grant_entitlement(p_order uuid) returns void language plpgsql security definer set search_path=public as $$
begin
  -- TODO Sprint 4 (US 33, 34, 35): kind='plan' -> thêm/gia hạn dòng trong subscriptions; kind='story' -> thêm story_purchases.
  -- Hiện cố ý để trống: đơn đã 'paid' nhưng chưa cấp quyền. Khi thử US 31, cấp quyền tay bằng db/dev.sql (lệnh 4).
  null;
end $$;

create or replace function fulfill_order(p_order uuid, p_txn text, p_amount int, p_raw jsonb default null)
returns order_status language plpgsql security definer set search_path=public as $$
declare o orders%rowtype;
begin
  select * into o from orders where id = p_order for update;
  if not found then raise exception 'Không tìm thấy đơn hàng'; end if;
  if o.status = 'paid' then return 'paid'; end if;                     -- gọi lặp: bỏ qua
  if p_amount is distinct from o.amount then                           -- cổng báo số tiền khác đơn: không cấp quyền, giữ lại để đối soát
    update orders set status = 'failed', fail_reason = 'Sai số tiền: cổng báo ' || coalesce(p_amount::text, 'null') || ', đơn ' || o.amount,
                      provider_txn = p_txn, raw = p_raw where id = p_order;
    return 'failed';
  end if;
  update orders set status = 'paid', paid_at = now(), provider_txn = p_txn, raw = p_raw, fail_reason = null where id = p_order;
  perform grant_entitlement(p_order);
  return 'paid';
end $$;
create or replace function fail_order(p_order uuid, p_reason text, p_raw jsonb default null)
returns void language sql security definer set search_path=public as $$
  update orders set status = 'failed', fail_reason = p_reason, raw = coalesce(p_raw, raw) where id = p_order and status = 'pending'
$$;
revoke execute on function fulfill_order(uuid, text, int, jsonb), fail_order(uuid, text, jsonb), grant_entitlement(uuid) from public, anon, authenticated;
grant  execute on function fulfill_order(uuid, text, int, jsonb), fail_order(uuid, text, jsonb), grant_entitlement(uuid) to service_role;
