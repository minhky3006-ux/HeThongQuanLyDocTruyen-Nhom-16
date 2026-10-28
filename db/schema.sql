-- TruyệnXanh · Schema PostgreSQL cho Supabase. Dán toàn bộ file vào SQL Editor rồi Run.
-- Nguyên tắc: DB chỉ lưu "key" của ảnh (vd covers/12.webp), ảnh thật nằm ở Cloudflare R2.
create extension if not exists pg_trgm;  -- tìm kiếm tên truyện nhanh (story 4)

create type user_role    as enum ('member','author','admin');
create type story_kind   as enum ('text','comic');
create type story_status as enum ('draft','pending','published','removed');

-- ========== BẢNG ==========
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_key text,
  role user_role not null default 'member',
  is_locked boolean not null default false,            -- story 15: khóa tài khoản
  created_at timestamptz not null default now()
);
create table genres (
  id smallint generated always as identity primary key,
  name text not null unique, slug text not null unique
);
create table stories (
  id bigint generated always as identity primary key,
  author_id uuid not null references profiles(id),
  title text not null,
  description text,
  kind story_kind not null default 'text',              -- text: chương chữ, comic: chương là chuỗi ảnh
  cover_key text,
  status story_status not null default 'pending',       -- story 16: pending -> admin duyệt -> published
  view_count bigint not null default 0,
  follow_count int not null default 0,
  chapter_count int not null default 0,
  rating_avg numeric(2,1) not null default 0,
  rating_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on stories (status, updated_at desc);
create index on stories (status, view_count desc);
create index on stories (author_id);
create index stories_title_trgm on stories using gin (title gin_trgm_ops);

create table story_genres (
  story_id bigint references stories(id) on delete cascade,
  genre_id smallint references genres(id) on delete cascade,
  primary key (story_id, genre_id)
);
create index on story_genres (genre_id);

create table chapters (
  id bigint generated always as identity primary key,
  story_id bigint not null references stories(id) on delete cascade,
  number int not null,
  title text,
  content text,                                          -- nội dung chữ (kind = text)
  view_count bigint not null default 0,
  created_at timestamptz not null default now(),
  unique (story_id, number)
);
create table chapter_pages (                             -- ảnh của chương (kind = comic)
  id bigint generated always as identity primary key,
  chapter_id bigint not null references chapters(id) on delete cascade,
  page_no smallint not null,
  image_key text not null,                               -- vd: s12/c3/001.webp
  width int, height int,                                 -- giữ chỗ trước khi ảnh tải, tránh giật layout
  unique (chapter_id, page_no)
);
create table follows (                                   -- story 8
  user_id uuid references profiles(id) on delete cascade,
  story_id bigint references stories(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, story_id)
);
create table reading_history (                           -- story 10: đọc tiếp
  user_id uuid references profiles(id) on delete cascade,
  story_id bigint references stories(id) on delete cascade,
  chapter_id bigint references chapters(id) on delete cascade,
  page_no smallint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, story_id)
);
create index on reading_history (user_id, updated_at desc);
create table comments (                                  -- story 9, 18
  id bigint generated always as identity primary key,
  story_id bigint not null references stories(id) on delete cascade,
  chapter_id bigint references chapters(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  body text not null check (length(body) between 1 and 2000),
  is_hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create index on comments (story_id, created_at desc);
create table ratings (
  user_id uuid references profiles(id) on delete cascade,
  story_id bigint references stories(id) on delete cascade,
  score smallint not null check (score between 1 and 5),
  primary key (user_id, story_id)
);
create index on ratings (story_id);
create table story_views_daily (                         -- story 14: thống kê lượt xem
  story_id bigint references stories(id) on delete cascade,
  day date not null, views int not null default 0,
  primary key (story_id, day)
);

-- ========== HÀM TRỢ GIÚP ==========
create function is_admin() returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and role='admin' and not is_locked) $$;
create function is_author() returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and role in ('author','admin') and not is_locked) $$;
create function can_write() returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and not is_locked) $$;
create function owns_story(sid bigint) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from stories where id=sid and author_id=auth.uid()) $$;

