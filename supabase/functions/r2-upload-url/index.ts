// Cấp link upload tạm (5 phút) lên Cloudflare R2. Khóa R2 chỉ nằm ở đây (secrets), không bao giờ ở trình duyệt.
// Deploy: supabase functions deploy r2-upload-url   (xem db/README.md)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.20";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    // Chạy bằng chính quyền của người gọi, nên RLS trong DB vẫn áp dụng
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return json({ error: "Chưa đăng nhập" }, 401);

    const { key, contentType } = await req.json();
    if (contentType !== "image/webp") return json({ error: "Chỉ nhận ảnh WebP" }, 400);
    const { data: me } = await sb.from("profiles").select("is_locked").eq("id", user.id).single();
    if (!me || me.is_locked) return json({ error: "Tài khoản bị khóa" }, 403);

    // Chỉ cho ghi vào đúng vị trí của mình
    const m = /^covers\/(\d+)(_s)?\.webp$/.exec(key) ?? /^s(\d+)\/c\d+\/\d{3,4}\.webp$/.exec(key);
    if (m) {
      const { data } = await sb.from("stories").select("id").eq("id", m[1]).eq("author_id", user.id).maybeSingle();
      if (!data) return json({ error: "Đây không phải truyện của bạn" }, 403);
    } else if (key !== `avatars/${user.id}.webp`) {
      return json({ error: "Đường dẫn ảnh không hợp lệ" }, 400);
    }

    const aws = new AwsClient({
      accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID")!, secretAccessKey: Deno.env.get("R2_SECRET_ACCESS_KEY")!,
      service: "s3", region: "auto",
    });
    const url = new URL(`https://${Deno.env.get("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com/${Deno.env.get("R2_BUCKET")}/${key}`);
    url.searchParams.set("X-Amz-Expires", "300");
    const signed = await aws.sign(new Request(url, { method: "PUT" }), { aws: { signQuery: true } });
    return json({ url: signed.url });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
