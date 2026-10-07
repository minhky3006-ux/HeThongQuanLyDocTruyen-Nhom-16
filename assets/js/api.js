/* api.js — lớp DUY NHẤT nói chuyện với Supabase và R2. Trang HTML chỉ gọi API.xxx(), không tự viết truy vấn. */
(() => {
  const cfg = window.APP_CONFIG || {};
  const sb =
    cfg.SUPABASE_URL && window.supabase
      ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY)
      : null;
  const PAGE = 20;
  const CARD = "id,title,cover_key,rating_avg,view_count,chapter_count,profiles(display_name)";
  const MSG = {
    "Invalid login credentials": "Sai email hoặc mật khẩu.",
    "User already registered": "Email này đã được đăng ký.",
    "Password should be": "Mật khẩu cần tối thiểu 6 ký tự.",
    "JSON object requested": "Không tìm thấy dữ liệu.",
    "row-level security": "Bạn không có quyền thực hiện thao tác này.",
    "Email not confirmed": "Hãy xác nhận email trước khi đăng nhập.",
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

  /* ===== Tài khoản (story 5, 6, 11) ===== */
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
      options: { data: { display_name: displayName } },
    });
    if (error) throw new Error(vi(error.message));
    if (data.session && asAuthor) await becomeAuthor();
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

  /* ===== Đọc truyện (story 1–4, 7) ===== */
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
    const col = { new: "updated_at", hot: "view_count", rating: "rating_avg" }[sort] || "updated_at";
    const { data, count } = await run(
      query.order(col, { ascending: false }).range(page * PAGE, page * PAGE + PAGE - 1),
    );
    return { items: data.map(withAuthor), total: count ?? 0 };
  }
  async function getStory(id) {
    const s = await rows(
      db()
        .from("stories")
        .select("*,profiles(display_name),story_genres(genres(id,name))")
        .eq("id", id)
        .single(),
    );
    return { ...withAuthor(s), genres: (s.story_genres || []).map((x) => x.genres) };
  }
  const listChapters = (storyId) =>
    rows(db().from("chapters").select("id,number,title,created_at").eq("story_id", storyId).order("number"));
  async function getChapter(storyId, number) {
    const c = await rows(
      db()
        .from("chapters")
        .select("*,chapter_pages(page_no,image_key,width,height)")
        .eq("story_id", storyId)
        .eq("number", number)
        .single(),
    );
    c.chapter_pages = (c.chapter_pages || []).sort((a, b) => a.page_no - b.page_no);
    return c;
  }
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

  /* ===== Thành viên (story 8, 9, 10) ===== */
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
    await db()
      .from("reading_history")
      .upsert(
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
        .select("id,body,created_at,user_id,profiles(display_name)")
        .eq("story_id", storyId)
        .order("created_at", { ascending: false })
        .range(page * PAGE, page * PAGE + PAGE - 1),
    );
  async function addComment(storyId, body, chapterId = null) {
    await run(
      db()
        .from("comments")
        .insert({ story_id: storyId, chapter_id: chapterId, user_id: await uid(), body: body.trim() }),
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

  /* ===== Tác giả (story 12, 13, 14) ===== */
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
    run(db().from("stories").update({ title: patch.title, description: patch.description }).eq("id", id));
  const myStories = async () =>
    rows(
      db()
        .from("stories")
        .select("id,title,status,kind,cover_key,view_count,chapter_count,updated_at")
        .eq("author_id", await uid())
        .order("updated_at", { ascending: false }),
    );
  async function addChapter(storyId, { title, content = null }) {
    const last = await rows(
      db()
        .from("chapters")
        .select("number")
        .eq("story_id", storyId)
        .order("number", { ascending: false })
        .limit(1),
    );
    return rows(
      db()
        .from("chapters")
        .insert({ story_id: storyId, number: (last[0]?.number || 0) + 1, title, content })
        .select()
        .single(),
    );
  }
  const updateChapter = (id, { title, content }) =>
    run(db().from("chapters").update({ title, content }).eq("id", id));
  const deleteChapter = (id) => run(db().from("chapters").delete().eq("id", id));
  async function addComicChapter(storyId, { title, files, onProgress }) {
    // tạo chương + tải ảnh; lỗi thì hoàn tác
    const c = await addChapter(storyId, { title });
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

  /* ===== Quản trị viên (Sprint 2: story 15–18) ===== */
  const pendingStories = () =>
    rows(
      db()
        .from("stories")
        .select("id,title,description,created_at,profiles(display_name)")
        .eq("status", "pending")
        .order("created_at"),
    );
  const setStoryStatus = (id, status) => run(db().from("stories").update({ status }).eq("id", id));
  const listUsers = (page = 0) =>
    rows(
      db()
        .from("profiles")
        .select("id,display_name,role,is_locked,created_at")
        .order("created_at", { ascending: false })
        .range(page * PAGE, page * PAGE + PAGE - 1),
    );
  const setUserLocked = (userId, locked) => run(db().rpc("admin_set_locked", { uid: userId, locked }));
  const addGenre = (name, slug) => run(db().from("genres").insert({ name, slug }));
  const deleteGenre = (id) => run(db().from("genres").delete().eq("id", id));
  const hideComment = (id, hidden = true) =>
    run(db().from("comments").update({ is_hidden: hidden }).eq("id", id));

  /* ===== Ảnh: nén WebP trên trình duyệt, upload lên R2 qua link tạm ===== */
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
      body: { key, contentType: "image/webp" },
    });
    if (error || !data?.url) {
      let m = error?.message || "Không lấy được link upload.";
      try {
        m = (await error.context.json()).error || m;
      } catch (_) {}
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
    addComment,
    deleteComment,
    rate,
    myRating,
    createStory,
    updateStory,
    myStories,
    addChapter,
    updateChapter,
    deleteChapter,
    addComicChapter,
    storyStats,
    pendingStories,
    setStoryStatus,
    listUsers,
    setUserLocked,
    addGenre,
    deleteGenre,
    hideComment,
    imgUrl,
    compressImage,
    uploadImage,
    uploadCover,
    uploadChapterPages,
  };
})();
