// Tạo đơn hàng và trả link sang cổng thanh toán.
// Deploy: supabase functions deploy create-payment      (giữ xác thực JWT mặc định)
// Giá do MÁY CHỦ lấy từ bảng plans, không nhận từ trình duyệt -> không sửa giá được từ client.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors, json, provider, siteUrl, vnpayPayUrl } from "../_shared/payment.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    // Người gọi: dùng đúng quyền của họ để biết họ là ai và có bị khóa không
    const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const {
      data: { user },
    } = await asUser.auth.getUser();
    if (!user) return json({ error: "Bạn cần đăng nhập." }, 401);
    const { data: me } = await asUser.from("profiles").select("is_locked").eq("id", user.id).single();
    if (!me || me.is_locked) return json({ error: "Tài khoản bị khóa" }, 403);

    let body: { kind?: unknown; planId?: unknown; storyId?: unknown };
    try {
      body = await req.json();
    } catch (_) {
      return json({ error: "Yêu cầu không hợp lệ" }, 400);
    }
    const isPlan = body.kind === "plan" && Number.isInteger(body.planId);
    const isStory = body.kind === "story" && Number.isInteger(body.storyId);
    if (!isPlan && !isStory) return json({ error: "Yêu cầu không hợp lệ" }, 400);

    // Ghi đơn bằng service role vì client không có quyền ghi bảng orders (xem db/migrations/ALL_sprint3-6.sql)
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    // Mô tả món hàng: giá luôn lấy từ DB tại thời điểm tạo đơn và được CHỐT vào đơn
    let item: { kind: "plan" | "story"; plan_id?: number; story_id?: number; amount: number };
    if (isPlan) {
      const { data: plan } = await admin.from("plans").select("id,price,is_active").eq("id", body.planId).maybeSingle();
      if (!plan || !plan.is_active) return json({ error: "Gói này không tồn tại hoặc đã ngừng bán." }, 404);
      item = { kind: "plan", plan_id: plan.id, amount: plan.price };
    } else {
      const { data: story } = await admin.from("stories").select("id,status,access_policy,price").eq("id", body.storyId).maybeSingle();
      if (!story || story.status !== "published") return json({ error: "Truyện không tồn tại." }, 404);
      if (story.access_policy === "free" || !story.price) return json({ error: "Truyện này không bán lẻ." }, 400);
      // đã có quyền (gói còn hạn bao phủ truyện, hoặc đã mua) thì không bán lại
      const { data: has } = await admin.rpc("has_story_access_for", { p_user: user.id, p_story: story.id });
      if (has) return json({ error: "Bạn đã có quyền đọc truyện này (gói còn hạn hoặc đã mua), không cần thanh toán lại." }, 409);
      item = { kind: "story", story_id: story.id, amount: story.price };
    }

    // Chặn tạo đơn dồn dập (mỗi người tối đa 5 đơn đang chờ trong 1 giờ)
    const { count } = await admin
      .from("orders")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .eq("status", "pending")
      .gte("created_at", new Date(Date.now() - 3600e3).toISOString());
    if ((count ?? 0) >= 5) return json({ error: "Bạn có quá nhiều đơn đang chờ, hãy thử lại sau." }, 429);

    const prov = provider();
    const { data: order, error } = await admin
      .from("orders")
      .insert({ user_id: user.id, ...item, provider: prov })
      .select("id,amount")
      .single();
    if (error || !order) throw error ?? new Error("Không tạo được đơn");

    const back = `${siteUrl()}/pages/member/checkout.html?order=${order.id}`;
    let payUrl: string;
    if (prov === "vnpay") {
      const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "127.0.0.1";
      payUrl = await vnpayPayUrl(order, ip, back);
    } else if (prov === "mock") {
      payUrl = `${siteUrl()}/pages/member/mock-gateway.html?order=${order.id}`;
    } else {
      return json({ error: "Cổng thanh toán chưa được cấu hình" }, 500);
    }
    return json({ orderId: order.id, payUrl });
  } catch (e) {
    console.error(e); // chi tiết chỉ xem trong log Supabase
    return json({ error: "Lỗi máy chủ, vui lòng thử lại sau" }, 500);
  }
});
