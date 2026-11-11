-- DỮ LIỆU THỬ GỘP. Chạy SAU db/schema.sql và db/migrations/ALL_sprint3-6.sql; chạy lại nhiều lần được.
-- CHỈ DÙNG CHO MÔI TRƯỜNG THỬ: tạo lại 6 tài khoản test @example.com (mật khẩu Test@123456) cùng truyện, đơn hàng thử.
-- Ảnh truyện tranh mẫu (tùy chọn): db/seed_test_images.sql.

-- ======================================================================================================
-- PHẦN 1/5 · Tài khoản test, truyện, chương, bình luận (tự dọn bản cũ khi chạy lại)
-- Tài khoản test (mật khẩu chung: Test@123456):
--   admin@example.com (admin) · tacgia1@example.com, tacgia2@example.com (tác giả) · thanhvien1..3@example.com (thành viên)
-- Truyện: 101-105 đã đăng (3 truyện chữ, 2 truyện tranh), 106 chờ duyệt, 201-225 là 25 truyện phụ để thử phân trang.
-- Bước 2 (sau khi upload ảnh test lên R2): chạy db/seed_test_images.sql để có ảnh bìa và trang truyện tranh.

-- 0. Dọn dữ liệu test cũ
-- Đơn hàng / gói / quyền sở hữu của tài khoản test tham chiếu tới truyện và tài khoản, phải xóa trước
delete from story_purchases where user_id in (select id from auth.users where email like '%@example.com');
delete from subscriptions   where user_id in (select id from auth.users where email like '%@example.com');
delete from orders          where user_id in (select id from auth.users where email like '%@example.com');
delete from stories where id between 101 and 106 or id between 201 and 225
   or author_id in (select id from auth.users where email in ('admin@example.com','tacgia1@example.com','tacgia2@example.com','thanhvien1@example.com','thanhvien2@example.com','thanhvien3@example.com'));
delete from auth.users where email in ('admin@example.com','tacgia1@example.com','tacgia2@example.com','thanhvien1@example.com','thanhvien2@example.com','thanhvien3@example.com');   -- kéo theo profiles, theo dõi, bình luận, đánh giá, lịch sử

-- 1. Tài khoản
create temp table _u(idx int, email text, name text, role user_role, id uuid default gen_random_uuid());
insert into _u(idx,email,name,role) values
 (1,'admin@example.com','Quản Trị Viên','admin'),(2,'tacgia1@example.com','Mai An','author'),(3,'tacgia2@example.com','Trần Phong','author'),
 (4,'thanhvien1@example.com','Lê Hạ','member'),(5,'thanhvien2@example.com','Ngọc Linh','member'),(6,'thanhvien3@example.com','Hoàng Nam','member');
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,
  confirmation_token,recovery_token,email_change,email_change_token_new)
select '00000000-0000-0000-0000-000000000000',id,'authenticated','authenticated',email,extensions.crypt('Test@123456',extensions.gen_salt('bf')),now(),
  '{"provider":"email","providers":["email"]}'::jsonb,jsonb_build_object('display_name',name),now(),now(),'','','','' from _u;
insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
select gen_random_uuid(),id,id::text,jsonb_build_object('sub',id::text,'email',email,'email_verified',true),'email',now(),now(),now() from _u;
update profiles p set role=u.role from _u u where p.id=u.id;   -- profiles được tạo tự động bởi trigger khi thêm user

-- 2. Thể loại
insert into genres(name,slug) values ('Phiêu lưu','phieu-luu'),('Fantasy','fantasy'),('Đời thường','doi-thuong'),('Tình cảm','tinh-cam'),
 ('Kiếm hiệp','kiem-hiep'),('Học đường','hoc-duong'),('Trinh thám','trinh-tham') on conflict do nothing;

