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
    // Quản trị viên: thêm mục "Quản trị" vào menu (Sprint 2: story 15–18)
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
