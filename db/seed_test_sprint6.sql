-- DỮ LIỆU GIẢ CHO SPRINT 6 (thống kê). Chạy SAU migrations 002–005 và seed_test_sprint1/3/4/5. Chạy lại nhiều lần được.
-- Tạo ~60 ngày dữ liệu: đơn mua gói và mua lẻ đã thanh toán, lượt xem truyện/chương theo ngày, thêm người theo dõi và thảo luận chương.
-- Các đơn doanh thu này được đánh dấu "bỏ qua" trong nhật ký đối soát để KHÔNG hiện là bất thường ở trang Giao dịch.

delete from orders where id::text like '00000000-0000-0000-0000-0000000008%';

-- 1. Đơn mua gói (US 26): 24 đơn rải trong 60 ngày, 3 người, luân phiên 3 gói đang bán
insert into orders(id, user_id, kind, plan_id, amount, provider, status, paid_at, provider_txn, created_at)
select ('00000000-0000-0000-0000-0000000008' || lpad(i::text, 2, '0'))::uuid,
       (select id from auth.users where email = 'thanhvien' || (1 + i % 3) || '@example.com'),
       'plan', p.id, p.price, 'mock', 'paid',
       now() - make_interval(hours => (i * 59) % 1440), 'S6-PLAN-' || i,
       now() - make_interval(hours => (i * 59) % 1440)
from generate_series(1, 24) i
join lateral (select id, price from plans where name in ('Gói tháng toàn bộ', 'Gói tuần thử nghiệm', 'Gói chọn lọc') order by name offset (i % 3) limit 1) p on true;

-- 2. Đơn mua lẻ (US 27): 15 đơn cho truyện 102, 103, 104 (giá chốt tại thời điểm mua)
insert into orders(id, user_id, kind, story_id, amount, provider, status, paid_at, provider_txn, created_at)
select ('00000000-0000-0000-0000-0000000008' || lpad((50 + i)::text, 2, '0'))::uuid,
       (select id from auth.users where email = 'thanhvien' || (1 + i % 3) || '@example.com'),
       'story', 102 + i % 3, case 102 + i % 3 when 102 then 39000 when 103 then 25000 else 29000 end, 'mock', 'paid',
       now() - make_interval(hours => (i * 97) % 1440), 'S6-STORY-' || i,
       now() - make_interval(hours => (i * 97) % 1440)
from generate_series(1, 15) i;

insert into order_audit(order_id, action, note)
select id, 'ignore', 'Dữ liệu thống kê giả (seed Sprint 6)' from orders where id::text like '00000000-0000-0000-0000-0000000008%';

-- 3. Lượt xem theo ngày (US 28, 40): 30 ngày gần nhất cho truyện 101–106
insert into story_views_daily(story_id, day, views)
select s, (now() at time zone 'Asia/Ho_Chi_Minh')::date - d, 5 + ((s * 7 + d * 3) % 25)
from generate_series(101, 106) s, generate_series(0, 29) d
on conflict (story_id, day) do update set views = excluded.views;
insert into chapter_views_daily(chapter_id, day, views)
select c.id, (now() at time zone 'Asia/Ho_Chi_Minh')::date - d, 1 + ((c.id::int * 5 + d * 2) % (9 - least(c.number, 6)))
from chapters c, generate_series(0, 29) d where c.story_id between 101 and 106 and c.number <= 4
on conflict (chapter_id, day) do update set views = excluded.views;

-- 4. Thêm người theo dõi và thảo luận chương (US 28)
insert into follows(user_id, story_id)
select u.id, s from auth.users u, (values (101), (102), (104), (105)) v(s) where u.email like 'thanhvien%@example.com' on conflict do nothing;
delete from comments where body like '[S6]%';
insert into comments(story_id, chapter_id, user_id, body)
select c.story_id, c.id, (select id from auth.users where email = 'thanhvien1@example.com'), '[S6] Thảo luận chương ' || c.number || ' (' || g || ')'
from chapters c, generate_series(1, 3) g where c.story_id = 101 and c.number <= 2;

-- 5. Kiểm tra nhanh (mong đợi: 24 đơn gói, 15 đơn mua lẻ; không đơn bất thường mới từ seed này)
select (select count(*) from orders where id::text like '00000000-0000-0000-0000-0000000008%' and kind = 'plan') as don_goi,
       (select count(*) from orders where id::text like '00000000-0000-0000-0000-0000000008%' and kind = 'story') as don_mua_le,
       (select count(*) from orders where id::text like '00000000-0000-0000-0000-0000000008%' and order_issue(id) is not null) as bat_thuong_tu_seed6;