-- 3. Truyện (id cố định để khớp tên file ảnh)
insert into stories(id,author_id,title,description,kind,status) overriding system value
select v.id,(select id from _u where idx=v.a),v.t,v.d,v.k::story_kind,v.s::story_status from (values
 (101,2,'Rừng Xanh Thức Giấc','Cô gái nhỏ nghe được tiếng nói của cây cối và bắt đầu hành trình tìm lại ngôi làng đã biến mất.','text','published'),
 (102,2,'Quán Trà Cuối Phố','Chuyện những vị khách quen và tách trà chiều ở một quán nhỏ cuối con phố cũ.','text','published'),
 (103,3,'Kiếm Khách Vô Danh','Một kiếm khách giấu tên rời núi, mang theo thanh kiếm gãy và một lời hứa.','text','published'),
 (104,3,'Học Viện Ánh Trăng','Năm nhất ở học viện phép thuật, nơi mọi bí mật đều nằm trong thư viện.','comic','published'),
 (105,2,'Thành Phố Không Ngủ','Vụ án đầu tiên của thám tử trẻ diễn ra đúng đêm mất điện toàn thành phố.','comic','published'),
 (106,3,'Bản Thảo Chưa Duyệt','Truyện đang chờ quản trị viên duyệt, khách không được thấy truyện này.','text','pending')) v(id,a,t,d,k,s);
insert into stories(id,author_id,title,description,kind,status) overriding system value
select 200+g,(select id from _u where idx=2+(g%2)),'Truyện thử nghiệm số '||g,'Truyện mẫu để thử phân trang, tìm kiếm và sắp xếp.','text','published' from generate_series(1,25) g;
insert into story_genres(story_id,genre_id)
select v.s,g.id from (values (101,'phieu-luu'),(101,'fantasy'),(102,'doi-thuong'),(102,'tinh-cam'),(103,'kiem-hiep'),(104,'hoc-duong'),(104,'fantasy'),
 (105,'trinh-tham'),(106,'fantasy')) v(s,slug) join genres g on g.slug=v.slug;
insert into story_genres(story_id,genre_id) select 200+g,(select id from genres order by id offset (g%7) limit 1) from generate_series(1,25) g;

-- 4. Chương (truyện chữ có nội dung; truyện tranh chỉ có tiêu đề, ảnh thêm ở bước 2)
create temp table _ch(sid,n,title,content) as
with spec(sid,cnt) as (values (101,5),(102,4),(103,6),(104,2),(105,2),(106,2) union all select 200+g,1 from generate_series(1,25) g)
select s.id,n,(array['Khởi đầu','Cuộc gặp gỡ','Bí mật','Con đường phía trước','Thử thách','Hồi kết'])[n],
 case when s.kind='text' then (select string_agg(p,E'\n\n' order by k) from (select k,(array[
  'Buổi sáng, sương còn đọng trên những tán lá, và cả khu rừng như đang khẽ thở.',
  'Cô bước chậm rãi trên con đường mòn quen thuộc, lòng nặng trĩu những câu hỏi chưa có lời đáp.',
  'Một tiếng động lạ vang lên phía sau, khiến cả nhóm đồng loạt dừng lại và nín thở lắng nghe.',
  'Người lữ khách mỉm cười, đặt chén trà xuống bàn rồi bắt đầu kể một câu chuyện đã cũ.',
  'Ánh đèn đường hắt lên mặt nước, vẽ nên những vệt sáng vàng dài và run rẩy.',
  'Anh nhớ lại lời hứa năm nào, và hiểu rằng có những điều chỉ có thể giữ bằng hành động.',
  'Gió thổi qua hành lang vắng, mang theo mùi giấy cũ và một chút hương hoa sữa muộn.',
  'Họ nhìn nhau, không ai nói gì, nhưng cả hai đều biết mọi chuyện sẽ không còn như trước.',
  'Tiếng chuông từ ngọn tháp xa ngân lên ba hồi, báo hiệu một ngày mới đã bắt đầu.',
  'Cuối cùng, sau bao nhiêu thử thách, họ cũng tìm thấy lối ra mà mình đã kiếm tìm.'])[1+((s.id+n+k)%10)] p
  from generate_series(1,5) k) q) end
from spec join stories s on s.id=spec.sid, generate_series(1,spec.cnt) n;
-- Từ migration 002, nội dung chương nằm ở bảng chapter_contents (chapters không còn cột content)
insert into chapters(story_id,number,title) select sid,n,title from _ch;
insert into chapter_contents(chapter_id,content)
select c.id,x.content from _ch x join chapters c on c.story_id=x.sid and c.number=x.n where x.content is not null;

-- 5. Số liệu mô phỏng
update stories set view_count=case id when 101 then 12400 when 102 then 8900 when 103 then 20100 when 104 then 6700 when 105 then 5400 else (id*37)%900 end,
  updated_at=now()-((id*7)%20)*interval '1 day' where id between 101 and 106 or id between 201 and 225;
