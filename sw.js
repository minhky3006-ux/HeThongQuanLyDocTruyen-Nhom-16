/* Service worker của TruyệnXanh: giúp cài như ứng dụng và mở được khung giao diện khi mất mạng.
   Chiến lược: MẠNG TRƯỚC, mất mạng mới dùng bản đã lưu. Nhờ vậy sau khi triển khai bản mới, người dùng luôn nhận mã mới ngay,
   không bị kẹt bản cũ. Chỉ xử lý file CÙNG TÊN MIỀN của web; mọi lời gọi tới Supabase, R2, cổng thanh toán đều đi thẳng, không bao giờ lưu. */
const CACHE = "truyenxanh-v2"; // đổi số này nếu muốn buộc xóa toàn bộ bản đã lưu
const SHELL = ["index.html", "manifest.json", "assets/css/style.css", "assets/js/config.js", "assets/js/api.js", "assets/js/ui.js", "assets/js/layout.js", "assets/img/icon-192.png"];

self.addEventListener("install", (e) => {
  // allSettled: thiếu một file (vd. config.js chưa tạo) không làm hỏng cả việc cài đặt
  e.waitUntil(caches.open(CACHE).then((c) => Promise.allSettled(SHELL.map((u) => c.add(u)))).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  e.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok && res.type === "basic") {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(async () => {
        const hit = await caches.match(req);
        if (hit) return hit;
        if (req.mode === "navigate") return (await caches.match("index.html")) || Response.error();
        return Response.error();
      }),
  );
});