-- Tạo profile tự động khi đăng ký (story 5)
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id, display_name, role)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)),
          case when new.raw_user_meta_data->>'want_author' = 'true' then 'author'::user_role else 'member'::user_role end);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- Thành viên đăng ký làm tác giả (story 12)
create function become_author() returns void language sql security definer set search_path=public as
$$ update profiles set role='author' where id=auth.uid() and role='member' and not is_locked $$;
-- Admin khóa/mở tài khoản (story 15)
create function admin_set_locked(uid uuid, locked boolean) returns void language plpgsql security definer set search_path=public as
$$ begin if not is_admin() then raise exception 'forbidden'; end if; update profiles set is_locked=locked where id=uid; end $$;
-- Ghi lượt xem (gọi khi mở chương)
-- Chống bơm lượt đọc: 1 lượt/người/chương/giờ
create table view_dedupe (
  story_id bigint not null,
  chapter_id bigint not null default 0,
  viewer text not null,
  bucket timestamptz not null,
  primary key (story_id, chapter_id, viewer, bucket)
);
alter table view_dedupe enable row level security;          -- không có policy: chỉ hàm security definer ghi được
revoke all on view_dedupe from anon, authenticated;
create function track_view(p_story bigint, p_chapter bigint default null) returns void language plpgsql security definer set search_path=public as $$
declare hdr json; who text; n int;
begin
  perform 1 from stories where id=p_story and status='published';
  if not found then return; end if;
  begin hdr := nullif(current_setting('request.headers', true), '')::json; exception when others then hdr := null; end;
  who := coalesce(auth.uid()::text,
                  nullif(trim(split_part(coalesce(hdr->>'cf-connecting-ip', hdr->>'x-forwarded-for', ''), ',', 1)), ''),
                  'unknown');
  insert into view_dedupe(story_id, chapter_id, viewer, bucket)
  values (p_story, coalesce(p_chapter, 0), who, date_trunc('hour', now())) on conflict do nothing;
  get diagnostics n = row_count;
  if n = 0 then return; end if;
  if random() < 0.01 then delete from view_dedupe where bucket < now() - interval '2 days'; end if;
  update stories set view_count=view_count+1 where id=p_story;
  if p_chapter is not null then update chapters set view_count=view_count+1 where id=p_chapter and story_id=p_story; end if;
  insert into story_views_daily(story_id,day,views) values (p_story,current_date,1)
  on conflict (story_id,day) do update set views=story_views_daily.views+1;
end $$;

-- ========== TRIGGER ĐẾM (đọc danh sách không cần count(*)) ==========
create function trg_chapter_count() returns trigger language plpgsql security definer set search_path=public as $$
begin
  update stories set chapter_count=chapter_count+(case when tg_op='INSERT' then 1 else -1 end), updated_at=now()
  where id=coalesce(new.story_id, old.story_id);
  return null;
end $$;
create trigger chapters_count after insert or delete on chapters for each row execute function trg_chapter_count();
-- Số chương do DB gán khi client không gửi number (tránh trùng khi thêm cùng lúc)
create function trg_chapter_number() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.number is null then
    perform pg_advisory_xact_lock(new.story_id);
    new.number := coalesce((select max(number) from chapters where story_id = new.story_id), 0) + 1;
  end if;
  return new;
end $$;
create trigger chapters_number before insert on chapters for each row execute function trg_chapter_number();
create function trg_follow_count() returns trigger language plpgsql security definer set search_path=public as $$
begin
  update stories set follow_count=follow_count+(case when tg_op='INSERT' then 1 else -1 end)
  where id=coalesce(new.story_id, old.story_id);
  return null;
end $$;
create trigger follows_count after insert or delete on follows for each row execute function trg_follow_count();
create function trg_rating() returns trigger language plpgsql security definer set search_path=public as $$
declare sid bigint := coalesce(new.story_id, old.story_id);
begin
  update stories set rating_avg=coalesce((select round(avg(score),1) from ratings where story_id=sid),0),
                     rating_count=(select count(*) from ratings where story_id=sid) where id=sid;
  return null;