update stories set created_at=updated_at-interval '30 days' where id between 101 and 106 or id between 201 and 225;
insert into story_views_daily(story_id,day,views) select s,current_date-d,20+((s*d*13)%80) from generate_series(101,105) s, generate_series(0,6) d;
insert into ratings(user_id,story_id,score) select u.id,s,3+((u.idx+s)%3) from _u u, generate_series(101,105) s where u.idx>=4;
insert into follows(user_id,story_id) select (select id from _u where idx=v.u),v.s from (values (4,101),(4,103),(5,101),(6,102)) v(u,s);
insert into reading_history(user_id,story_id,chapter_id,page_no)
select (select id from _u where idx=4),101,(select id from chapters where story_id=101 and number=3),0;
insert into comments(story_id,user_id,body,is_hidden,created_at)
select v.s,(select id from _u where idx=v.u),v.b,v.h,now()-v.m*interval '1 hour' from (values
 (101,4,'Truyện hay quá, mong tác giả ra chương mới sớm!',false,5),(101,5,'Mở đầu cuốn hút, tả cảnh rừng rất đẹp.',false,30),
 (101,6,'Bình luận vi phạm, dùng để thử chức năng ẩn bình luận.',true,48),(102,4,'Đọc xong thấy lòng nhẹ hẳn, cảm ơn tác giả.',false,12),
 (103,5,'Cảnh đấu kiếm ở chương 3 rất đã mắt.',false,20)) v(s,u,b,h,m);

-- 6. Đặt lại bộ đếm id để truyện thật sau này không trùng id test
select setval(pg_get_serial_sequence('public.stories','id'), greatest((select max(id) from stories),300));

-- 7. Kiểm tra nhanh (kết quả mong đợi: 6 tài khoản, 30 đã đăng + 1 chờ duyệt, 5+4+6+2+2+2+25=46 chương)
select (select count(*) from profiles where id in (select id from _u)) as tai_khoan,
       (select count(*) from stories where status='published' and (id between 101 and 106 or id between 201 and 225)) as truyen_da_dang,
       (select count(*) from stories where status='pending' and id=106) as cho_duyet,
       (select count(*) from chapters where story_id between 101 and 106 or story_id between 201 and 225) as chuong;

-- ======================================================================================================
-- PHẦN 2/5 · Chính sách truy cập, gói đọc, quyền sở hữu mẫu
-- Kịch bản thử (dùng tài khoản test ở phần 1, mật khẩu Test@123456):
--   101 Rừng Xanh Thức Giấc  : free   -> ai cũng đọc được
--   102 Quán Trà Cuối Phố    : paid   -> chỉ người có quyền đọc được (thanhvien2 có gói "Gói tháng toàn bộ")
--   103 Kiếm Khách Vô Danh   : mixed  -> chương 1-2 đọc thử, chương 3 trở đi trả phí
--   104 Học Viện Ánh Trăng   : paid, truyện tranh -> thử khóa ảnh
--   thanhvien1: không có quyền gì · thanhvien3: gói đã HẾT HẠN (phải bị khóa như người không có gói)

-- 1. Chính sách truy cập
update stories set access_policy='free'  where id = 101;
update stories set access_policy='paid'  where id in (102, 104);
update stories set access_policy='mixed' where id = 103;
update chapters set is_free_preview = (story_id = 103 and number <= 2) where story_id in (101,102,103,104);

-- 2. Gói đọc: xóa gói test cũ rồi tạo lại (xóa thuê bao test trước vì có khóa ngoại)
delete from subscriptions where user_id in (select id from auth.users where email in ('thanhvien2@example.com','thanhvien3@example.com'));
delete from plans where name in ('Gói tháng toàn bộ','Gói tuần thử nghiệm','Gói chọn lọc','Gói ngừng bán');
insert into plans(name, description, price, duration_days, scope, is_active) values
 ('Gói tháng toàn bộ',  'Đọc mọi truyện trả phí trong 30 ngày', 59000, 30, 'all',      true),
 ('Gói tuần thử nghiệm','Dùng thử 7 ngày, đọc mọi truyện trả phí', 19000, 7,  'all',      true),
 ('Gói chọn lọc',       'Chỉ gồm truyện Kiếm Khách Vô Danh',     29000, 30, 'selected', true),
 ('Gói ngừng bán',      'Đã ngừng cung cấp (kiểm tra ẩn khỏi khách)', 39000, 30, 'all',  false);
insert into plan_stories(plan_id, story_id) select id, 103 from plans where name = 'Gói chọn lọc';

