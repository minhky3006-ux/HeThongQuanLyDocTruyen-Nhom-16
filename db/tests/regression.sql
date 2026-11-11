-- KIỂM THỬ HỒI QUY PHÂN QUYỀN & NGHIỆP VỤ Ở TẦNG DB. Chạy được ngay trong Supabase SQL Editor, KHÔNG để lại dữ liệu.
-- Điều kiện: đã chạy schema.sql + db/migrations/ALL_sprint3-6.sql + db/seed_test_ALL.sql.
-- Cách dùng: dán cả file, bấm Run, đọc bảng kết quả cuối ("PASS"/"FAIL"). Mọi thay đổi trong lúc kiểm thử được hoàn tác.
-- Cơ chế: toàn bộ chạy trong một khối con rồi cố ý gây lỗi để hoàn tác; kết quả nằm trong biến nên vẫn đọc được.
-- Mỗi lần thêm tính năng mới, thêm một dòng kiểm tra ở đây rồi chạy lại trước khi nộp.

create or replace function pg_temp.login(p_email text) returns void language plpgsql as $$
declare u uuid;
begin
  select id into u from auth.users where email = p_email;
  if u is null then raise exception 'Thiếu tài khoản test %, hãy chạy db/seed_test_ALL.sql', p_email; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u::text, true);
  execute 'set local role authenticated';
end $$;
create or replace function pg_temp.anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
end $$;
create or replace function pg_temp.logout() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
create or replace function pg_temp.uid(p_email text) returns uuid language sql as $$ select id from auth.users where email = p_email $$;
create or replace function pg_temp.ch(p_story bigint, p_no int) returns bigint language sql as $$ select id from chapters where story_id = p_story and number = p_no $$;
create or replace function pg_temp.chk(p_name text, p_ok boolean) returns text language sql as $$
  select case when coalesce(p_ok, false) then 'PASS | ' else 'FAIL | ' end || p_name
$$;

do $test$
declare
  res text[] := '{}'; u2 uuid; u3 uuid; uadm uuid; v boolean; n bigint; t text; c102 bigint; c101 bigint; c103_1 bigint; c103_3 bigint; c104 bigint; story_new bigint; ch_new bigint; o uuid;
