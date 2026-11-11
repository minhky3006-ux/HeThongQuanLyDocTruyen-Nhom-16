// Chèn header (desktop) + tab bar (mobile) và hiện trạng thái đăng nhập. Cần ui.js + api.js nạp trước.
const NAV = [
  ["home", "index.html", "🏠", "Trang chủ"],
  ["stories", "pages/stories/list.html", "📚", "Truyện"],
  ["library", "pages/member/library.html", "📖", "Tủ truyện"],
  ["author", "pages/author/dashboard.html", "✍️", "Tác giả"],
  ["login", "pages/auth/login.html", "👤", "Tài khoản"],
];
const cur = document.body.dataset.page;
const links = (c) =>
  NAV.map(
    ([k, h, i, t]) =>
      `<a data-nav="${k}" href="${ROOT}${h}" class="${k === cur ? "on" : ""}">${c ? `<span>${i}</span>` : ""}${t}</a>`,
  ).join("");
document.body.insertAdjacentHTML(
  "afterbegin",
  `<header class="topbar"><div class="container"><a class="brand" href="${ROOT}index.html">🌿 TruyệnXanh</a><nav class="nav-links">${links(false)}</nav></div></header>`,
);
document.body.insertAdjacentHTML("beforeend", `<nav class="tabbar">${links(true)}</nav>`);
if (!API.configured)
  document
    .querySelector("main")
    .insertAdjacentHTML(
      "afterbegin",
      '<div class="banner">Chưa kết nối cơ sở dữ liệu. Copy <code>assets/js/config.example.js</code> thành <code>config.js</code> và điền khóa Supabase (xem db/README.md).</div>',
    );
API.currentUser()
  .then((u) => {
    if (!u) return;
    // Quản trị viên: thêm mục "Quản trị" vào menu
    API.getProfile()
      .then((me) => {
        if (me.role !== "admin") return;
        const add = (box, withIcon) =>
          box &&
          box.insertAdjacentHTML(
            "beforeend",
            `<a data-nav="admin" href="${ROOT}pages/admin/users.html" class="${cur === "admin" ? "on" : ""}">${withIcon ? "<span>🛡️</span>" : ""}Quản trị</a>`,
          );
        add(document.querySelector(".nav-links"), false);
        add(document.querySelector(".tabbar"), true);
      })
      .catch(() => {});
    // đăng ký service worker để cài như ứng dụng (chỉ khi chạy qua http/https, không phải file://)
    if ("serviceWorker" in navigator && /^https?:$/.test(location.protocol))
      navigator.serviceWorker.register(ROOT + "sw.js").catch(() => {});
    // chuông thông báo chương mới kèm số chưa đọc
    const bell = (box, withIcon) =>
      box &&
      box.insertAdjacentHTML(
        "beforeend",
        `<a data-nav="notifications" href="${ROOT}pages/member/notifications.html" class="${cur === "notifications" ? "on" : ""}">${withIcon ? "<span>🔔</span>" : ""}Thông báo<b class="bell-badge" hidden></b></a>`,
      );
    bell(document.querySelector(".nav-links"), false);
    bell(document.querySelector(".tabbar"), true);
    API.unreadNotificationCount()
      .then((n) => {
        if (n)
          document.querySelectorAll(".bell-badge").forEach((b) => {
            b.textContent = n > 99 ? "99+" : n;
            b.hidden = false;
          });
      })
      .catch(() => {});
    // Đã đăng nhập: mục "Tài khoản" đổi thành "Đăng xuất" (cả menu desktop lẫn tab bar mobile)
    document.querySelectorAll('a[data-nav="login"]').forEach((a) => {
      a.lastChild.textContent = "Đăng xuất";
      a.classList.remove("on");
      a.href = "#";
      a.onclick = async (e) => {
        e.preventDefault();
        await API.signOut();
        location.href = ROOT + "index.html";
      };
    });
  })
  .catch(() => {});

// ---- Cài ứng dụng lên màn hình chính (PWA) ----
// Android/Chrome/Edge: bắt sự kiện beforeinstallprompt để hiện nút "Cài đặt" (cài bằng 1 chạm).
// iPhone/iPad (Safari): không có sự kiện này, chỉ hướng dẫn "Chia sẻ > Thêm vào Màn hình chính".
(() => {
  if (matchMedia("(display-mode: standalone)").matches || navigator.standalone) return; // đã chạy như ứng dụng
  const KEY = "tx_install_dismissed";
  const store = {
    get: () => { try { return +localStorage.getItem(KEY) || 0; } catch (_) { return 0; } },
    set: () => { try { localStorage.setItem(KEY, Date.now()); } catch (_) {} },
  };
  const snoozed = () => Date.now() - store.get() < 7 * 864e5; // đã tắt thì 7 ngày sau mới hỏi lại
  let deferred = null;
  let bar = null;
  const close = (remember) => {
    if (bar) bar.remove();
    bar = null;
    if (remember) store.set();
  };
  const show = (text, withButton) => {
    if (bar || snoozed()) return;
    bar = document.createElement("div");
    bar.className = "install-bar";
    bar.innerHTML = `<span>${text}</span>${withButton ? '<button class="btn sm" data-i="go">Cài đặt</button>' : ""}<button class="btn ghost sm" data-i="x" aria-label="Đóng">✕</button>`;
    bar.onclick = (e) => {
      const b = e.target.closest("button[data-i]");
      if (!b) return;
      if (b.dataset.i === "go") install();
      else close(true);
    };
    document.body.appendChild(bar);
  };
  async function install() {
    if (!deferred) return;
    deferred.prompt();
    await deferred.userChoice.catch(() => {});
    deferred = null; // mỗi lần chỉ dùng được một lần
    close(false);
    document.querySelectorAll('a[data-nav="install"]').forEach((a) => a.remove());
  }
  window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault();
    deferred = e;
    show("Cài TruyệnXanh lên màn hình chính để đọc nhanh như một ứng dụng.", true);
    // nút cố định trên menu desktop, dùng được cả khi đã tắt banner
    const nav = document.querySelector(".nav-links");
    if (nav && !nav.querySelector('[data-nav="install"]')) {
      nav.insertAdjacentHTML("beforeend", '<a data-nav="install" href="#">⬇ Cài ứng dụng</a>');
      nav.lastChild.onclick = (ev) => {
        ev.preventDefault();
        install();
      };
    }
  });
  window.addEventListener("appinstalled", () => {
    deferred = null;
    close(false);
    document.querySelectorAll('a[data-nav="install"]').forEach((a) => a.remove());
  });
  const ios = /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  if (ios) show("Để cài ứng dụng: bấm nút Chia sẻ (ô vuông có mũi tên) rồi chọn \"Thêm vào Màn hình chính\".", false);
})();
