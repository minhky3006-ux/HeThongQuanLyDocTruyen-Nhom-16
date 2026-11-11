-- DỮ LIỆU GIẢ CHO SPRINT 3. Chạy SAU schema.sql + migrations/002 + seed_test_sprint1.sql. Chạy lại nhiều lần được.
-- Kịch bản thử (dùng tài khoản test ở seed_test_sprint1.sql, mật khẩu Test@123456):
--   101 Rừng Xanh Thức Giấc  : free   -> ai cũng đọc được
--   102 Quán Trà Cuối Phố    : paid   -> chỉ người có quyền đọc được (thanhvien2 có gói "Gói tháng toàn bộ")
--   103 Kiếm Khách Vô Danh   : mixed  -> chương 1-2 đọc thử, chương 3 trở đi trả phí
--   104 Học Viện Ánh Trăng   : paid, truyện tranh -> thử khóa ảnh
--   thanhvien1: không có quyền gì · thanhvien3: gói đã HẾT HẠN (phải bị khóa như người không có gói)

-- 1. Chính sách truy cập (US 19)
update stories set access_policy='free'  where id = 101;
update stories set access_policy='paid'  where id in (102, 104);
update stories set access_policy='mixed' where id = 103;
update chapters set is_free_preview = (story_id = 103 and number <= 2) where story_id in (101,102,103,104);

-- 2. Gói đọc (US 21): xóa gói test cũ rồi tạo lại (xóa thuê bao test trước vì có khóa ngoại)
delete from subscriptions where user_id in (select id from auth.users where email in ('thanhvien2@example.com','thanhvien3@example.com'));
delete from plans where name in ('Gói tháng toàn bộ','Gói tuần thử nghiệm','Gói chọn lọc','Gói ngừng bán');
insert into plans(name, description, price, duration_days, scope, is_active) values
 ('Gói tháng toàn bộ',  'Đọc mọi truyện trả phí trong 30 ngày', 59000, 30, 'all',      true),
 ('Gói tuần thử nghiệm','Dùng thử 7 ngày, đọc mọi truyện trả phí', 19000, 7,  'all',      true),
 ('Gói chọn lọc',       'Chỉ gồm truyện Kiếm Khách Vô Danh',     29000, 30, 'selected', true),
 ('Gói ngừng bán',      'Đã ngừng cung cấp (kiểm tra ẩn khỏi khách)', 39000, 30, 'all',  false);
insert into plan_stories(plan_id, story_id) select id, 103 from plans where name = 'Gói chọn lọc';

-- 3. Quyền sở hữu mẫu (US 31 cần dữ liệu này để thử; Sprint 4 sẽ do luồng mua tự tạo)
insert into subscriptions(user_id, plan_id, starts_at, expires_at)
select u.id, (select id from plans where name='Gói tháng toàn bộ'), now() - interval '2 days', now() + interval '28 days'
from auth.users u where u.email = 'thanhvien2@example.com';
insert into subscriptions(user_id, plan_id, starts_at, expires_at)
select u.id, (select id from plans where name='Gói tháng toàn bộ'), now() - interval '45 days', now() - interval '15 days'
from auth.users u where u.email = 'thanhvien3@example.com';

-- 4. Kiểm tra nhanh (mong đợi: 3 truyện trả phí/kết hợp, 2 chương đọc thử, 3 gói đang bán, 2 gói thuê bao)
select (select count(*) from stories where access_policy <> 'free') as truyen_tra_phi,
       (select count(*) from chapters where is_free_preview) as chuong_doc_thu,
       (select count(*) from plans where is_active) as goi_dang_ban,
       (select count(*) from subscriptions) as thue_bao;