begin
  begin  -- khối con: mọi thay đổi bị hoàn tác ở cuối
    u2 := pg_temp.uid('thanhvien2@example.com'); u3 := pg_temp.uid('thanhvien3@example.com'); uadm := pg_temp.uid('admin@example.com');
    c101 := pg_temp.ch(101, 1); c102 := pg_temp.ch(102, 1); c103_1 := pg_temp.ch(103, 1); c103_3 := pg_temp.ch(103, 3); c104 := pg_temp.ch(104, 1);
    update stories set access_policy = 'free' where id = 101;
    update stories set access_policy = 'paid' where id in (102, 104);
    update stories set access_policy = 'mixed' where id = 103;
    update chapters set is_free_preview = (story_id = 103 and number <= 2) where story_id in (101, 102, 103, 104);
    delete from subscriptions where user_id in (pg_temp.uid('thanhvien1@example.com'), pg_temp.uid('thanhvien2@example.com'), pg_temp.uid('thanhvien3@example.com'));
    delete from story_purchases where user_id in (pg_temp.uid('thanhvien1@example.com'), pg_temp.uid('thanhvien2@example.com'), pg_temp.uid('thanhvien3@example.com'));
    insert into plans(name, price, duration_days, scope) values ('__test_all', 50000, 30, 'all'), ('__test_sel', 30000, 30, 'selected');
    insert into plan_stories select id, 103 from plans where name = '__test_sel';
    insert into subscriptions(user_id, plan_id, starts_at, expires_at) select pg_temp.uid('thanhvien2@example.com'), id, now() - interval '1 day', now() + interval '29 days' from plans where name = '__test_all';
    insert into subscriptions(user_id, plan_id, starts_at, expires_at) select pg_temp.uid('thanhvien3@example.com'), id, now() - interval '40 days', now() - interval '10 days' from plans where name = '__test_all';

    -- ===== Quyền đọc chương =====
    perform pg_temp.anon();  v := can_read_chapter(c101); perform pg_temp.logout(); res := res || pg_temp.chk('Khách đọc được chương truyện miễn phí', v);
    perform pg_temp.anon();  v := can_read_chapter(c102); perform pg_temp.logout(); res := res || pg_temp.chk('Khách KHÔNG đọc được chương truyện trả phí', not v);
    perform pg_temp.anon();  v := can_read_chapter(c103_1); perform pg_temp.logout(); res := res || pg_temp.chk('Truyện kết hợp: chương đọc thử mở cho khách', v);
    perform pg_temp.anon();  v := can_read_chapter(c103_3); perform pg_temp.logout(); res := res || pg_temp.chk('Truyện kết hợp: chương không đọc thử bị khóa', not v);
    perform pg_temp.login('thanhvien1@example.com'); v := can_read_chapter(c102); perform pg_temp.logout(); res := res || pg_temp.chk('Thành viên không có gói bị khóa chương trả phí', not v);
    perform pg_temp.login('thanhvien3@example.com'); v := can_read_chapter(c102); perform pg_temp.logout(); res := res || pg_temp.chk('Gói ĐÃ HẾT HẠN không còn quyền đọc', not v);
    perform pg_temp.login('thanhvien2@example.com'); v := can_read_chapter(c102) and can_read_chapter(c104) and can_read_chapter(c103_3); perform pg_temp.logout(); res := res || pg_temp.chk('Gói còn hạn (phạm vi tất cả) đọc được mọi truyện trả phí', v);
    perform pg_temp.login('tacgia1@example.com'); v := can_read_chapter(c102); perform pg_temp.logout(); res := res || pg_temp.chk('Tác giả đọc được truyện của mình', v);
    perform pg_temp.login('tacgia1@example.com'); v := can_read_chapter(c104); perform pg_temp.logout(); res := res || pg_temp.chk('Tác giả KHÔNG đọc được truyện trả phí của người khác', not v);
    perform pg_temp.login('admin@example.com'); v := can_read_chapter(c104); perform pg_temp.logout(); res := res || pg_temp.chk('Admin đọc được mọi chương', v);
    perform pg_temp.anon(); select count(*) into n from chapter_contents where chapter_id = c102; perform pg_temp.logout(); res := res || pg_temp.chk('Khách không lấy được nội dung chương trả phí qua bảng chapter_contents', n = 0);
    perform pg_temp.anon(); select count(*) into n from chapters where story_id = 102; perform pg_temp.logout(); res := res || pg_temp.chk('Khách vẫn thấy danh sách chương trả phí (để hiện nhãn)', n >= 1);
    -- gói phạm vi "chọn truyện" chỉ phủ truyện được chọn
    delete from subscriptions where user_id = pg_temp.uid('thanhvien1@example.com');
    insert into subscriptions(user_id, plan_id, starts_at, expires_at) select pg_temp.uid('thanhvien1@example.com'), id, now(), now() + interval '30 days' from plans where name = '__test_sel';
    perform pg_temp.login('thanhvien1@example.com'); v := can_read_chapter(c103_3) and not can_read_chapter(c102); perform pg_temp.logout(); res := res || pg_temp.chk('Gói "truyện chọn lọc": mở truyện được chọn, KHÔNG mở truyện khác', v);
    delete from subscriptions where user_id = pg_temp.uid('thanhvien1@example.com');

    -- ===== Ghi dữ liệu trái phép =====
    v := false; begin perform pg_temp.login('thanhvien1@example.com'); insert into orders(user_id, kind, plan_id, amount, provider) select auth.uid(), 'plan', id, 1, 'mock' from plans limit 1; v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Thành viên KHÔNG tự tạo được đơn hàng', not v);
    v := false; begin perform pg_temp.login('thanhvien1@example.com'); insert into subscriptions(user_id, plan_id, expires_at) select auth.uid(), id, now() + interval '99 days' from plans limit 1; v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Thành viên KHÔNG tự cấp gói cho mình', not v);
    v := false; begin perform pg_temp.login('thanhvien1@example.com'); perform fulfill_order(gen_random_uuid(), 'x', 1); v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Thành viên KHÔNG gọi được fulfill_order', not v);
    v := false; begin perform pg_temp.login('tacgia1@example.com'); update stories set access_policy = 'free' where id = 102; v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Tác giả KHÔNG tự đổi chính sách truy cập/giá truyện', not v);
    v := false; begin perform pg_temp.login('thanhvien1@example.com'); perform admin_set_story_price(102, 1); v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Thành viên không đặt được giá truyện (admin_set_story_price)', not v);

    -- ===== Thanh toán & cấp quyền =====
    insert into orders(id, user_id, kind, plan_id, amount, provider) select gen_random_uuid(), pg_temp.uid('thanhvien1@example.com'), 'plan', id, price, 'mock' from plans where name = '__test_all' returning id into o;
    perform fulfill_order(o, 'T-REG-1', 50000); perform fulfill_order(o, 'T-REG-1', 50000);
    select count(*) into n from subscriptions where order_id = o; res := res || pg_temp.chk('Thanh toán gói thành công cấp ĐÚNG 1 gói, gọi lặp không cấp thêm', n = 1);
    perform pg_temp.login('thanhvien1@example.com'); v := can_read_chapter(c102); perform pg_temp.logout(); res := res || pg_temp.chk('Sau khi thanh toán gói, đọc được chương trả phí', v);
    insert into orders(id, user_id, kind, plan_id, amount, provider) select gen_random_uuid(), pg_temp.uid('thanhvien1@example.com'), 'plan', id, price, 'mock' from plans where name = '__test_all' returning id into o;
    perform fulfill_order(o, 'T-REG-2', 50000);
    select (max(starts_at) filter (where order_id = o) = max(expires_at) filter (where order_id <> o)) into v from subscriptions where user_id = pg_temp.uid('thanhvien1@example.com');
    res := res || pg_temp.chk('Mua lại cùng gói: gia hạn NỐI TIẾP đúng lúc gói trước hết hạn', v);
    insert into orders(id, user_id, kind, plan_id, amount, provider) select gen_random_uuid(), pg_temp.uid('thanhvien3@example.com'), 'plan', id, price, 'mock' from plans where name = '__test_all' returning id into o;
    t := fulfill_order(o, 'T-REG-3', 1); res := res || pg_temp.chk('Cổng báo sai số tiền: đơn thành failed, không cấp quyền', t = 'failed' and not exists(select 1 from subscriptions where order_id = o));
    insert into orders(id, user_id, kind, story_id, amount, provider) values (gen_random_uuid(), pg_temp.uid('thanhvien1@example.com'), 'story', 104, 25000, 'mock') returning id into o;
    perform fulfill_order(o, 'T-REG-4', 25000);
    perform pg_temp.login('thanhvien1@example.com'); v := has_story_access(104) and (story_access_info(104)->>'purchased')::boolean; perform pg_temp.logout(); res := res || pg_temp.chk('Mua lẻ truyện cấp quyền sở hữu, story_access_info báo purchased', v);

    -- ===== Chương hẹn giờ & số chương =====
    insert into chapters(story_id, title, publish_at) values (101, '__hen_gio', now() + interval '1 day') returning id into ch_new;
    perform pg_temp.anon(); select count(*) into n from chapters where id = ch_new; v := can_read_chapter(ch_new); perform pg_temp.logout();
    res := res || pg_temp.chk('Chương hẹn giờ trong tương lai ẩn với khách (danh sách + quyền đọc)', n = 0 and not v);
    perform pg_temp.login('tacgia1@example.com'); select count(*) into n from chapters where id = ch_new; perform pg_temp.logout(); res := res || pg_temp.chk('Tác giả vẫn thấy chương hẹn giờ của mình', n = 1);
    update chapters set publish_at = now() - interval '1 minute' where id = ch_new;
    perform pg_temp.anon(); select count(*) into n from chapters where id = ch_new; perform pg_temp.logout(); res := res || pg_temp.chk('Tới giờ hẹn: khách thấy chương', n = 1);

    -- ===== Thông báo chương mới =====
    insert into follows(user_id, story_id) values (pg_temp.uid('thanhvien2@example.com'), 101) on conflict do nothing;
    delete from notifications where user_id = pg_temp.uid('thanhvien2@example.com');
    insert into chapters(story_id, title) values (101, '__thong_bao') returning id into ch_new;
    select count(*) into n from notifications where chapter_id = ch_new and user_id = pg_temp.uid('thanhvien2@example.com'); res := res || pg_temp.chk('Người theo dõi nhận thông báo khi có chương mới', n = 1);
    select count(*) into n from notifications where chapter_id = ch_new and user_id = pg_temp.uid('tacgia1@example.com'); res := res || pg_temp.chk('Tác giả không tự nhận thông báo chương của mình', n = 0);
    perform pg_temp.login('thanhvien1@example.com'); select count(*) into n from notifications where chapter_id = ch_new and user_id = u2; perform pg_temp.logout(); res := res || pg_temp.chk('Người khác không đọc được thông báo của người đó', n = 0);

    -- ===== Bình luận, báo cáo, hạn chế =====
    v := false; begin perform pg_temp.login('thanhvien3@example.com'); insert into comments(story_id, chapter_id, user_id, body) values (102, c102, auth.uid(), '__khong co quyen'); v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Không có quyền đọc chương thì KHÔNG viết được thảo luận chương đó', not v);
    v := false; begin perform pg_temp.login('thanhvien2@example.com'); insert into comments(story_id, chapter_id, user_id, body) values (102, c102, auth.uid(), '__co quyen'); v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Có quyền đọc chương thì viết được thảo luận chương', v);
    perform pg_temp.anon(); select count(*) into n from comments where body = '__co quyen'; perform pg_temp.logout(); res := res || pg_temp.chk('Khách không thấy thảo luận của chương trả phí', n = 0);
    insert into comments(story_id, chapter_id, user_id, body) values (101, c101, pg_temp.uid('thanhvien3@example.com'), '__bi bao cao');
    v := false; begin perform pg_temp.login('thanhvien2@example.com'); insert into comment_reports(comment_id, reporter_id, reason) select id, auth.uid(), 'spam' from comments where body = '__bi bao cao'; v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Báo cáo bình luận người khác thành công', v);
    v := false; begin perform pg_temp.login('thanhvien2@example.com'); insert into comment_reports(comment_id, reporter_id, reason) select id, auth.uid(), 'abuse' from comments where body = '__bi bao cao'; v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Báo cáo trùng bị chặn', not v);
    v := false; begin perform pg_temp.login('thanhvien3@example.com'); insert into comment_reports(comment_id, reporter_id, reason) select id, auth.uid(), 'spam' from comments where body = '__bi bao cao'; v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Không tự báo cáo bình luận của chính mình', not v);
    v := false; begin perform pg_temp.login('thanhvien1@example.com'); perform admin_report_queue(); v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Thành viên không xem được hàng đợi báo cáo', not v);
    perform pg_temp.login('admin@example.com'); select count(*) into n from admin_report_queue(true, 50, 0) where body = '__bi bao cao'; perform pg_temp.logout(); res := res || pg_temp.chk('Admin thấy bình luận bị báo cáo trong hàng đợi', n = 1);
    perform pg_temp.login('admin@example.com'); perform admin_handle_reports((select id from comments where body = '__bi bao cao'), 'hide', 'test'); perform pg_temp.logout();
    perform pg_temp.login('thanhvien2@example.com'); select count(*) into n from comments where body = '__bi bao cao'; perform pg_temp.logout(); res := res || pg_temp.chk('Bình luận bị ẩn: người khác không còn thấy', n = 0);
    perform pg_temp.login('admin@example.com'); perform admin_restrict_user(u3, 3, 'test'); perform pg_temp.logout();
    v := false; begin perform pg_temp.login('thanhvien3@example.com'); insert into comments(story_id, user_id, body) values (101, auth.uid(), '__bi han che'); v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Người bị hạn chế KHÔNG bình luận được', not v);
    v := false; begin perform pg_temp.login('admin@example.com'); perform admin_restrict_user(uadm, 3, 'x'); v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Không hạn chế được quản trị viên', not v);
    select count(*) into n from moderation_log where action in ('hide_comment', 'restrict'); res := res || pg_temp.chk('Hành động kiểm duyệt được ghi vào nhật ký', n >= 2);

    -- ===== Đối soát & thống kê =====
    insert into orders(id, user_id, kind, plan_id, amount, provider, status, paid_at) select gen_random_uuid(), pg_temp.uid('thanhvien3@example.com'), 'plan', id, price, 'mock', 'paid', now() from plans where name = '__test_sel' returning id into o;
    v := order_issue(o) = 'paid_no_entitlement'; res := res || pg_temp.chk('Đơn đã thu tiền nhưng chưa có quyền bị đánh dấu bất thường', v);
    perform pg_temp.login('admin@example.com'); t := admin_fix_order(o, 'regrant', 'test'); perform pg_temp.logout();
    res := res || pg_temp.chk('Admin cấp lại quyền: đơn hết bất thường', t = 'paid' and order_issue(o) is null and exists(select 1 from subscriptions where order_id = o));
    v := false; begin perform pg_temp.login('thanhvien1@example.com'); perform admin_fix_order(o, 'ignore', 'hack'); v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Thành viên không xử lý được đơn (admin_fix_order)', not v);
    v := false; begin perform pg_temp.login('thanhvien1@example.com'); perform admin_revenue_plans(current_date - 7, current_date); v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Thành viên không xem được thống kê doanh thu gói', not v);
    v := false; begin perform pg_temp.login('tacgia1@example.com'); perform admin_revenue_stories(current_date - 7, current_date); v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Tác giả không xem được doanh thu toàn hệ thống', not v);
    v := false; begin perform pg_temp.anon(); perform admin_content_stats(current_date - 7, current_date); v := true; exception when others then v := false; end; perform pg_temp.logout();
    res := res || pg_temp.chk('Khách không xem được thống kê nội dung', not v);
    perform pg_temp.login('admin@example.com');
    v := (admin_revenue_plans(current_date - 60, current_date)->'totals'->>'revenue')::bigint
         = (select coalesce(sum(amount), 0) from orders where status = 'paid' and kind = 'plan' and vn_day(paid_at) between current_date - 60 and current_date);
    perform pg_temp.logout(); res := res || pg_temp.chk('Doanh thu gói khớp tổng đơn đã thanh toán (đối chiếu SQL)', v);
    perform pg_temp.login('admin@example.com');
    v := (admin_revenue_stories(current_date - 60, current_date)->'totals'->>'revenue')::bigint
         = (select coalesce(sum(amount), 0) from orders where status = 'paid' and kind = 'story' and vn_day(paid_at) between current_date - 60 and current_date);
    perform pg_temp.logout(); res := res || pg_temp.chk('Doanh thu mua lẻ khớp tổng đơn đã thanh toán (đối chiếu SQL)', v);
    perform pg_temp.login('admin@example.com');
    v := (admin_content_stats(current_date - 30, current_date)->'totals'->>'views')::bigint
         = (select coalesce(sum(d.views), 0) from story_views_daily d join stories s on s.id = d.story_id and s.status = 'published' where d.day between current_date - 30 and current_date);
    perform pg_temp.logout(); res := res || pg_temp.chk('Tổng lượt xem khớp bảng lượt xem theo ngày, chỉ tính truyện đã đăng', v);

    -- ===== Lượt đọc =====
    delete from view_dedupe; select view_count into n from chapters where id = c102;
    perform pg_temp.login('thanhvien3@example.com'); perform track_view(102, c102); perform pg_temp.logout();
    res := res || pg_temp.chk('Chương bị khóa KHÔNG được tính lượt đọc', (select view_count from chapters where id = c102) = n);
    perform pg_temp.login('thanhvien2@example.com'); perform track_view(102, c102); perform pg_temp.logout();
    res := res || pg_temp.chk('Người có quyền đọc: tính 1 lượt cho chương', (select view_count from chapters where id = c102) = n + 1);

    raise exception '__ROLLBACK__';
  exception when others then
    if sqlerrm <> '__ROLLBACK__' then res := res || ('FAIL | Lỗi không mong đợi khi chạy kiểm thử: ' || sqlerrm); end if;
  end;
  perform set_config('regression.results', array_to_string(res, E'\n'), false);
end $test$;

select line as ket_qua from regexp_split_to_table(current_setting('regression.results'), E'\n') line
union all
select '== TỔNG: ' || count(*) filter (where l like 'PASS%') || ' đạt, ' || count(*) filter (where l not like 'PASS%') || ' lỗi =='
from regexp_split_to_table(current_setting('regression.results'), E'\n') l;
