-- DỮ LIỆU GIẢ CHO SPRINT 4. Chạy SAU migrations 002, 003 và seed_test_sprint1.sql + seed_test_sprint3.sql. Chạy lại nhiều lần được.
-- Kịch bản thử (mật khẩu Test@123456):
--   Giá bán lẻ: 102 = 39.000₫ · 103 = 25.000₫ · 104 chưa đặt giá (chỉ đọc được bằng gói)
--   thanhvien1: chưa có gì -> thử mua lẻ 102 (mock gateway), rồi thử mua lại (phải bị chặn), mua gói rồi gia hạn
--   thanhvien2: có "Gói tháng toàn bộ" (seed Sprint 3) -> vào truyện 102 thấy "đọc được nhờ gói", KHÔNG có nút mua; mua lẻ 102 bị từ chối (409)
--   Truyện 101 có chương hẹn giờ (tác giả tacgia1 thấy, khách chưa thấy); truyện 105 đã Hoàn thành, 106 Tạm ngưng

-- 1. Giá bán lẻ (story 22) kèm nhật ký đổi giá
update stories set price = 39000 where id = 102;
update stories set price = 25000 where id = 103;
update stories set price = null  where id = 104;

-- 2. Tiến độ truyện (story 20)
update stories set progress = 'ongoing'   where id in (101, 102, 103, 104);
update stories set progress = 'completed' where id = 105;
update stories set progress = 'paused'    where id = 106;

-- 3. Chương hẹn giờ cho truyện 101: hẹn 3 ngày nữa, độc giả chưa thấy
with old as (delete from chapters where story_id = 101 and title = 'Chương hẹn giờ (seed S4)' returning 1),
ins as (insert into chapters(story_id, title, publish_at) values (101, 'Chương hẹn giờ (seed S4)', now() + interval '3 days') returning id)
insert into chapter_contents(chapter_id, content) select id, E'Chương này được hẹn giờ phát hành.\n\nĐộc giả chỉ đọc được khi tới giờ.' from ins;
select release_due_chapters();

-- 4. Làm sạch giao dịch thử của thanhvien1 để chạy lại kịch bản mua
delete from story_purchases where user_id = (select id from auth.users where email = 'thanhvien1@example.com');
delete from subscriptions  where user_id = (select id from auth.users where email = 'thanhvien1@example.com');
delete from orders         where user_id = (select id from auth.users where email = 'thanhvien1@example.com');

-- 5. Kiểm tra nhanh (mong đợi: 2 truyện có giá, 1 chương hẹn giờ, 1 hoàn thành, 1 tạm ngưng)
select (select count(*) from stories where price is not null) as truyen_co_gia,
       (select count(*) from chapters where publish_at > now()) as chuong_hen_gio,
       (select count(*) from stories where progress = 'completed') as hoan_thanh,
       (select count(*) from stories where progress = 'paused') as tam_ngung;
