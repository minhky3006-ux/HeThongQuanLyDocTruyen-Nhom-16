// Dùng: npm run apk            -> build APK debug (cài thử được ngay)
//       npm run apk -- release -> build APK release (cần đã tạo khóa ký, xem README mục "APK bản phát hành")
// Yêu cầu: đã chạy `npx cap add android`, có JDK 17+ và Android SDK (cài Android Studio là có đủ).
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";

const release = process.argv[2] === "release";
const run = (cmd, args, cwd) => {
  const r = spawnSync(cmd, args, { cwd, stdio: "inherit", shell: process.platform === "win32" });
  if (r.status !== 0) {
    console.error(`\nLệnh thất bại: ${cmd} ${args.join(" ")}`);
    process.exit(r.status ?? 1);
  }
};
if (!existsSync("android")) {
  console.error('Chưa có thư mục android/. Chạy trước: npx cap add android');
  process.exit(1);
}
run("npx", ["cap", "sync", "android"], ".");
const gradle = process.platform === "win32" ? "gradlew.bat" : "./gradlew";
run(gradle, [release ? "assembleRelease" : "assembleDebug"], "android");
const out = join("android", "app", "build", "outputs", "apk", release ? "release" : "debug");
console.log(`\nXong. File APK nằm trong: ${out}`);
