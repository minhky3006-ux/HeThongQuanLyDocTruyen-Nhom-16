-- DỮ LIỆU GIẢ CHO SPRINT 1. Chạy sau schema.sql trong Supabase SQL Editor. Chạy lại nhiều lần được (tự dọn bản cũ).
-- Tài khoản test (mật khẩu chung: Test@123456):
--   admin@example.com (admin) · tacgia1@example.com, tacgia2@example.com (tác giả) · thanhvien1..3@example.com (thành viên)
-- Truyện: 101-105 đã đăng (3 truyện chữ, 2 truyện tranh), 106 chờ duyệt, 201-225 là 25 truyện phụ để thử phân trang.
-- Bước 2 (sau khi upload ảnh test lên R2): chạy db/seed_test_images.sql để có ảnh bìa và trang truyện tranh.

-- 0. Dọn dữ liệu test cũ
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
with spec(sid,cnt) as (values (101,5),(102,4),(103,6),(104,2),(105,2),(106,2) union all select 200+g,1 from generate_series(1,25) g)
insert into chapters(story_id,number,title,content)
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
