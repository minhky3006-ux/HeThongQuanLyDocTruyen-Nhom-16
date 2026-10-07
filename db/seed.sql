-- Chạy SAU schema.sql. Thể loại + 5 truyện mẫu (cần đã có ít nhất 1 tài khoản đăng ký).
insert into genres(name,slug) values ('Phiêu lưu','phieu-luu'),('Fantasy','fantasy'),('Đời thường','doi-thuong'),
 ('Tình cảm','tinh-cam'),('Kiếm hiệp','kiem-hiep'),('Học đường','hoc-duong'),('Trinh thám','trinh-tham') on conflict do nothing;
insert into stories(author_id,title,description,kind,status)
select (select id from profiles order by created_at limit 1), t, d, 'text', 'published' from (values
 ('Rừng Xanh Thức Giấc','Cô gái nhỏ nghe được tiếng nói của cây cối và bắt đầu hành trình tìm lại ngôi làng đã biến mất.'),
 ('Quán Trà Cuối Phố','Chuyện những vị khách quen và tách trà chiều ở một quán nhỏ cuối con phố cũ.'),
 ('Kiếm Khách Vô Danh','Một kiếm khách giấu tên rời núi, mang theo thanh kiếm gãy và một lời hứa.'),
 ('Học Viện Ánh Trăng','Năm nhất ở học viện phép thuật, nơi mọi bí mật đều nằm trong thư viện.'),
 ('Thành Phố Không Ngủ','Vụ án đầu tiên của thám tử trẻ diễn ra đúng đêm mất điện toàn thành phố.')) v(t,d);
