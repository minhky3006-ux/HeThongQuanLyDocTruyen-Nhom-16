(() => {
  const cfg = window.APP_CONFIG || {};
  const sb =
    cfg.SUPABASE_URL && window.supabase
      ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY)
      : null;
  const PAGE = 20;
  const CARD =
    "id,title,cover_key,rating_avg,view_count,chapter_count,rating_count,access_policy,profiles!author_id(display_name)";
  const MSG = {
    comment_reports_comment_id_reporter_id_key: "Bạn đã báo cáo bình luận này rồi.",
    banned_words_word_norm_mode_key: "Từ khóa này đã có trong danh sách.",
    "Invalid login credentials": "Sai email hoặc mật khẩu.",
    "User already registered": "Email này đã được đăng ký.",
    "Password should be": "Mật khẩu cần tối thiểu 6 ký tự.",
    "JSON object requested": "Không tìm thấy dữ liệu.",
    "row-level security": "Bạn không có quyền thực hiện thao tác này.",
    "Email not confirmed": "Hãy xác nhận email trước khi đăng nhập.",
    "duplicate key": "Dữ liệu bị trùng, hãy thử lại.",
    "Failed to fetch": "Không kết nối được máy chủ, kiểm tra mạng rồi thử lại.",
    "violates foreign key": "Không xóa được vì đã có dữ liệu liên quan (đơn hàng, thuê bao...). Hãy chọn Ngừng bán thay vì xóa.",
    "violates check constraint": "Dữ liệu không hợp lệ, kiểm tra lại các ô nhập (giá > 0, thời hạn 1–3660 ngày).",
  };
  const vi = (m) => {
    for (const k in MSG) if (m && m.includes(k)) return MSG[k];
    return m;
  };
  const db = () => {
    if (!sb)
      throw new Error(
        "Chưa cấu hình: copy assets/js/config.example.js thành assets/js/config.js rồi điền khóa Supabase.",
      );
    return sb;
  };
  const run = async (q) => {
    const { data, error, count } = await q;
    if (error) throw new Error(vi(error.message));
    return { data, count };
  };
  const rows = async (q) => (await run(q)).data;
  const clean = (s) =>
    String(s || "")
      .replace(/[%,()*\\]/g, " ")
      .trim();
  const withAuthor = (s) => ({ ...s, author: s.profiles?.display_name || "Ẩn danh" });

  async function currentUser() {
    if (!sb) return null;
    const { data } = await sb.auth.getSession();
    return data.session?.user || null;
  }
  async function uid() {
    const u = await currentUser();
    if (!u) throw new Error("Bạn cần đăng nhập.");
    return u.id;
  }
  async function signUp({ email, password, displayName, asAuthor = false }) {
    const { data, error } = await db().auth.signUp({
      email,
      password,
      // want_author: trigger handle_new_user gán role tác giả ngay khi tạo profile (không mất khi bật Confirm email)
      options: { data: { display_name: displayName, want_author: asAuthor ? "true" : "false" } },
    });
    if (error) throw new Error(vi(error.message));
    return { needsConfirm: !data.session };
  }
  async function signIn(email, password) {
    const { error } = await db().auth.signInWithPassword({ email, password });
    if (error) throw new Error(vi(error.message));
  }
  const signOut = async () => {
    await db().auth.signOut();
  };
  const getProfile = async () =>
    rows(
      db()
        .from("profiles")
        .select("*")
        .eq("id", await uid())
        .single(),
    );
  const becomeAuthor = () => run(db().rpc("become_author"));

  const listGenres = () => rows(db().from("genres").select("id,name").order("name"));
  async function listStories({ q = "", genreId = null, sort = "new", page = 0 } = {}) {
    let query = db()
      .from("stories")
      .select(genreId ? CARD + ",story_genres!inner(genre_id)" : CARD, { count: "exact" })
      .eq("status", "published");
    if (genreId) query = query.eq("story_genres.genre_id", genreId);
    const k = clean(q);
    if (k) {
      // tìm theo tên truyện hoặc tên tác giả
      const ids = (
        await rows(db().from("profiles").select("id").ilike("display_name", `%${k}%`).limit(50))
      ).map((p) => p.id);
      query = ids.length
        ? query.or(`title.ilike.%${k}%,author_id.in.(${ids.join(",")})`)
        : query.ilike("title", `%${k}%`);
    }
    const col =
      { new: "updated_at", released: "published_at", hot: "view_count", rating: "rating_avg" }[sort] || "updated_at";
    const { data, count } = await run(
      query.order(col, { ascending: false }).range(page * PAGE, page * PAGE + PAGE - 1),
    );
    return { items: data.map(withAuthor), total: count ?? 0 };
  }
  async function getStory(id) {
    const s = await rows(
      db()
        .from("stories")
        .select("*,profiles!author_id(display_name),story_genres(genres(id,name))")
        .eq("id", id)
        .single(),
    );
    return { ...withAuthor(s), genres: (s.story_genres || []).map((x) => x.genres) };
  }
  const listChapters = (storyId) =>
    rows(
      db().from("chapters").select("id,number,title,created_at,is_free_preview,publish_at").eq("story_id", storyId).order("number"),
    );
  /* Trả về chương kèm: content (chữ), chapter_pages (ảnh), canRead (true/false).
     Chưa có quyền đọc → content = null, chapter_pages = [] và canRead = false: trang đọc hiển thị khung mua gói. */
  async function getChapter(storyId, number) {
    const c = await rows(
      db()
        .from("chapters")
        .select("*,chapter_contents(content),chapter_pages(page_no,image_key,width,height)")
        .eq("story_id", storyId)
        .eq("number", number)
        .single(),
    );
    const cc = Array.isArray(c.chapter_contents) ? c.chapter_contents[0] : c.chapter_contents;
    c.content = cc?.content ?? null;
    delete c.chapter_contents;
    c.chapter_pages = (c.chapter_pages || []).sort((a, b) => a.page_no - b.page_no);
    c.canRead = await canReadChapter(c.id);
    return c;
  }
  // Hỏi DB người dùng hiện tại có đọc được chương này không (kể cả khách chưa đăng nhập). DB là nơi quyết định duy nhất.
  const canReadChapter = async (chapterId) => !!(await rows(db().rpc("can_read_chapter", { p_chapter: chapterId })));
  // Người dùng hiện tại có gói còn hạn / đã mua lẻ truyện này không (để hiện "Đã mở khóa" ở danh sách chương)
  const hasStoryAccess = async (storyId) => !!(await rows(db().rpc("has_story_access", { p_story: storyId })));
  function trackView(storyId, chapterId) {
    // mỗi chương chỉ tính 1 lượt/phiên, lỗi thì bỏ qua
    try {
      const k = `v${chapterId}`;
      if (sessionStorage.getItem(k)) return;
      sessionStorage.setItem(k, "1");
    } catch (_) {}
    db()
      .rpc("track_view", { p_story: storyId, p_chapter: chapterId })
      .then(
        () => {},
        () => {},
      );
  }

  async function isFollowing(storyId) {
    const u = await currentUser();
    if (!u) return false;
    return (
      (await rows(db().from("follows").select("story_id").eq("user_id", u.id).eq("story_id", storyId)))
        .length > 0
    );
  }
  async function toggleFollow(storyId) {
    // trả về true nếu đang theo dõi sau thao tác
    const u = await uid();
    if (await isFollowing(storyId)) {
      await run(db().from("follows").delete().eq("user_id", u).eq("story_id", storyId));
      return false;
    }
    await run(db().from("follows").insert({ user_id: u, story_id: storyId }));
    return true;
  }
  const myFollows = async () =>
    rows(
      db()
        .from("follows")
        .select("story_id,stories(" + CARD + ")")
        .eq("user_id", await uid())
        .order("created_at", { ascending: false }),
    );
  async function saveHistory(storyId, chapterId, pageNo = 0) {
    const u = await currentUser();
    if (!u) return;
    await db().from("reading_history").upsert(
      {
        user_id: u.id,
        story_id: storyId,
        chapter_id: chapterId,
        page_no: pageNo,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id,story_id" },
    );
  }
  async function getResume(storyId) {
    const u = await currentUser();
    if (!u) return null;
    return rows(
      db()
        .from("reading_history")
        .select("chapter_id,page_no,chapters(number)")
        .eq("user_id", u.id)
        .eq("story_id", storyId)
        .maybeSingle(),
    );
  }
  const getHistory = async (limit = 20) =>
    rows(
      db()
        .from("reading_history")
        .select("story_id,chapter_id,page_no,updated_at,stories(id,title,cover_key),chapters(number)")
        .eq("user_id", await uid())
        .order("updated_at", { ascending: false })
        .limit(limit),
    );
  const listComments = (storyId, page = 0) =>
    rows(
      db()
        .from("comments")
        .select("id,body,created_at,user_id,profiles!user_id(display_name)")
        .eq("story_id", storyId)
        .is("chapter_id", null) // bình luận cấp truyện; thảo luận từng chương: listChapterComments
        .eq("is_hidden", false)
        .order("created_at", { ascending: false })
        .range(page * PAGE, page * PAGE + PAGE - 1),
    );
  // Thảo luận của một chương. DB chỉ trả khi người xem đọc được chương đó.
  const listChapterComments = (chapterId, page = 0) =>
    rows(
      db()
        .from("comments")
        .select("id,body,created_at,user_id,profiles!user_id(display_name)")
        .eq("chapter_id", chapterId)
        .eq("is_hidden", false)
        .order("created_at", { ascending: false })
        .range(page * PAGE, page * PAGE + PAGE - 1),
    );
  // Báo cáo bình luận vi phạm. reason: spam | abuse | spoiler | other
  const reportComment = async (commentId, reason, note = "") =>
    run(
      db()
        .from("comment_reports")
        .insert({ comment_id: commentId, reporter_id: await uid(), reason, note: String(note || "").trim().slice(0, 500) || null }),
    );
  // Người dùng đang bị hạn chế bình luận? -> { until_at, reason } hoặc null
  const myRestriction = async () => {
    const u = await currentUser();
    if (!u) return null;
    const r = await rows(db().from("user_restrictions").select("until_at,reason").eq("user_id", u.id).gt("until_at", new Date().toISOString()).maybeSingle());
    return r || null;
  };
  // Bình luận chỉ thuộc về một chương. Trả về { auto_hidden }: true nếu chứa từ khóa cấm nên bị ẩn chờ admin duyệt.
  async function addComment(storyId, body, chapterId) {
    if (!chapterId) throw new Error("Bình luận phải thuộc một chương.");
    return rows(
      db()
        .from("comments")
        .insert({ story_id: storyId, chapter_id: chapterId, user_id: await uid(), body: body.trim() })
        .select("id,auto_hidden")
        .single(),
    );
  }
  const deleteComment = (id) => run(db().from("comments").delete().eq("id", id));
  async function rate(storyId, score) {
    await run(
      db()
        .from("ratings")
        .upsert({ user_id: await uid(), story_id: storyId, score }, { onConflict: "user_id,story_id" }),
    );
  }
  async function myRating(storyId) {
    const u = await currentUser();
    if (!u) return 0;
    const r = await rows(db().from("ratings").select("score").eq("user_id", u.id).eq("story_id", storyId));
    return r[0]?.score || 0;
  }

  async function createStory({ title, description, kind, genreIds = [] }) {
    const s = await rows(
      db()
        .from("stories")
        .insert({ author_id: await uid(), title, description, kind })
        .select()
        .single(),
    );
    if (genreIds.length)
      await run(
        db()
          .from("story_genres")
          .insert(genreIds.map((g) => ({ story_id: s.id, genre_id: g }))),
      );
    return s;
  }
  const updateStory = (id, patch) =>
    run(db().from("stories").update({ title: patch.title, description: patch.description, progress: patch.progress }).eq("id", id));
  /* Đổi thể loại của truyện đã đăng: chỉ xóa thể loại bị bỏ tick, chỉ thêm thể loại mới tick (RLS sg_write: chủ truyện hoặc admin) */
  async function setStoryGenres(storyId, genreIds = []) {
    const want = new Set(genreIds.map(Number));
    const cur = (await rows(db().from("story_genres").select("genre_id").eq("story_id", storyId))).map((r) => r.genre_id);
    const drop = cur.filter((g) => !want.has(g));
    const add = [...want].filter((g) => !cur.includes(g));
    if (drop.length) await run(db().from("story_genres").delete().eq("story_id", storyId).in("genre_id", drop));
    if (add.length)
      await run(db().from("story_genres").insert(add.map((g) => ({ story_id: storyId, genre_id: g }))));
  }
  const myStories = async () =>
    rows(
      db()
        .from("stories")
        .select("id,title,status,kind,cover_key,view_count,chapter_count,updated_at")
        .eq("author_id", await uid())
        .order("updated_at", { ascending: false }),
    );
  // Số chương do DB tự gán (trigger chapters_number). Nội dung chữ nằm ở bảng chapter_contents; lỗi thì hoàn tác chương vừa tạo.
  async function addChapter(storyId, { title, content = null, publishAt = null }) {
    const c = await rows(
      db().from("chapters").insert({ story_id: storyId, title, publish_at: publishAt }).select().single(),
    );
    if (content != null) {
      try {
        await run(db().from("chapter_contents").insert({ chapter_id: c.id, content }));
      } catch (e) {
        await deleteChapter(c.id).catch(() => {});
        throw e;
      }
    }
    return c;
  }
  // publishAt: undefined = giữ nguyên · null = phát hành ngay · chuỗi ISO = hẹn giờ
  async function updateChapter(id, { title, content, publishAt }) {
    const patch = { title };
    if (publishAt !== undefined) patch.publish_at = publishAt;
    await run(db().from("chapters").update(patch).eq("id", id));
    if (content != null)
      await run(db().from("chapter_contents").upsert({ chapter_id: id, content }, { onConflict: "chapter_id" }));
  }
  const deleteChapter = (id) => run(db().from("chapters").delete().eq("id", id));
  async function addComicChapter(storyId, { title, files, onProgress, publishAt = null }) {
    // tạo chương + tải ảnh; lỗi thì hoàn tác
    const c = await addChapter(storyId, { title, publishAt });
    try {
      const pages = await uploadChapterPages(storyId, c.number, files, onProgress);
      await run(
        db()
          .from("chapter_pages")
          .insert(pages.map((p, i) => ({ chapter_id: c.id, page_no: i + 1, ...p }))),
      );
      return c;
    } catch (e) {
      await deleteChapter(c.id).catch(() => {});
      throw e;
    }
  }
  const storyStats = (storyId, days = 30) =>
    rows(
      db()
        .from("story_views_daily")
        .select("day,views")
        .eq("story_id", storyId)
        .gte("day", new Date(Date.now() - days * 864e5).toISOString().slice(0, 10))
        .order("day"),
    );

  const pendingStories = () =>
    rows(
      db()
        .from("stories")
        .select("id,title,description,created_at,profiles!author_id(display_name)")
        .eq("status", "pending")
        .order("created_at"),
    );
  const adminStories = (status = "published", page = 0) =>
    rows(
      db()
        .from("stories")
        .select("id,title,status,view_count,chapter_count,created_at,profiles!author_id(display_name)")
        .eq("status", status)
        .order("updated_at", { ascending: false })
        .range(page * PAGE, page * PAGE + PAGE - 1),
    );
  // mode: "visible" (đang hiển thị) | "auto" (bị tự ẩn vì từ khóa cấm, chờ duyệt) | "hidden" (mọi bình luận đã ẩn). q: tìm theo nội dung.
  const adminComments = (mode = "visible", page = 0, q = "") => {
    if (mode === true) mode = "hidden";
    if (mode === false) mode = "visible";
    let query = db()
      .from("comments")
      .select("id,body,created_at,is_hidden,auto_hidden,hidden_reason,story_id,chapter_id,user_id,stories(title),chapters(number),profiles!user_id(display_name,is_locked,role)")
      .order("created_at", { ascending: false })
      .range(page * PAGE, page * PAGE + PAGE - 1);
    query = mode === "visible" ? query.eq("is_hidden", false) : mode === "auto" ? query.eq("is_hidden", true).eq("auto_hidden", true) : query.eq("is_hidden", true);
    const k = clean(q);
    if (k) query = query.ilike("body", `%${k}%`);
    return rows(query);
  };
  // Từ khóa cấm: bình luận chứa từ này sẽ bị ẩn tự động
  const listBannedWords = () => rows(db().from("banned_words").select("id,word,mode,created_at").order("created_at", { ascending: false }).limit(1000));
  const addBannedWord = (word, mode = "word") => run(db().from("banned_words").insert({ word: String(word || "").trim().slice(0, 100), mode }));
  const deleteBannedWord = (id) => run(db().from("banned_words").delete().eq("id", id));
  // Quét bình luận đang hiển thị theo danh sách hiện tại; trả về số bình luận vừa bị ẩn
  const adminApplyBannedWords = async () => (await run(db().rpc("admin_apply_banned_words"))).data;
  const setStoryStatus = (id, status) => run(db().from("stories").update({ status }).eq("id", id));
  const listUsers = (page = 0) =>
    rows(
      db()
        .from("profiles")
        .select("id,display_name,role,is_locked,created_at,user_restrictions!user_id(until_at,reason)")
        .order("created_at", { ascending: false })
        .range(page * PAGE, page * PAGE + PAGE - 1),
    );
  const setUserLocked = (userId, locked, reason = null) => run(db().rpc("admin_set_locked", { uid: userId, locked, p_reason: reason }));
  const addGenre = (name, slug) => run(db().from("genres").insert({ name, slug }));
  const deleteGenre = (id) => run(db().from("genres").delete().eq("id", id));
  const hideComment = (id, hidden = true) =>
    run(db().from("comments").update({ is_hidden: hidden }).eq("id", id));

  // Danh sách truyện đã đăng kèm chính sách hiện tại, có tìm theo tên
  const adminAccessStories = (q = "", page = 0) => {
    let query = db()
      .from("stories")
      .select("id,title,kind,access_policy,price,chapter_count,profiles!author_id(display_name)")
      .eq("status", "published");
    const k = clean(q);
    if (k) query = query.ilike("title", `%${k}%`);
    return rows(query.order("title").range(page * PAGE, page * PAGE + PAGE - 1));
  };
  // Đặt chính sách (free | paid | mixed) và danh sách chương đọc thử (mảng id chương) trong một lần gọi
  const adminSetStoryAccess = (storyId, policy, previewIds = null) =>
    run(db().rpc("admin_set_story_access", { p_story: storyId, p_policy: policy, p_preview_ids: previewIds }));
  // Gói đang bán (khách/thành viên) hoặc toàn bộ gói kể cả đã ngừng (admin)
  const listPlans = () =>
    rows(db().from("plans").select("*").eq("is_active", true).order("price"));
  const adminListPlans = () => rows(db().from("plans").select("*,plan_stories(story_id,stories(title))").order("id"));
  // plan: { id?, name, description, price, duration_days, scope: 'all'|'selected' }; storyIds chỉ dùng khi scope = 'selected'
  async function savePlan(plan, storyIds = []) {
    const f = {
      name: String(plan.name || "").trim(),
      description: plan.description || null,
      price: Math.round(Number(plan.price)),
      duration_days: Math.round(Number(plan.duration_days)),
      scope: plan.scope,
    };
    const saved = plan.id
      ? await rows(db().from("plans").update(f).eq("id", plan.id).select().single())
      : await rows(db().from("plans").insert(f).select().single());
    await setPlanStories(saved.id, plan.scope === "selected" ? storyIds : []);
    return saved;
  }
  async function setPlanStories(planId, storyIds = []) {
    const want = new Set(storyIds.map(Number));
    const cur = (await rows(db().from("plan_stories").select("story_id").eq("plan_id", planId))).map((r) => r.story_id);
    const drop = cur.filter((g) => !want.has(g));
    const add = [...want].filter((g) => !cur.includes(g));
    if (drop.length) await run(db().from("plan_stories").delete().eq("plan_id", planId).in("story_id", drop));
    if (add.length) await run(db().from("plan_stories").insert(add.map((g) => ({ plan_id: planId, story_id: g }))));
  }
  const setPlanActive = (id, active) => run(db().from("plans").update({ is_active: active }).eq("id", id));
  const deletePlan = (id) => run(db().from("plans").delete().eq("id", id));

  async function callFn(name, body) {
    const { data, error } = await db().functions.invoke(name, { body });
    if (error || !data) {
      let m = error?.message || "Không gọi được máy chủ thanh toán.";
      try {
        m = (await error.context.json()).error || m;
      } catch (_) {
        // không đọc được phản hồi JSON = request không tới được hàm (chưa deploy, sai project, lỗi CORS hoặc hàm sập khi khởi động)
        if (error?.name === "FunctionsFetchError") m = "Không kết nối được máy chủ thanh toán. Hàm \"" + name + "\" có thể chưa được deploy hoặc đang lỗi, hãy thử lại sau.";
      }
      throw new Error(m);
    }
    return data;
  }
  // Tạo đơn mua gói đọc. Trả về { orderId, payUrl }; giá lấy từ DB phía máy chủ, không gửi từ client.
  const createPayment = (planId) => callFn("create-payment", { kind: "plan", planId });
  const getOrder = (orderId) =>
    rows(
      db()
        .from("orders")
        .select("id,status,kind,amount,currency,provider,fail_reason,created_at,paid_at,plans(name,duration_days),stories(id,title)")
        .eq("id", orderId)
        .single(),
    );
  // CHỈ DÙNG KHI THỬ (PAYMENT_PROVIDER=mock): giả lập cổng báo thành công/thất bại. Chạy thật thì máy chủ từ chối.
  const mockPay = (orderId, success) => callFn("payment-webhook", { provider: "mock", orderId, result: success ? "success" : "fail" });

  // Admin đặt giá bán lẻ (VND); null = ngừng bán lẻ. Giá cũ được ghi vào story_price_log, đơn đã tạo giữ giá cũ.
  const adminSetStoryPrice = (storyId, price) =>
    run(db().rpc("admin_set_story_price", { p_story: storyId, p_price: price == null || price === "" ? null : Math.round(Number(price)) }));
  // Cập nhật số chương/"mới cập nhật" cho chương hẹn giờ đã tới hạn. Dự phòng khi chưa bật pg_cron; tối đa 1 lần/5 phút/trình duyệt.
  function releaseDueChapters() {
    try {
      const last = +sessionStorage.getItem("rdc") || 0;
      if (Date.now() - last < 5 * 60e3) return;
      sessionStorage.setItem("rdc", String(Date.now()));
    } catch (_) {}
    db().rpc("release_due_chapters").then(() => {}, () => {});
  }
  // Nguồn quyền đọc của người đang đăng nhập với truyện này: { purchased, subscription: {plan_name, expires_at} | null }
  const myStoryAccess = (storyId) => rows(db().rpc("story_access_info", { p_story: storyId }));
  // Mua lẻ truyện: giá lấy từ stories.price phía máy chủ; trả 409 nếu đã có quyền đọc (không phải trả lại)
  const createStoryPayment = (storyId) => callFn("create-payment", { kind: "story", storyId });
  // Lịch sử của tôi. RLS chỉ trả dữ liệu của chính người dùng.
  const mySubscriptions = () =>
    rows(db().from("subscriptions").select("id,plan_id,starts_at,expires_at,plans(name,scope,duration_days)").order("expires_at", { ascending: false }));
  const myPurchases = () =>
    rows(db().from("story_purchases").select("created_at,stories(id,title,cover_key)").order("created_at", { ascending: false }));
  const myOrders = (page = 0) =>
    rows(
      db()
        .from("orders")
        .select("id,status,kind,amount,created_at,paid_at,fail_reason,plans(name),stories(id,title)")
        .order("created_at", { ascending: false })
        .range(page * PAGE, page * PAGE + PAGE - 1),
    );

  // Hàng đợi báo cáo gộp theo bình luận. open=true: đang chờ; false: đã xử lý
  const adminReportQueue = (open = true, page = 0) =>
    rows(db().rpc("admin_report_queue", { p_open: open, p_limit: PAGE, p_offset: page * PAGE }));
  // action: 'hide' (ẩn bình luận) | 'dismiss' (bỏ qua báo cáo)
  const adminHandleReports = (commentId, action, note = null) =>
    run(db().rpc("admin_handle_reports", { p_comment: commentId, p_action: action, p_note: note }));
  // Hạn chế bình luận p_days ngày (1–365); days = 0 để gỡ hạn chế
  const adminRestrictUser = (userId, days, reason = null) =>
    run(db().rpc("admin_restrict_user", { p_user: userId, p_days: days, p_reason: reason }));

  // Thông báo chương mới
  const listNotifications = (page = 0) =>
    rows(
      db()
        .from("notifications")
        .select("id,story_id,chapter_id,story_title,chapter_number,chapter_title,created_at,read_at")
        .order("created_at", { ascending: false })
        .range(page * PAGE, page * PAGE + PAGE - 1),
    );
  async function unreadNotificationCount() {
    if (!(await currentUser())) return 0;
    const { count } = await run(db().from("notifications").select("id", { count: "exact", head: true }).is("read_at", null));
    return count || 0;
  }
  // ids = null: đánh dấu tất cả đã đọc
  async function markNotificationsRead(ids = null) {
    let q = db().from("notifications").update({ read_at: new Date().toISOString() }).is("read_at", null);
    if (ids) q = q.in("id", ids);
    await run(q);
  }
  const deleteNotification = (id) => run(db().from("notifications").delete().eq("id", id));

  // Đối soát giao dịch. status: pending|paid|failed|cancelled hoặc null = tất cả
  const adminOrders = ({ status = null, onlyIssues = false, page = 0 } = {}) =>
    rows(db().rpc("admin_orders_list", { p_status: status, p_only_issues: onlyIssues, p_limit: PAGE, p_offset: page * PAGE }));
  const adminOrderSummary = () => rows(db().rpc("admin_order_summary"));
  // action: regrant | cancel | manual_confirm | ignore (hai thao tác sau bắt buộc ghi chú). Trả về trạng thái đơn sau xử lý.
  const adminFixOrder = (orderId, action, note = null) =>
    rows(db().rpc("admin_fix_order", { p_order: orderId, p_action: action, p_note: note }));

  // Thống kê thành viên & gói. from/to dạng 'YYYY-MM-DD'; group: 'day' | 'month'
  const adminMemberStats = (from, to, group = "day") =>
    rows(db().rpc("admin_member_stats", { p_from: from, p_to: to, p_group: group }));

  // from/to dạng 'YYYY-MM-DD'; group: 'day' | 'month'. Doanh thu = đơn đã thanh toán, tính theo ngày thanh toán (giờ Việt Nam).
  const adminRevenuePlans = (from, to, group = "day") =>
    rows(db().rpc("admin_revenue_plans", { p_from: from, p_to: to, p_group: group }));
  // storyId = null: tất cả truyện; có storyId: chỉ truyện đó
  const adminRevenueStories = (from, to, group = "day", storyId = null) =>
    rows(db().rpc("admin_revenue_stories", { p_from: from, p_to: to, p_group: group, p_story: storyId }));
  const adminContentStats = (from, to, limit = 10) =>
    rows(db().rpc("admin_content_stats", { p_from: from, p_to: to, p_limit: limit }));
  // Nhật ký kiểm duyệt: ai ẩn bình luận, hạn chế, khóa... và khi nào
  const adminModerationLog = (page = 0) =>
    rows(
      db()
        .from("moderation_log")
        .select("id,action,reason,until_at,created_at,comment_id,admin:profiles!admin_id(display_name),target:profiles!target_user(display_name)")
        .order("created_at", { ascending: false })
        .range(page * PAGE, page * PAGE + PAGE - 1),
    );

  const imgUrl = (key, thumb = false) =>
    key ? cfg.IMG_BASE + (thumb ? key.replace(/\.webp$/, "_s.webp") : key) : "";
  async function compressImage(file, maxW = 1080, quality = 0.8) {
    const bmp = await createImageBitmap(file);
    const r = Math.min(1, maxW / bmp.width),
      w = Math.round(bmp.width * r),
      h = Math.round(bmp.height * r);
    const c = document.createElement("canvas");
    c.width = w;
    c.height = h;
    c.getContext("2d").drawImage(bmp, 0, 0, w, h);
    const blob = await new Promise((res) => c.toBlob(res, "image/webp", quality));
    if (!blob || blob.type !== "image/webp") throw new Error("Trình duyệt không hỗ trợ xuất ảnh WebP.");
    return { blob, width: w, height: h };
  }
  async function uploadImage(blob, key) {
    const { data, error } = await db().functions.invoke("r2-upload-url", {
      body: { key, contentType: "image/webp", size: blob.size },
    });
    if (error || !data?.url) {
      let m = error?.message || "Không lấy được link upload.";
      try {
        m = (await error.context.json()).error || m;
      } catch (_) {
        // không đọc được phản hồi JSON = request không tới được hàm (chưa deploy, sai project, lỗi CORS hoặc hàm sập khi khởi động)
        if (error?.name === "FunctionsFetchError") m = "Không kết nối được máy chủ thanh toán. Hàm \"" + name + "\" có thể chưa được deploy hoặc đang lỗi, hãy thử lại sau.";
      }
      throw new Error(m);
    }
    const r = await fetch(data.url, { method: "PUT", headers: { "Content-Type": "image/webp" }, body: blob });
    if (!r.ok) throw new Error(`Upload ảnh thất bại (${r.status}). Kiểm tra CORS của bucket R2.`);
    return key;
  }
  async function uploadCover(storyId, file) {
    const key = `covers/${storyId}.webp`;
    await uploadImage((await compressImage(file, 600)).blob, key);
    await uploadImage((await compressImage(file, 300)).blob, `covers/${storyId}_s.webp`);
    await run(db().from("stories").update({ cover_key: key }).eq("id", storyId));
    return key;
  }
  async function uploadChapterPages(storyId, number, files, onProgress = () => {}) {
    const list = [...files].sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
    const out = new Array(list.length);
    let next = 0,
      done = 0;
    const worker = async () => {
      while (next < list.length) {
        const i = next++,
          { blob, width, height } = await compressImage(list[i]);
        const key = `s${storyId}/c${number}/${String(i + 1).padStart(3, "0")}.webp`;
        await uploadImage(blob, key);
        out[i] = { image_key: key, width, height };
        onProgress(++done, list.length);
      }
    };
    await Promise.all([worker(), worker(), worker()]);
    return out;
  }

  window.API = {
    configured: !!sb,
    PAGE,
    currentUser,
    signUp,
    signIn,
    signOut,
    getProfile,
    becomeAuthor,
    listGenres,
    listStories,
    getStory,
    listChapters,
    getChapter,
    trackView,
    isFollowing,
    toggleFollow,
    myFollows,
    saveHistory,
    getResume,
    getHistory,
    listComments,
    listChapterComments,
    reportComment,
    myRestriction,
    adminReportQueue,
    adminHandleReports,
    adminRestrictUser,
    listNotifications,
    unreadNotificationCount,
    markNotificationsRead,
    deleteNotification,
    adminOrders,
    adminOrderSummary,
    adminFixOrder,
    adminMemberStats,
    adminRevenuePlans,
    adminRevenueStories,
    adminContentStats,
    adminModerationLog,
    addComment,
    deleteComment,
    rate,
    myRating,
    createStory,
    updateStory,
    setStoryGenres,
    myStories,
    addChapter,
    updateChapter,
    deleteChapter,
    addComicChapter,
    storyStats,
    pendingStories,
    adminStories,
    adminComments,
    listBannedWords,
    addBannedWord,
    deleteBannedWord,
    adminApplyBannedWords,
    setStoryStatus,
    listUsers,
    setUserLocked,
    addGenre,
    deleteGenre,
    hideComment,
    PAGE,
    canReadChapter,
    adminSetStoryPrice,
    releaseDueChapters,
    myStoryAccess,
    createStoryPayment,
    mySubscriptions,
    myPurchases,
    myOrders,
    hasStoryAccess,
    adminAccessStories,
    adminSetStoryAccess,
    listPlans,
    adminListPlans,
    savePlan,
    setPlanStories,
    setPlanActive,
    deletePlan,
    createPayment,
    getOrder,
    mockPay,
    imgUrl,
    compressImage,
    uploadImage,
    uploadCover,
    uploadChapterPages,
  };
})();
