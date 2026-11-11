-- Lệnh tiện dụng khi phát triển (chạy trong Supabase SQL Editor). Sprint 2 đã có trang admin (pages/admin) thay cho lệnh 2.
-- 1) Biến tài khoản của bạn thành admin (thay email):
update profiles set role='admin' where id=(select id from auth.users where email='email-cua-ban@gmail.com');
-- 2) Duyệt tất cả truyện đang chờ duyệt (story 16) để chúng hiện ra cho khách:
update stories set status='published' where status='pending';
-- 3) Xem nhanh dữ liệu:
select id,title,status,chapter_count,view_count from stories order by id desc;
-- 4) Cấp thử quyền đọc cho tài khoản của bạn (không qua thanh toán).
--    Cần đã có ít nhất 1 gói: tạo ở trang Quản trị > Gói đọc, hoặc chạy db/seed_test_ALL.sql.
insert into subscriptions(user_id, plan_id, starts_at, expires_at)
select (select id from auth.users where email='email-cua-ban@gmail.com'), (select id from plans where is_active order by id limit 1), now(), now() + interval '30 days';
-- 5) Xem các đơn thanh toán gần nhất:
select id, status, amount, provider, provider_txn, fail_reason, created_at from orders order by created_at desc limit 10;
