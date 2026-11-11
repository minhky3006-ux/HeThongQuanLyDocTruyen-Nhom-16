-- DỮ LIỆU GIẢ CHO SPRINT 5. Chạy SAU migrations 002–004 và seed_test_sprint1/3/4. Chạy lại nhiều lần được.
-- Kịch bản thử (mật khẩu Test@123456):
--   Báo cáo (story 38, 23): admin vào Quản trị › Báo cáo thấy 2 bình luận chờ xử lý (1 bình luận bị 2 báo cáo)
--   Thông báo (story 39): thanhvien1, thanhvien2 theo dõi truyện 101 và 103 -> đăng nhập thấy chuông có thông báo chương mới
--   Đối soát (story 24): admin vào Quản trị › Giao dịch thấy 4 đơn bất thường (đã thu tiền chưa cấp quyền, chờ quá lâu, sai số tiền, mua lẻ trùng)
--   Thảo luận chương (story 37): chương 1 truyện 101 (miễn phí) và chương 1 truyện 102 (chỉ người có gói thấy) đã có thảo luận
--   Thống kê (story 25): Quản trị › Thống kê thành viên

-- 0. Dọn dữ liệu thử của seed này
delete from comments where body like '[S5]%';
delete from story_purchases where user_id = (select id from auth.users where email = 'thanhvien3@example.com') and story_id = 104;
delete from orders where id::text like '00000000-0000-0000-0000-0000000007%';
delete from chapters where story_id = 103 and title = 'Chương mới (seed S5)';
delete from user_restrictions;

-- 1. Theo dõi (story 39)
insert into follows(user_id, story_id)
select u.id, s from auth.users u, (values (101), (103)) v(s)
where u.email in ('thanhvien1@example.com', 'thanhvien2@example.com') on conflict do nothing;

-- 2. Thảo luận theo chương (story 37) và bình luận cấp truyện
insert into comments(story_id, chapter_id, user_id, body)
select 101, (select id from chapters where story_id = 101 and number = 1), (select id from auth.users where email = 'thanhvien1@example.com'), '[S5] Chương đầu mở đầu rất cuốn!'
union all select 101, (select id from chapters where story_id = 101 and number = 1), (select id from auth.users where email = 'thanhvien3@example.com'), '[S5] Mua gói ngay tại link này nhé, giảm 90%!!!'
union all select 102, (select id from chapters where story_id = 102 and number = 1), (select id from auth.users where email = 'thanhvien2@example.com'), '[S5] Chương trả phí này đáng tiền.'
union all select 101, null, (select id from auth.users where email = 'thanhvien3@example.com'), '[S5] Bạn nào xem rồi thì spoil giùm kết truyện đi';

-- 3. Báo cáo (story 38): 2 người báo cáo bình luận quảng cáo; 1 người báo cáo bình luận đòi spoil
insert into comment_reports(comment_id, reporter_id, reason, note)
select c.id, u.id, 'spam'::report_reason, 'Quảng cáo rõ ràng' from comments c, auth.users u
where c.body like '[S5] Mua gói ngay%' and u.email = 'thanhvien1@example.com'
union all select c.id, u.id, 'abuse'::report_reason, null from comments c, auth.users u where c.body like '[S5] Mua gói ngay%' and u.email = 'thanhvien2@example.com'
union all select c.id, u.id, 'spoiler'::report_reason, 'Đòi tiết lộ nội dung' from comments c, auth.users u where c.body like '[S5] Bạn nào xem rồi%' and u.email = 'thanhvien1@example.com'
on conflict do nothing;

-- 4. Đơn bất thường (story 24)
-- 701: đã thu tiền nhưng chưa có subscriptions
insert into orders(id, user_id, kind, plan_id, amount, provider, status, paid_at, provider_txn, created_at)
select '00000000-0000-0000-0000-000000000701', u.id, 'plan', p.id, p.price, 'mock', 'paid', now() - interval '2 hours', 'SEED-701', now() - interval '2 hours'
from auth.users u, plans p where u.email = 'thanhvien3@example.com' and p.name = 'Gói tuần thử nghiệm';
-- 702: chờ thanh toán quá lâu
insert into orders(id, user_id, kind, plan_id, amount, provider, status, created_at)
select '00000000-0000-0000-0000-000000000702', u.id, 'plan', p.id, p.price, 'mock', 'pending', now() - interval '3 hours'
from auth.users u, plans p where u.email = 'thanhvien1@example.com' and p.name = 'Gói tháng toàn bộ';
-- 703: cổng báo sai số tiền
insert into orders(id, user_id, kind, plan_id, amount, provider, status, provider_txn, fail_reason, created_at)
select '00000000-0000-0000-0000-000000000703', u.id, 'plan', p.id, p.price, 'mock', 'failed', 'SEED-703', 'Sai số tiền: cổng báo 10000, đơn ' || p.price, now() - interval '1 day'
from auth.users u, plans p where u.email = 'thanhvien2@example.com' and p.name = 'Gói tháng toàn bộ';
-- 704 + 705: mua lẻ trùng cùng một truyện
insert into orders(id, user_id, kind, story_id, amount, provider, status, paid_at, provider_txn, created_at)
select v.id::uuid, u.id, 'story', 104, 25000, 'mock', 'paid', v.at, v.txn, v.at
from auth.users u, (values ('00000000-0000-0000-0000-000000000704', now() - interval '5 days', 'SEED-704'),
                           ('00000000-0000-0000-0000-000000000705', now() - interval '4 days', 'SEED-705')) v(id, at, txn)
where u.email = 'thanhvien3@example.com';
insert into story_purchases(user_id, story_id, order_id)
select u.id, 104, '00000000-0000-0000-0000-000000000704' from auth.users u where u.email = 'thanhvien3@example.com' on conflict do nothing;

-- 5. Thông báo (story 39): đăng chương mới cho truyện 103 -> người theo dõi nhận thông báo (trigger chapters_notify)
insert into chapters(story_id, title) values (103, 'Chương mới (seed S5)');

-- 6. Kiểm tra nhanh (mong đợi: 2 bình luận chờ xử lý, 3 báo cáo, 4 loại bất thường trong 5 đơn seed, >=2 thông báo)
select (select count(distinct comment_id) from comment_reports where status = 'open') as binh_luan_cho_xu_ly,
       (select count(*) from comment_reports where status = 'open') as bao_cao,
       (select count(*) from orders where id::text like '00000000-0000-0000-0000-0000000007%' and order_issue(id) is not null) as don_bat_thuong,
       (select count(*) from notifications where chapter_title = 'Chương mới (seed S5)') as thong_bao;