-- 3. Quyền sở hữu mẫu (dữ liệu để thử quyền đọc; thực tế do luồng mua tạo)
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

-- ======================================================================================================
-- PHẦN 3/5 · Giá bán lẻ, tiến độ truyện, chương hẹn giờ
-- Kịch bản thử (mật khẩu Test@123456):
--   Giá bán lẻ: 102 = 39.000₫ · 103 = 25.000₫ · 104 chưa đặt giá (chỉ đọc được bằng gói)
--   thanhvien1: chưa có gì -> thử mua lẻ 102 (mock gateway), rồi thử mua lại (phải bị chặn), mua gói rồi gia hạn
--   thanhvien2: có "Gói tháng toàn bộ" (phần 2) -> vào truyện 102 thấy "đọc được nhờ gói", KHÔNG có nút mua; mua lẻ 102 bị từ chối (409)
--   Truyện 101 có chương hẹn giờ (tác giả tacgia1 thấy, khách chưa thấy); truyện 105 đã Hoàn thành, 106 Tạm ngưng

-- 1. Giá bán lẻ kèm nhật ký đổi giá
update stories set price = 39000 where id = 102;
update stories set price = 25000 where id = 103;
update stories set price = null  where id = 104;

-- 2. Tiến độ truyện
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

-- ======================================================================================================
-- PHẦN 4/5 · Báo cáo, thông báo, đơn bất thường, thảo luận chương
-- Kịch bản thử (mật khẩu Test@123456):
--   Báo cáo: admin vào Quản trị › Báo cáo thấy 2 bình luận chờ xử lý (1 bình luận bị 2 báo cáo)
--   Thông báo: thanhvien1, thanhvien2 theo dõi truyện 101 và 103 -> đăng nhập thấy chuông có thông báo chương mới
--   Đối soát: admin vào Quản trị › Giao dịch thấy 4 đơn bất thường (đã thu tiền chưa cấp quyền, chờ quá lâu, sai số tiền, mua lẻ trùng)
--   Thảo luận chương: chương 1 truyện 101 (miễn phí) và chương 1 truyện 102 (chỉ người có gói thấy) đã có thảo luận
--   Thống kê: Quản trị › Thống kê thành viên

-- 0. Dọn dữ liệu thử của seed này
delete from comments where body like '[S5]%';
delete from story_purchases where user_id = (select id from auth.users where email = 'thanhvien3@example.com') and story_id = 104;
delete from orders where id::text like '00000000-0000-0000-0000-0000000007%';
delete from chapters where story_id = 103 and title = 'Chương mới (seed S5)';
delete from user_restrictions;

-- 1. Theo dõi
insert into follows(user_id, story_id)
select u.id, s from auth.users u, (values (101), (103)) v(s)
where u.email in ('thanhvien1@example.com', 'thanhvien2@example.com') on conflict do nothing;

-- 2. Thảo luận theo chương và bình luận cấp truyện
insert into comments(story_id, chapter_id, user_id, body)
select 101, (select id from chapters where story_id = 101 and number = 1), (select id from auth.users where email = 'thanhvien1@example.com'), '[S5] Chương đầu mở đầu rất cuốn!'
union all select 101, (select id from chapters where story_id = 101 and number = 1), (select id from auth.users where email = 'thanhvien3@example.com'), '[S5] Mua gói ngay tại link này nhé, giảm 90%!!!'
union all select 102, (select id from chapters where story_id = 102 and number = 1), (select id from auth.users where email = 'thanhvien2@example.com'), '[S5] Chương trả phí này đáng tiền.'
union all select 101, null, (select id from auth.users where email = 'thanhvien3@example.com'), '[S5] Bạn nào xem rồi thì spoil giùm kết truyện đi';

-- 3. Báo cáo: 2 người báo cáo bình luận quảng cáo; 1 người báo cáo bình luận đòi spoil
insert into comment_reports(comment_id, reporter_id, reason, note)
select c.id, u.id, 'spam'::report_reason, 'Quảng cáo rõ ràng' from comments c, auth.users u
where c.body like '[S5] Mua gói ngay%' and u.email = 'thanhvien1@example.com'
union all select c.id, u.id, 'abuse'::report_reason, null from comments c, auth.users u where c.body like '[S5] Mua gói ngay%' and u.email = 'thanhvien2@example.com'
union all select c.id, u.id, 'spoiler'::report_reason, 'Đòi tiết lộ nội dung' from comments c, auth.users u where c.body like '[S5] Bạn nào xem rồi%' and u.email = 'thanhvien1@example.com'
on conflict do nothing;

