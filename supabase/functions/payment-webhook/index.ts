// Nhận kết quả thanh toán và ghi nhận giao dịch.
// Deploy: supabase functions deploy payment-webhook --no-verify-jwt
//   (--no-verify-jwt vì VNPay gọi từ máy chủ của họ, không có JWT; độ tin cậy dựa vào CHỮ KÝ của cổng, kiểm tra bên dưới.)
// Mọi thay đổi trạng thái đơn đều đi qua hàm DB fulfill_order / fail_order: idempotent, kiểm tra số tiền, chỉ service role gọi được.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors, json, provider, vnpayVerify } from "../_shared/payment.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  try {
    if (req.method === "GET") {
      if (provider() !== "vnpay") return json({ RspCode: "99", Message: "Not enabled" });
      const params = Object.fromEntries(new URL(req.url).searchParams) as Record<string, string>;
      const v = await vnpayVerify(params);
      if (!v) return json({ RspCode: "97", Message: "Invalid signature" });
      const { data: order } = await admin.from("orders").select("id,amount,status,provider").eq("id", v.vnp_TxnRef).maybeSingle();
      if (!order || order.provider !== "vnpay") return json({ RspCode: "01", Message: "Order not found" });
      if (Number(v.vnp_Amount) !== order.amount * 100) return json({ RspCode: "04", Message: "Invalid amount" });
      if (order.status === "paid") return json({ RspCode: "02", Message: "Order already confirmed" });
      if (v.vnp_ResponseCode === "00" && v.vnp_TransactionStatus === "00") {
        const { error } = await admin.rpc("fulfill_order", {
          p_order: order.id,
          p_txn: v.vnp_TransactionNo ?? v.vnp_TxnRef,
          p_amount: Number(v.vnp_Amount) / 100,
          p_raw: v,
        });
        if (error) throw error;
      } else {
        await admin.rpc("fail_order", { p_order: order.id, p_reason: `VNPay mã ${v.vnp_ResponseCode ?? "?"}`, p_raw: v });
      }
      return json({ RspCode: "00", Message: "Confirm Success" });
    }

    if (req.method === "POST") {
      if (provider() !== "mock") return json({ error: "Cổng giả lập đã tắt" }, 403);
      const asUser = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
        global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
      });
      const {
        data: { user },
      } = await asUser.auth.getUser();
      if (!user) return json({ error: "Bạn cần đăng nhập." }, 401);
      const b = await req.json().catch(() => ({}));
      if (b.provider !== "mock" || typeof b.orderId !== "string") return json({ error: "Yêu cầu không hợp lệ" }, 400);
      const { data: order } = await admin.from("orders").select("id,amount,status,user_id,provider").eq("id", b.orderId).maybeSingle();
      if (!order || order.user_id !== user.id || order.provider !== "mock") return json({ error: "Không tìm thấy đơn hàng" }, 404);
      if (order.status !== "pending") return json({ status: order.status });
      if (b.result === "success") {
        const { data, error } = await admin.rpc("fulfill_order", {
          p_order: order.id,
          p_txn: `MOCK-${crypto.randomUUID()}`,
          p_amount: order.amount,
          p_raw: { mock: true },
        });
        if (error) throw error;
        return json({ status: data });
      }
      await admin.rpc("fail_order", { p_order: order.id, p_reason: "Giả lập: thanh toán thất bại", p_raw: { mock: true } });
      return json({ status: "failed" });
    }
    return json({ error: "Method not allowed" }, 405);
  } catch (e) {
    console.error(e);
    return req.method === "GET" ? json({ RspCode: "99", Message: "Unknown error" }) : json({ error: "Lỗi máy chủ, vui lòng thử lại sau" }, 500);
  }
});
