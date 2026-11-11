// Dùng: npm run set-url -- https://truyenxanhvn.com/
// Ghi địa chỉ web đã triển khai vào capacitor.config.json (ứng dụng sẽ mở đúng địa chỉ này).
import { readFileSync, writeFileSync } from "node:fs";
const url = process.argv[2];
if (!url || !/^https:\/\/[^\s/]+(\/\S*)?$/.test(url)) {
  console.error("Cần địa chỉ https đầy đủ, ví dụ: npm run set-url -- https://truyenxanhvn.com/");
  process.exit(1);
}
const p = new URL("../capacitor.config.json", import.meta.url);
const cfg = JSON.parse(readFileSync(p, "utf8"));
cfg.server.url = url.endsWith("/") ? url : url + "/";
writeFileSync(p, JSON.stringify(cfg, null, 2) + "\n");
console.log("Đã đặt server.url =", cfg.server.url);
