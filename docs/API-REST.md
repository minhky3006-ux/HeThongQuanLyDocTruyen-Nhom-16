# API REST dùng chung cho Web và Mobile

Web và ứng dụng mobile dùng **cùng một API**: REST của Supabase (PostgREST) + vài hàm RPC + 2 Edge Function. Mọi quyền truy cập do **RLS trong DB** quyết định, client chỉ hiển thị kết quả. Tên hàm trong `assets/js/api.js` (`API.xxx`) tương ứng với các yêu cầu bên dưới.

- Địa chỉ gốc: `https://<project>.supabase.co`. Mọi yêu cầu gửi header `apikey: <anon key>`; người đã đăng nhập thêm `Authorization: Bearer <access_token>` (khách dùng chính anon key làm Bearer).
- Phản hồi lỗi: JSON `{code, message, details, hint}` (vd. `42501` = không có quyền).
- Các ví dụ **REST/RPC** dưới đây đã chạy thử với PostgREST và DB của dự án (khách và người có gói cho kết quả đúng như mô tả). Phần **Auth** và **Edge Function** theo định dạng chuẩn của Supabase, chưa chạy trên project thật.

## 1. Tài khoản (Supabase Auth)
| Việc | Yêu cầu |
|---|---|
| Đăng ký | `POST /auth/v1/signup` body `{"email","password","data":{"display_name":"…"}}` |
| Đăng nhập | `POST /auth/v1/token?grant_type=password` body `{"email","password"}` → `access_token`, `refresh_token`, `user.id` |
| Làm mới phiên | `POST /auth/v1/token?grant_type=refresh_token` body `{"refresh_token"}` |
| Đăng xuất | `POST /auth/v1/logout` (Bearer) |
| Hồ sơ của tôi | `GET /rest/v1/profiles?id=eq.<user.id>&select=*` |

## 2. Duyệt và đọc (khách và thành viên)
| Việc | Yêu cầu (ví dụ) |
|---|---|
| Danh sách truyện mới cập nhật | `GET /rest/v1/stories?select=id,title,cover_key,access_policy,price,view_count,rating_avg,profiles!author_id(display_name)&status=eq.published&order=updated_at.desc&limit=20&offset=0` (thêm `Prefer: count=exact` để lấy tổng ở header `Content-Range`) |
| Sắp xếp khác | `order=published_at.desc` (mới phát hành), `order=view_count.desc` (đọc nhiều), `order=rating_avg.desc` |
| Tìm theo tên | thêm `&title=ilike.*từ khóa*` |
| Lọc thể loại | `…&select=…,story_genres!inner(genre_id)&story_genres.genre_id=eq.3` |
| Chi tiết truyện | `GET /rest/v1/stories?select=*,profiles!author_id(display_name),story_genres(genres(id,name))&id=eq.102` với header `Accept: application/vnd.pgrst.object+json` |
| Danh sách chương (kèm nhãn trả phí) | `GET /rest/v1/chapters?select=id,number,title,is_free_preview,publish_at&story_id=eq.102&order=number` — khách vẫn thấy chương trả phí; chương hẹn giờ chưa tới hạn không có trong kết quả |
| **Đọc chương** | `GET /rest/v1/chapters?select=id,number,title,chapter_contents(content),chapter_pages(page_no,image_key)&story_id=eq.102&number=eq.1`. Chưa có quyền: `chapter_contents` là `null`, `chapter_pages` là `[]` |
| Có đọc được chương không | `POST /rest/v1/rpc/can_read_chapter` `{"p_chapter":6}` → `true/false` |
| Quyền của tôi với truyện | `POST /rest/v1/rpc/story_access_info` `{"p_story":102}` → `{"purchased":bool,"subscription":{"plan_name","expires_at"}|null}` |
| Ảnh truyện tranh / bìa | `GET <IMG_BASE>/<image_key>` (`IMG_BASE` trong `assets/js/config.js`, CDN của R2) |
| Ghi nhận lượt đọc | `POST /rest/v1/rpc/track_view` `{"p_story":102,"p_chapter":6}` — gọi sau ~8 giây còn mở chương; chỉ tính khi đọc được |
| Lưu tiến độ đọc | xem `API.saveHistory` (bảng `reading_history`) |
| Bình luận / thảo luận chương | `GET /rest/v1/comments?select=id,body,created_at,profiles!user_id(display_name)&chapter_id=eq.6&is_hidden=eq.false&order=created_at.desc` · ghi: `POST /rest/v1/comments` `{"story_id","chapter_id","user_id","body"}` |
| Báo cáo bình luận | `POST /rest/v1/comment_reports` `{"comment_id","reporter_id","reason":"spam|abuse|spoiler|other","note"}` |
| Thông báo | `GET /rest/v1/notifications?order=created_at.desc` · đánh dấu đọc: `PATCH /rest/v1/notifications?read_at=is.null` `{"read_at":"<ISO>"}` |

## 3. Mua quyền đọc
| Việc | Yêu cầu |
|---|---|
| Gói đang bán | `GET /rest/v1/plans?select=id,name,price,duration_days,scope&is_active=eq.true&order=price` |
| **Tạo đơn mua gói** | `POST /functions/v1/create-payment` (Bearer) `{"kind":"plan","planId":9}` → `{"orderId","payUrl"}` |
| **Tạo đơn mua lẻ** | `POST /functions/v1/create-payment` `{"kind":"story","storyId":102}` → `{"orderId","payUrl"}`; `409` nếu đã có quyền, `400` nếu truyện không bán lẻ |
| Thanh toán | mở `payUrl` (trình duyệt trong ứng dụng); cổng gọi `payment-webhook` về máy chủ, **không** gọi từ client |
| Kết quả đơn | `GET /rest/v1/orders?id=eq.<orderId>&select=id,status,amount,fail_reason,plans(name),stories(title)` – hỏi lại mỗi ~3 giây tới khi `status` khác `pending` (`paid`/`failed`/`cancelled`) |
| Gói đang dùng | `GET /rest/v1/subscriptions?select=starts_at,expires_at,plans(name)&order=expires_at.desc` |
| Truyện đã mua | `GET /rest/v1/story_purchases?select=created_at,stories(id,title,cover_key)` |
| Lịch sử thanh toán | `GET /rest/v1/orders?select=id,status,kind,amount,created_at,plans(name),stories(title)&order=created_at.desc` |

**Ghi chú an toàn:** client **không ghi** được `orders`, `subscriptions`, `story_purchases` (trả `403 permission denied`, đã thử); giá luôn lấy từ DB ở máy chủ; không bao giờ coi tham số trên URL quay về từ cổng là kết quả thanh toán.

## 4. Quản trị (chỉ vai trò admin, thành viên gọi sẽ bị từ chối)
RPC: `admin_set_story_access`, `admin_set_story_price`, `admin_report_queue`, `admin_handle_reports`, `admin_restrict_user`, `admin_set_locked`, `admin_orders_list`, `admin_order_summary`, `admin_fix_order`, `admin_member_stats`, `admin_revenue_plans`, `admin_revenue_stories`, `admin_content_stats` — tham số xem đầu mỗi hàm trong `db/migrations/*.sql` và các hàm `API.admin*` tương ứng.