end $$;
create trigger ratings_calc after insert or update or delete on ratings for each row execute function trg_rating();

-- Tác giả chỉ được đưa truyện về draft/pending; published/removed là việc của admin (story 16)
create function trg_story_status_guard() returns trigger language plpgsql security definer set search_path=public as $$
begin
  -- auth.uid() null = chạy từ SQL Editor/service role (vd db/dev.sql) → cho phép
  if new.status is distinct from old.status and auth.uid() is not null and not is_admin() then
    if old.status = 'removed' or new.status not in ('draft','pending') then
      raise exception 'row-level security: chỉ quản trị viên được duyệt/gỡ truyện';
    end if;
  end if;
  return new;
end $$;
create trigger stories_status_guard before update on stories for each row execute function trg_story_status_guard();

-- ========== QUYỀN CỘT (chặn tự sửa role, bộ đếm...) ==========
revoke update on profiles, stories, comments from anon, authenticated;
grant update (display_name, avatar_key) on profiles to authenticated;
grant update (title, description, cover_key, kind, status) on stories to authenticated;
grant update (is_hidden) on comments to authenticated;

-- ========== ROW LEVEL SECURITY ==========
alter table profiles enable row level security;       alter table genres enable row level security;
alter table stories enable row level security;        alter table story_genres enable row level security;
alter table chapters enable row level security;       alter table chapter_pages enable row level security;
alter table follows enable row level security;        alter table reading_history enable row level security;
alter table comments enable row level security;       alter table ratings enable row level security;
alter table story_views_daily enable row level security;

create policy profiles_read   on profiles for select using (true);
create policy profiles_update on profiles for update using (id=auth.uid());
create policy genres_read     on genres for select using (true);
create policy genres_admin    on genres for all using (is_admin()) with check (is_admin());

create policy stories_read    on stories for select using (status='published' or author_id=auth.uid() or is_admin());
create policy stories_insert  on stories for insert with check (author_id=auth.uid() and is_author() and status in ('draft','pending'));
create policy stories_update  on stories for update using (author_id=auth.uid()) with check (author_id=auth.uid());  -- đổi trạng thái do trigger stories_status_guard kiểm soát
create policy stories_admin   on stories for update using (is_admin()) with check (is_admin());
create policy stories_delete  on stories for delete using (author_id=auth.uid() or is_admin());

create policy sg_read   on story_genres for select using (true);
create policy sg_write  on story_genres for all using (owns_story(story_id) or is_admin()) with check (owns_story(story_id) or is_admin());

create policy chapters_read  on chapters for select using (
  exists(select 1 from stories s where s.id=story_id and (s.status='published' or s.author_id=auth.uid())) or is_admin());
create policy chapters_write on chapters for all using (owns_story(story_id)) with check (owns_story(story_id) and is_author());
create policy pages_read  on chapter_pages for select using (
  exists(select 1 from chapters c join stories s on s.id=c.story_id where c.id=chapter_id and (s.status='published' or s.author_id=auth.uid())) or is_admin());
create policy pages_write on chapter_pages for all
  using (exists(select 1 from chapters c where c.id=chapter_id and owns_story(c.story_id)))
  with check (exists(select 1 from chapters c where c.id=chapter_id and owns_story(c.story_id)));

create policy follows_own on follows for all using (user_id=auth.uid()) with check (user_id=auth.uid() and can_write());
create policy history_own on reading_history for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy comments_read   on comments for select using (not is_hidden or user_id=auth.uid() or is_admin());
create policy comments_insert on comments for insert with check (user_id=auth.uid() and can_write());
create policy comments_delete on comments for delete using (user_id=auth.uid() or is_admin());
create policy comments_hide   on comments for update using (is_admin()) with check (is_admin());
create policy ratings_read  on ratings for select using (true);
create policy ratings_write on ratings for all using (user_id=auth.uid()) with check (user_id=auth.uid() and can_write());
create policy views_read on story_views_daily for select using (owns_story(story_id) or is_admin());
