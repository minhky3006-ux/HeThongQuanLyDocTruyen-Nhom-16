-- Migration 001 · Vá lỗi/rủi ro sau đánh giá Sprint 1. Chạy MỘT lần trong Supabase SQL Editor (DB đã chạy schema.sql cũ).
-- DB mới tạo từ schema.sql hiện tại đã có sẵn các thay đổi này, không cần chạy file này.
-- Chạy lại nhiều lần vẫn an toàn.

-- 1) Tick "tôi muốn đăng truyện" khi đăng ký không còn mất khi bật Confirm email:
--    web gửi want_author=true trong metadata, trigger tạo profile gán luôn role tác giả.
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id, display_name, role)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)),
          case when new.raw_user_meta_data->>'want_author' = 'true' then 'author'::user_role else 'member'::user_role end);
  return new;
end $$;

-- 2) Số chương do DB gán (có khóa theo truyện) → không còn lỗi trùng khi hai lần thêm chương cùng lúc.
create or replace function trg_chapter_number() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.number is null then
    perform pg_advisory_xact_lock(new.story_id);
    new.number := coalesce((select max(number) from chapters where story_id = new.story_id), 0) + 1;
  end if;
  return new;
end $$;
drop trigger if exists chapters_number on chapters;
create trigger chapters_number before insert on chapters for each row execute function trg_chapter_number();

-- 3) Chống bơm lượt đọc: mỗi người (user, hoặc IP nếu chưa đăng nhập) chỉ tính 1 lượt/chương/giờ.
create table if not exists view_dedupe (
  story_id bigint not null,
  chapter_id bigint not null default 0,
  viewer text not null,
  bucket timestamptz not null,
  primary key (story_id, chapter_id, viewer, bucket)
);
alter table view_dedupe enable row level security;          -- không có policy: chỉ hàm security definer ghi được
revoke all on view_dedupe from anon, authenticated;
create or replace function track_view(p_story bigint, p_chapter bigint default null) returns void language plpgsql security definer set search_path=public as $$
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

-- 4) Tác giả sửa được tên/mô tả/bìa truyện ĐÃ DUYỆT, nhưng không tự đổi trạng thái sang published,
--    và truyện bị gỡ (removed) không tự "sống lại" bằng cách đặt về pending.
drop policy if exists stories_update on stories;
create policy stories_update on stories for update using (author_id=auth.uid()) with check (author_id=auth.uid());
create or replace function trg_story_status_guard() returns trigger language plpgsql security definer set search_path=public as $$
begin
  -- auth.uid() null = chạy từ SQL Editor/service role (vd db/dev.sql) → cho phép
  if new.status is distinct from old.status and auth.uid() is not null and not is_admin() then
    if old.status = 'removed' or new.status not in ('draft','pending') then
      raise exception 'row-level security: chỉ quản trị viên được duyệt/gỡ truyện';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists stories_status_guard on stories;
create trigger stories_status_guard before update on stories for each row execute function trg_story_status_guard();
