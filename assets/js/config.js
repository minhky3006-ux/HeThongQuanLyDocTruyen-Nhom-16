// Copy thành config.js (đã nằm trong .gitignore) rồi điền giá trị thật. KHÔNG commit config.js.
window.APP_CONFIG = {
  SUPABASE_URL: "https://fodabxujramcnwklpqwc.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_cTLOVcwvxbA0V4Vz1KmKVQ_iY3alYnh", // anon key được phép công khai, bảo mật dựa vào RLS
  IMG_BASE: "https://pub-d51c5a2ce27d424d9f249659bdb672e2.r2.dev/", // domain gắn với bucket R2
};
// Ghép URL ảnh: IMG_BASE + image_key, ví dụ APP_CONFIG.IMG_BASE + "s12/c3/001.webp"