-- 4. Đơn bất thường
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

-- 5. Thông báo: đăng chương mới cho truyện 103 -> người theo dõi nhận thông báo (trigger chapters_notify)
insert into chapters(story_id, title) values (103, 'Chương mới (seed S5)');

-- 6. Kiểm tra nhanh (mong đợi: 2 bình luận chờ xử lý, 3 báo cáo, 4 loại bất thường trong 5 đơn seed, >=2 thông báo)
select (select count(distinct comment_id) from comment_reports where status = 'open') as binh_luan_cho_xu_ly,
       (select count(*) from comment_reports where status = 'open') as bao_cao,
       (select count(*) from orders where id::text like '00000000-0000-0000-0000-0000000007%' and order_issue(id) is not null) as don_bat_thuong,
       (select count(*) from notifications where chapter_title = 'Chương mới (seed S5)') as thong_bao;

-- ======================================================================================================
-- PHẦN 5/5 · Dữ liệu thống kê 60 ngày (doanh thu, lượt xem)
-- Tạo ~60 ngày dữ liệu: đơn mua gói và mua lẻ đã thanh toán, lượt xem truyện/chương theo ngày, thêm người theo dõi và thảo luận chương.
-- Các đơn doanh thu này được đánh dấu "bỏ qua" trong nhật ký đối soát để KHÔNG hiện là bất thường ở trang Giao dịch.

delete from orders where id::text like '00000000-0000-0000-0000-0000000008%';

-- 1. Đơn mua gói: 24 đơn rải trong 60 ngày, 3 người, luân phiên 3 gói đang bán
insert into orders(id, user_id, kind, plan_id, amount, provider, status, paid_at, provider_txn, created_at)
select ('00000000-0000-0000-0000-0000000008' || lpad(i::text, 2, '0'))::uuid,
       (select id from auth.users where email = 'thanhvien' || (1 + i % 3) || '@example.com'),
       'plan', p.id, p.price, 'mock', 'paid',
       now() - make_interval(hours => (i * 59) % 1440), 'S6-PLAN-' || i,
       now() - make_interval(hours => (i * 59) % 1440)
from generate_series(1, 24) i
join lateral (select id, price from plans where name in ('Gói tháng toàn bộ', 'Gói tuần thử nghiệm', 'Gói chọn lọc') order by name offset (i % 3) limit 1) p on true;

-- 2. Đơn mua lẻ: 15 đơn cho truyện 102, 103, 104 (giá chốt tại thời điểm mua)
insert into orders(id, user_id, kind, story_id, amount, provider, status, paid_at, provider_txn, created_at)
select ('00000000-0000-0000-0000-0000000008' || lpad((50 + i)::text, 2, '0'))::uuid,
       (select id from auth.users where email = 'thanhvien' || (1 + i % 3) || '@example.com'),
       'story', 102 + i % 3, case 102 + i % 3 when 102 then 39000 when 103 then 25000 else 29000 end, 'mock', 'paid',
       now() - make_interval(hours => (i * 97) % 1440), 'S6-STORY-' || i,
       now() - make_interval(hours => (i * 97) % 1440)
from generate_series(1, 15) i;

insert into order_audit(order_id, action, note)
select id, 'ignore', 'Dữ liệu thống kê giả (seed thống kê)' from orders where id::text like '00000000-0000-0000-0000-0000000008%';

-- 3. Lượt xem theo ngày: 30 ngày gần nhất cho truyện 101–106
insert into story_views_daily(story_id, day, views)
select s, (now() at time zone 'Asia/Ho_Chi_Minh')::date - d, 5 + ((s * 7 + d * 3) % 25)
from generate_series(101, 106) s, generate_series(0, 29) d
on conflict (story_id, day) do update set views = excluded.views;
insert into chapter_views_daily(chapter_id, day, views)
select c.id, (now() at time zone 'Asia/Ho_Chi_Minh')::date - d, 1 + ((c.id::int * 5 + d * 2) % (9 - least(c.number, 6)))
from chapters c, generate_series(0, 29) d where c.story_id between 101 and 106 and c.number <= 4
on conflict (chapter_id, day) do update set views = excluded.views;

-- 4. Thêm người theo dõi và thảo luận chương
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
