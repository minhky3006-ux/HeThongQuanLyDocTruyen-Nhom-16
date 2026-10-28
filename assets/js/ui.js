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
const coverHTML = (s, big = false) =>
  s.cover_key
    ? `<img class="cover" src="${esc(API.imgUrl(s.cover_key, !big))}" alt="Bìa ${esc(s.title)}" width="300" height="400" loading="lazy">`
    : `<div class="cover" style="background:linear-gradient(160deg,${COLORS[s.id % COLORS.length]},#2E8B5C)">${esc(s.title[0])}</div>`;
const cardHTML = (s) =>
  `<a class="story" href="${ROOT}pages/stories/detail.html?id=${s.id}">${coverHTML(s)}<h3>${esc(s.title)}</h3><p>${esc(s.author)} · ${stars(s)}</p></a>`;
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
