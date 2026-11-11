# Ứng dụng mobile TruyệnXanh (Sprint 6, story 41)

Vỏ ứng dụng **Android / iOS** làm bằng [Capacitor](https://capacitorjs.com). Ứng dụng mở **đúng bản web đã triển khai** trong một WebView, nên:
- đăng nhập, duyệt truyện, đọc chương, mua gói / mua lẻ, thông báo… dùng **chung 100% giao diện, API (Supabase REST + Edge Function) và tài khoản** với web;
- sửa web xong là ứng dụng cập nhật theo, không phải build lại;
- phiên đăng nhập, giao diện thanh toán và địa chỉ quay về sau khi thanh toán đều ở cùng một địa chỉ web nên **không bị mất đăng nhập** khi sang cổng thanh toán rồi quay lại.

Ngoài ra bản web cài được như ứng dụng (PWA: `manifest.json` + `sw.js`) bằng "Thêm vào màn hình chính", không cần cài gì thêm.

> **Trạng thái:** cấu hình đã được kiểm tra bằng Capacitor thật (`cap add android`, `cap sync` chạy được, cấu hình được chép vào dự án Android). **Chưa build APK và chưa chạy trên máy/giả lập** (môi trường tạo khung không có Android SDK). Cần thử trên thiết bị thật trước khi báo cáo.

## Cần có
- Node.js 18+; Android Studio (JDK 17+) để build Android; **máy macOS + Xcode** để build iOS.
- Web đã triển khai bằng **HTTPS** (GitHub Pages, Netlify…) và đã chạy đúng `SITE_URL` cho hàm thanh toán (xem `db/README.md`).

## Đóng gói APK (Windows / macOS / Linux)
**Chuẩn bị một lần:** cài [Node.js 18+](https://nodejs.org) và [Android Studio](https://developer.android.com/studio) (đi kèm JDK và Android SDK). Mở Android Studio một lần để nó tải SDK. Web phải **đã chạy trên HTTPS** tại `https://truyenxanhvn.com/` vì ứng dụng mở đúng địa chỉ này.

```bash
cd mobile
npm install
npm run set-url -- https://truyenxanhvn.com/   # bỏ qua nếu đã đúng (đã đặt sẵn)
npx cap add android                            # chỉ chạy lần đầu, tạo thư mục android/
npm run icons                                  # tạo biểu tượng + màn hình chờ từ thư mục assets/
npm run apk                                    # build APK debug
```
APK nằm ở `mobile/android/app/build/outputs/apk/debug/app-debug.apk`. Chép sang điện thoại, mở file và cho phép "Cài đặt từ nguồn không xác định". Muốn thử nhanh trên điện thoại cắm cáp: bật Gỡ lỗi USB rồi `npx cap run android`.

Nếu `npm run apk` báo thiếu `JAVA_HOME` hoặc `ANDROID_HOME`: dùng JDK đi kèm Android Studio (thư mục `jbr`) và đặt `ANDROID_HOME` là thư mục SDK (thường `%LOCALAPPDATA%\Android\Sdk` trên Windows). Hoặc mở bằng Android Studio (`npm run android`) rồi chọn **Build > Build APK(s)**.

### APK bản phát hành (để gửi cho người dùng thật)
APK debug dùng khóa thử, chỉ để thử máy. Bản phát hành cần **ký bằng khóa của bạn**:
1. Tạo khóa một lần (**giữ file và mật khẩu cẩn thận, mất là không cập nhật được ứng dụng**):
   `keytool -genkeypair -v -keystore truyenxanh.jks -alias truyenxanh -keyalg RSA -keysize 2048 -validity 10000`
2. Trong Android Studio: **Build > Generate Signed App Bundle / APK > APK**, chọn khóa vừa tạo, loại build `release`.
3. Lên Google Play thì chọn **Android App Bundle (.aab)** thay vì APK. Google Play yêu cầu tài khoản nhà phát triển và có thể từ chối ứng dụng chỉ bọc lại web, nên nên có thêm tính năng riêng của ứng dụng.

## Thanh toán trong ứng dụng
- Trang thanh toán (VNPay) được mở **ngay trong ứng dụng** nhờ `allowNavigation` (`*.vnpayment.vn`, `*.supabase.co`) trong `capacitor.config.json`. Nếu đổi cổng thanh toán, thêm tên miền của cổng vào danh sách này, nếu không Capacitor sẽ mở trình duyệt ngoài và người dùng **không quay lại được ứng dụng**.
- Sau khi trả tiền, cổng đưa về `SITE_URL/pages/member/checkout.html?order=…` – cùng địa chỉ web nên vẫn trong ứng dụng, trang tự hỏi trạng thái đơn (trạng thái do cổng báo về máy chủ, không tin tham số trên URL).
- Cổng thử `mock-gateway.html` hoạt động như web (chỉ khi `PAYMENT_PROVIDER=mock`).

## Thử với web chạy trên máy (Live Server)
Android máy ảo gọi máy tính qua `10.0.2.2`. Tạm sửa `capacitor.config.json`: `"url": "http://10.0.2.2:5500/"` và `"cleartext": true`, rồi `npx cap sync`. **Đổi lại HTTPS khi build bản nộp.**

## Giới hạn
- Cần mạng: mất mạng thì hiện trang `www/error.html` (nút Thử lại). Phần khung web có service worker nhưng WebView của Capacitor không dùng offline cho nội dung truyện.
- Chưa có thông báo đẩy (push); thông báo chương mới xem ở chuông trong ứng dụng.
- Biểu tượng và màn hình chờ nằm trong `mobile/assets/` (đã tạo sẵn từ logo chữ T); `npm run icons` đưa chúng vào dự án Android.
- Phát hành lên Google Play / App Store cần tài khoản nhà phát triển, ký ứng dụng; ngoài phạm vi đồ án.
- Ai muốn làm ứng dụng **native** riêng (Flutter, React Native, Kotlin/Swift) vẫn dùng được cùng API: xem `docs/API-REST.md`.
