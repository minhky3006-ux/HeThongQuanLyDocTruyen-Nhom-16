// Copy file này thành assets/js/config.js (đã nằm trong .gitignore, KHÔNG commit) rồi điền giá trị thật.
// Lấy ở: Supabase > Project Settings > API (URL + anon/publishable key); IMG_BASE là domain gắn với bucket R2.
window.APP_CONFIG = {
  SUPABASE_URL: "https://<ma-project>.supabase.co",
  SUPABASE_ANON_KEY: "<anon-hoac-publishable-key>", // khóa này được phép công khai, bảo mật dựa vào RLS (db/schema.sql)
  IMG_BASE: "https://<ten-mien-r2>/", // BẮT BUỘC có dấu / ở cuối
};
// Ghép URL ảnh: IMG_BASE + image_key, ví dụ APP_CONFIG.IMG_BASE + "s12/c3/001.webp"
