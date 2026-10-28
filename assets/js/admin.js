/* admin.js — dùng chung cho các trang quản trị (Sprint 2: story 15–18). Nạp sau api.js, ui.js, layout.js. */
const ADMIN_NAV = [
  ["users", "users.html", "Người dùng"],
  ["stories", "stories.html", "Duyệt/gỡ truyện"],
  ["genres", "genres.html", "Thể loại"],
  ["comments", "comments.html", "Bình luận"],
];
/* Kiểm tra quyền admin, vẽ thanh menu con. Trả về true nếu được phép vào trang. */
async function requireAdmin(active) {
  const box = $("gate");
  try {
    const u = await API.currentUser();
    if (!u) {
      box.innerHTML = `<div class="card empty">Bạn cần <a href="../auth/login.html?next=${encodeURIComponent(location.pathname)}" style="color:var(--primary-dark);font-weight:600">đăng nhập</a> bằng tài khoản quản trị viên.</div>`;
      return false;
    }
    const me = await API.getProfile();
    if (me.role !== "admin") {
      box.innerHTML = emptyHTML("Chỉ quản trị viên mới được vào trang này.");
      return false;
    }
    box.innerHTML = `<nav class="subnav">${ADMIN_NAV.map(([k, h, t]) => `<a href="${h}" class="${k === active ? "on" : ""}">${t}</a>`).join("")}</nav>`;
    return true;
  } catch (e) {
    showError(box, e);
    return false;
  }
}
const fmtDate = (d) => new Date(d).toLocaleDateString("vi-VN");
