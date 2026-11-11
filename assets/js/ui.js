/* ui.js — hàm dựng HTML dùng chung. Mọi chữ do người dùng nhập PHẢI qua esc() để chống chèn mã độc (XSS). */
const $ = (id) => document.getElementById(id);
const ROOT = document.body.dataset.root || "";
const esc = (s) =>
  String(s ?? "").replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c],
  );
const stars = (s) => (s.rating_count === 0 ? "Chưa có đánh giá" : "★ " + Number(s.rating_avg).toFixed(1));
const fmt = (n) => {
  n = Number(n) || 0;
  return n >= 999950 ? (n / 1e6).toFixed(1) + "M" : n >= 1000 ? (n / 1000).toFixed(1) + "K" : n;
};
const COLORS = ["#46B07A", "#5BA8C9", "#E39A6B", "#9A86D1", "#D97A94", "#7DAF4B"];
const STATUS_VI = { draft: "Nháp", pending: "Chờ duyệt", published: "Đã đăng", removed: "Đã gỡ" };
// rows: mảng mảng (dòng đầu là tiêu đề). Thêm BOM UTF-8 để Excel đọc đúng tiếng Việt.
function downloadCSV(filename, rows) {
  const cell = (v) => {
    let t = String(v ?? "");
    if (/^[=+\-@]/.test(t)) t = "'" + t; // chống chèn công thức khi mở bằng Excel
    return /[",\n]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t;
  };
  const blob = new Blob(["\ufeff" + rows.map((r) => r.map(cell).join(",")).join("\r\n")], { type: "text/csv;charset=utf-8" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}
// Ngày yyyy-mm-dd theo giờ máy người dùng (không lệch múi giờ như toISOString)
const isoDay = (d) => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
const REPORT_VI = { spam: "Spam / quảng cáo", abuse: "Xúc phạm, quấy rối", spoiler: "Tiết lộ nội dung (spoiler)", other: "Lý do khác" };
// Một bình luận: người viết thấy nút Xóa, người khác (đã đăng nhập) thấy nút Báo cáo
const commentItemHTML = (c, meId) =>
  `<div class="comment"><b>${esc(c.profiles?.display_name || "Ẩn danh")}</b> <span class="muted" style="font-size:.8rem">${new Date(c.created_at).toLocaleString("vi-VN")}</span>${
    meId && meId === c.user_id
      ? ` <button class="btn ghost sm" data-del="${c.id}">Xóa</button>`
      : meId
        ? ` <button class="btn ghost sm" data-rep="${c.id}">Báo cáo</button>`
        : ""
  }<p>${esc(c.body)}</p></div>`;
// Hộp thoại chọn lý do báo cáo. Trả về { reason, note } hoặc null nếu hủy.
function reportDialog() {
  return new Promise((resolve) => {
    const wrap = document.createElement("div");
    wrap.className = "modal";
    wrap.innerHTML = `<form class="card modal-box"><h3 style="margin-top:0">Báo cáo bình luận</h3>
      <div class="field"><label for="rr">Lý do</label><select id="rr" class="input">${Object.entries(REPORT_VI).map(([k, v]) => `<option value="${k}">${v}</option>`).join("")}</select></div>
      <div class="field"><label for="rn">Ghi chú (không bắt buộc)</label><textarea id="rn" class="input" rows="3" maxlength="500"></textarea></div>
      <p class="row"><button class="btn">Gửi báo cáo</button><button type="button" class="btn ghost" data-x>Hủy</button></p></form>`;
    const done = (v) => {
      wrap.remove();
      resolve(v);
    };
    wrap.querySelector("form").onsubmit = (e) => {
      e.preventDefault();
      done({ reason: wrap.querySelector("#rr").value, note: wrap.querySelector("#rn").value });
    };
    wrap.querySelector("[data-x]").onclick = () => done(null);
    wrap.onclick = (e) => {
      if (e.target === wrap) done(null);
    };
    document.body.appendChild(wrap);
  });
}
async function reportCommentFlow(commentId, msgEl) {
  const r = await reportDialog();
  if (!r) return;
  try {
    await API.reportComment(commentId, r.reason, r.note);
    showMsg(msgEl, "Đã gửi báo cáo, cảm ơn bạn. Quản trị viên sẽ xem xét.", true);
  } catch (e) {
    showMsg(msgEl, e.message);
  }
}
const PROGRESS_VI = { ongoing: "Đang ra", completed: "Hoàn thành", paused: "Tạm ngưng" };
const fmtDay = (d) => new Date(d).toLocaleDateString("vi-VN");
const fmtDateTime = (d) => new Date(d).toLocaleString("vi-VN", { dateStyle: "short", timeStyle: "short" });
// câu giải thích vì sao đọc được, khi có cả gói lẫn mua lẻ. a = API.myStoryAccess(); trả "" nếu chưa có quyền.
function accessSourceText(a) {
  if (!a) return "";
  const sub = a.subscription ? `gói “${esc(a.subscription.plan_name)}” (đến ${fmtDay(a.subscription.expires_at)})` : "";
  if (sub && a.purchased) return `Bạn đọc được nhờ ${sub} và cũng đã mua lẻ truyện này (quyền mua lẻ không hết hạn).`;
  if (sub) return `Bạn đọc được nhờ ${sub}.`;
  if (a.purchased) return "Bạn đã mua truyện này, đọc không giới hạn thời gian.";
  return "";
}
const ACCESS_VI = { free: "Miễn phí", paid: "Trả phí", mixed: "Kết hợp" };
const ORDER_VI = { pending: "Đang chờ thanh toán", paid: "Đã thanh toán", failed: "Thất bại", cancelled: "Đã hủy" };
const vnd = (n) => Number(n || 0).toLocaleString("vi-VN") + " ₫";
// Chương này miễn phí? CHỈ để hiển thị nhãn. Quyền đọc thật do DB quyết định (hàm can_read_chapter, API.canReadChapter).
const isFreeChapter = (story, ch) =>
  story.access_policy === "free" || (story.access_policy === "mixed" && !!ch.is_free_preview);
const accessBadge = (story, ch, unlocked = false) =>
  isFreeChapter(story, ch)
    ? '<span class="badge">Miễn phí</span>'
    : unlocked
      ? '<span class="badge">Đã mở khóa</span>'
      : '<span class="badge lock">🔒 Trả phí</span>';
const coverHTML = (s, big = false) =>
  s.cover_key
    ? `<img class="cover" src="${esc(API.imgUrl(s.cover_key, !big))}" alt="Bìa ${esc(s.title)}" width="300" height="400" loading="lazy">`
    : `<div class="cover" style="background:linear-gradient(160deg,${COLORS[s.id % COLORS.length]},#2E8B5C)">${esc(s.title[0])}</div>`;
const cardHTML = (s) =>
  `<a class="story" href="${ROOT}pages/stories/detail.html?id=${s.id}">${coverHTML(s)}<h3>${esc(s.title)}</h3><p>${esc(s.author)} · ${stars(s)}${s.access_policy && s.access_policy !== "free" ? " · 🔒" : ""}</p></a>`;
const emptyHTML = (t) => `<p class="empty">${esc(t)}</p>`;
const showError = (el, e) => {
  el.innerHTML = `<p class="empty" role="alert">${esc(e.message || e)}</p>`;
};
const showMsg = (el, t, ok = false) => {
  el.textContent = t;
  el.className = "msg " + (ok ? "ok" : "err");
  el.hidden = false;
};
const paragraphs = (t) =>
  String(t || "")
    .split(/\n+/)
    .filter(Boolean)
    .map((p) => `<p>${esc(p)}</p>`)
    .join("");
const goNext = (fallback) => {
  const n = new URLSearchParams(location.search).get("next");
  try {
    const u = new URL(n || fallback, location.href);
    if (u.origin === location.origin) return (location.href = u.href);
  } catch (_) {}
  location.href = fallback;
};
