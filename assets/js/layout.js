// Chèn header (desktop) + tab bar (mobile) và hiện trạng thái đăng nhập. Cần ui.js + api.js nạp trước.
const NAV = [
  ["home", "index.html", "🏠", "Trang chủ"],
  ["stories", "pages/stories/list.html", "📚", "Truyện"],
  ["author", "pages/author/dashboard.html", "✍️", "Tác giả"],
  ["login", "pages/auth/login.html", "👤", "Tài khoản"],
];
const cur = document.body.dataset.page;
const links = (c) =>
  NAV.map(
    ([k, h, i, t]) =>
      `<a href="${ROOT}${h}" class="${k === cur ? "on" : ""}">${c ? `<span>${i}</span>` : ""}${t}</a>`,
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
    const b = document.createElement("button");
    b.className = "btn ghost logout";
    b.textContent = "Đăng xuất";
    b.onclick = async () => {
      await API.signOut();
      location.href = ROOT + "index.html";
    };
    document.querySelector(".topbar .container").appendChild(b);
  })
  .catch(() => {});
