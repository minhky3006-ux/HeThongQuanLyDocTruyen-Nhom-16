// Dùng chung cho create-payment và payment-webhook.
// Chọn cổng bằng secret PAYMENT_PROVIDER: "mock" (thử, không cần tài khoản) hoặc "vnpay" (sandbox/thật).

export const cors = {
  "Access-Control-Allow-Origin": "*",
  // SDK supabase-js bản mới có thể gửi thêm header (x-supabase-api-version...) -> thiếu là preflight CORS lỗi, trình duyệt báo "Failed to send a request to the Edge Function"
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

export const provider = () => (Deno.env.get("PAYMENT_PROVIDER") ?? "mock").toLowerCase();
// Địa chỉ gốc của web (có cả thư mục con nếu có), KHÔNG có dấu / ở cuối. Vd: http://127.0.0.1:5500 hoặc https://nhom16.github.io/truyen-xanh
export const siteUrl = () => (Deno.env.get("SITE_URL") ?? "http://127.0.0.1:5500").replace(/\/+$/, "");

// Quy tắc ký: sắp xếp tham số theo tên, nối "khoá=giá trị" (đã mã hoá URL, dấu cách thành +), HMAC-SHA512 bằng HashSecret.
const enc = (v: string) => encodeURIComponent(v).replace(/%20/g, "+");
const signData = (p: Record<string, string>) =>
  Object.keys(p)
    .sort()
    .map((k) => `${enc(k)}=${enc(p[k])}`)
    .join("&");
async function hmac512(data: string, secret: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-512" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
const need = (k: string) => {
  const v = Deno.env.get(k);
  if (!v) throw new Error(`Thiếu secret ${k} (xem db/README.md, mục Thanh toán)`);
  return v;
};
// yyyyMMddHHmmss theo giờ Việt Nam (UTC+7)
const vnTime = (ms = Date.now()) => new Date(ms + 7 * 3600e3).toISOString().replace(/\D/g, "").slice(0, 14);

export async function vnpayPayUrl(o: { id: string; amount: number }, ip: string, returnUrl: string) {
  const p: Record<string, string> = {
    vnp_Version: "2.1.0",
    vnp_Command: "pay",
    vnp_TmnCode: need("VNPAY_TMN_CODE"),
    vnp_Amount: String(o.amount * 100), // VNPay yêu cầu nhân 100
    vnp_CurrCode: "VND",
    vnp_TxnRef: o.id, // mã đơn của mình (uuid) -> IPN trả về đúng mã này
    vnp_OrderInfo: `Thanh toan don ${o.id}`, // không dấu
    vnp_OrderType: "other",
    vnp_Locale: "vn",
    vnp_ReturnUrl: returnUrl,
    vnp_IpAddr: ip,
    vnp_CreateDate: vnTime(),
    vnp_ExpireDate: vnTime(Date.now() + 15 * 60e3),
  };
  const hash = await hmac512(signData(p), need("VNPAY_HASH_SECRET"));
  const base = Deno.env.get("VNPAY_URL") ?? "https://sandbox.vnpayment.vn/paymentv2/vpcpay.html";
  return `${base}?${signData(p)}&vnp_SecureHash=${hash}`;
}
// Kiểm tra chữ ký của IPN/return. Trả về tham số đã bỏ vnp_SecureHash nếu hợp lệ, ngược lại null.
export async function vnpayVerify(params: Record<string, string>) {
  const { vnp_SecureHash, vnp_SecureHashType: _t, ...rest } = params;
  if (!vnp_SecureHash) return null;
  const expect = await hmac512(signData(rest), need("VNPAY_HASH_SECRET"));
  return expect.toLowerCase() === vnp_SecureHash.toLowerCase() ? rest : null;
}
