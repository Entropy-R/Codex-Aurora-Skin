const fragment = new URLSearchParams(location.hash.slice(1));
const fragmentToken = fragment.get("token");
const query = new URLSearchParams(location.search);
const queryToken = query.get("bootstrap");
const launchToken = queryToken || fragmentToken;
const token = launchToken || sessionStorage.getItem("dreamSkinManagerToken");
if (launchToken) {
  // 令牌只保存在当前标签页；刷新可恢复，关闭标签页后不会跨会话持久化。
  sessionStorage.setItem("dreamSkinManagerToken", launchToken);
}
history.replaceState(null, "", location.pathname);

const state = {
  bootstrap: null,
  selectedId: null,
  mode: "light",
  imageUrls: new Map(),
  busy: false,
  dragging: false,
  keyboardTimer: null,
};

const elements = Object.fromEntries([
  "session-dot", "session-text", "start-session", "restore-session", "theme-sections",
  "empty-editor", "theme-editor", "preview", "preview-image", "preview-overlay",
  "active-badge", "theme-source", "theme-name", "user-actions", "rename-theme",
  "delete-theme", "brightness", "brightness-value", "overlay", "overlay-value",
  "surface", "surface-value",
  "reset-visual", "apply-theme", "import-file", "toast",
].map((id) => [id, document.getElementById(id)]));

function toast(message, error = false) {
  elements.toast.textContent = message;
  elements.toast.classList.toggle("error", error);
  elements.toast.classList.add("visible");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => elements.toast.classList.remove("visible"), 3200);
}

async function api(path, options = {}) {
  if (!token) throw new Error("管理器链接缺少安全令牌，请重新打开 Codex Aurora Skin。");
  const response = await fetch(path, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(options.body instanceof FormData ? {} : { "Content-Type": "application/json" }),
      ...options.headers,
    },
  });
  const result = await response.json().catch(() => ({ error: `请求失败：${response.status}` }));
  if (!response.ok || result.ok === false) throw new Error(result.error || `请求失败：${response.status}`);
  return result;
}

function setBusy(busy) {
  state.busy = busy;
  for (const element of document.querySelectorAll("button, .import-button input")) {
    element.disabled = busy;
  }
}

async function authorizedImage(url) {
  if (state.imageUrls.has(url)) return state.imageUrls.get(url);
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error("主题缩略图读取失败");
  const objectUrl = URL.createObjectURL(await response.blob());
  state.imageUrls.set(url, objectUrl);
  return objectUrl;
}

function selectedTheme() {
  return state.bootstrap?.themes.find((theme) => theme.id === state.selectedId) || null;
}

function visualFor(theme) {
  return theme.visual[state.mode];
}

function updatePreview() {
  const theme = selectedTheme();
  if (!theme) return;
  const visual = visualFor(theme);
  const brightness = Number(elements.brightness.value || visual.brightness);
  const overlay = Number(elements.overlay.value || visual.overlayOpacity);
  const surface = Number(elements.surface.value || visual.surfaceOpacity);
  elements.overlay.min = state.mode === "light" ? "0.32" : "0";
  elements.surface.min = state.mode === "light" ? "0.60" : "0.20";
  elements["preview-image"].style.filter = `brightness(${brightness})`;
  elements["preview-overlay"].style.backgroundColor = state.mode === "light" ? "#fff" : "#000";
  elements["preview-overlay"].style.opacity = String(overlay);
  elements.preview.style.setProperty("--preview-surface-opacity", String(surface));
  elements.preview.style.setProperty(
    "--preview-panel-rgb",
    state.mode === "dark" ? "25 28 34" : "250 251 251",
  );
  elements["brightness-value"].value = `${Math.round(brightness * 100)}%`;
  elements["overlay-value"].value = `${Math.round(overlay * 100)}%`;
  elements["surface-value"].value = `${Math.round(surface * 100)}%`;
}

async function renderEditor() {
  const theme = selectedTheme();
  elements["empty-editor"].hidden = Boolean(theme);
  elements["theme-editor"].hidden = !theme;
  if (!theme) return;
  elements["theme-name"].textContent = theme.name;
  elements["theme-source"].textContent = theme.source === "builtin" ? "内置主题" : "用户主题";
  elements["user-actions"].hidden = theme.source !== "user";
  elements["active-badge"].hidden = !theme.active;
  const visual = visualFor(theme);
  elements.brightness.value = visual.brightness;
  elements.overlay.value = visual.overlayOpacity;
  elements.surface.value = visual.surfaceOpacity;
  elements["preview-image"].src = await authorizedImage(theme.previewUrl);
  elements["preview-image"].alt = `${theme.name} 背景预览`;
  updatePreview();
}

function themeCard(theme) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = `theme-card${theme.id === state.selectedId ? " selected" : ""}`;
  button.dataset.themeId = theme.id;
  const image = document.createElement("img");
  image.alt = "";
  authorizedImage(theme.previewUrl).then((url) => { image.src = url; }).catch((error) => toast(error.message, true));
  const name = document.createElement("strong");
  name.textContent = theme.name;
  const label = document.createElement("small");
  label.textContent = theme.active ? "正在使用" : theme.source === "builtin" ? "内置资源" : "本地导入";
  button.append(image, name, label);
  button.addEventListener("click", async () => {
    state.selectedId = theme.id;
    await render();
  });
  return button;
}

function themeGroup(title, themes) {
  const section = document.createElement("section");
  section.className = "theme-group";
  const heading = document.createElement("h3");
  heading.textContent = `${title} · ${themes.length}`;
  const grid = document.createElement("div");
  grid.className = "theme-grid";
  for (const theme of themes) grid.append(themeCard(theme));
  section.append(heading, grid);
  return section;
}

async function render() {
  const themes = state.bootstrap?.themes || [];
  elements["theme-sections"].replaceChildren(
    themeGroup("内置主题", themes.filter((theme) => theme.source === "builtin")),
    themeGroup("用户主题", themes.filter((theme) => theme.source === "user")),
  );
  for (const tab of document.querySelectorAll(".mode-tab")) {
    tab.classList.toggle("active", tab.dataset.mode === state.mode);
  }
  const session = state.bootstrap?.session || { state: "off" };
  elements["session-dot"].className = `status-dot ${session.active ? "active" : session.state === "stale" ? "stale" : ""}`;
  elements["session-text"].textContent = session.active
    ? "Codex 主题会话运行中"
    : session.state === "stale" ? "Codex 需要重新连接" : "Codex 主题会话未启动";
  elements["start-session"].textContent = session.active ? "重新应用会话" : "启动主题会话";
  await renderEditor();
}

async function refresh({ keepSelection = true } = {}) {
  const previous = keepSelection ? state.selectedId : null;
  state.bootstrap = await api("/api/bootstrap");
  state.selectedId = state.bootstrap.themes.some((theme) => theme.id === previous)
    ? previous
    : state.bootstrap.activeThemeId || state.bootstrap.themes[0]?.id || null;
  await render();
}

async function action(work, success) {
  if (state.busy) return;
  setBusy(true);
  try {
    await work();
    await refresh();
    if (success) toast(typeof success === "function" ? success() : success);
  } catch (error) {
    toast(error.message, true);
  } finally {
    setBusy(false);
  }
}

async function commitVisual(reset = false) {
  const theme = selectedTheme();
  if (!theme) return;
  let successMessage = reset ? "已恢复主题默认值。" : "背景参数已应用。";
  await action(async () => {
    const result = await api(`/api/themes/${encodeURIComponent(theme.id)}/visual`, {
      method: "PATCH",
      body: JSON.stringify({
        mode: state.mode,
        brightness: Number(elements.brightness.value),
        overlayOpacity: Number(elements.overlay.value),
        surfaceOpacity: Number(elements.surface.value),
        reset,
      }),
    });
    if (result.pending) {
      successMessage = theme.active
        ? "参数已保存，将在下次启动主题会话时生效。"
        : "参数已保存，应用此主题后生效。";
    }
  }, () => successMessage);
}

for (const tab of document.querySelectorAll(".mode-tab")) {
  tab.addEventListener("click", async () => {
    state.mode = tab.dataset.mode;
    await render();
  });
}

for (const slider of [elements.brightness, elements.overlay, elements.surface]) {
  slider.addEventListener("pointerdown", () => {
    state.dragging = true;
    clearTimeout(state.keyboardTimer);
  });
  slider.addEventListener("input", () => {
    updatePreview();
    if (!state.dragging) {
      clearTimeout(state.keyboardTimer);
      state.keyboardTimer = setTimeout(() => commitVisual(false), 500);
    }
  });
  slider.addEventListener("pointerup", () => {
    state.dragging = false;
    commitVisual(false);
  });
  slider.addEventListener("pointercancel", () => { state.dragging = false; });
}

elements["apply-theme"].addEventListener("click", () => {
  const theme = selectedTheme();
  if (!theme) return;
  action(
    () => api(`/api/themes/${encodeURIComponent(theme.id)}/apply`, { method: "POST", body: "{}" }),
    "主题已应用。",
  );
});

elements["reset-visual"].addEventListener("click", () => commitVisual(true));

elements["start-session"].addEventListener("click", () => {
  if (!confirm("启动主题会话可能需要重启当前 Codex，未发送的输入可能丢失。继续吗？")) return;
  action(
    () => api("/api/session/start", {
      method: "POST",
      body: JSON.stringify({ confirmRestart: true }),
    }),
    "Codex 主题会话已启动。",
  );
});

elements["restore-session"].addEventListener("click", () => {
  if (!confirm("将关闭 Aurora Skin 注入和 CDP 会话，并以官方方式重新打开 Codex。继续吗？")) return;
  action(
    () => api("/api/restore", { method: "POST", body: JSON.stringify({ confirm: true }) }),
    "已恢复官方外观。",
  );
});

elements["rename-theme"].addEventListener("click", () => {
  const theme = selectedTheme();
  const name = theme ? prompt("输入新的主题名称：", theme.name) : null;
  if (name === null) return;
  action(
    () => api(`/api/themes/${encodeURIComponent(theme.id)}`, {
      method: "PATCH",
      body: JSON.stringify({ name }),
    }),
    "主题已重命名。",
  );
});

elements["delete-theme"].addEventListener("click", () => {
  const theme = selectedTheme();
  if (!theme || !confirm(`确认删除本地主题“${theme.name}”？此操作无法撤销。`)) return;
  action(
    () => api(`/api/themes/${encodeURIComponent(theme.id)}`, {
      method: "DELETE",
      body: JSON.stringify({ confirm: true }),
    }),
    "用户主题已删除。",
  );
});

async function makeThumbnail(file) {
  const bitmap = await createImageBitmap(file);
  const canvas = document.createElement("canvas");
  canvas.width = 480;
  canvas.height = 270;
  const context = canvas.getContext("2d", { alpha: false });
  const scale = Math.max(canvas.width / bitmap.width, canvas.height / bitmap.height);
  const width = bitmap.width * scale;
  const height = bitmap.height * scale;
  context.drawImage(bitmap, (canvas.width - width) / 2, (canvas.height - height) / 2, width, height);
  bitmap.close();
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/webp", 0.78));
  if (!blob) throw new Error("浏览器无法生成 WebP 缩略图");
  return blob;
}

elements["import-file"].addEventListener("change", async () => {
  const file = elements["import-file"].files?.[0];
  elements["import-file"].value = "";
  if (!file) return;
  const name = prompt("输入主题名称：", file.name.replace(/\.[^.]+$/, ""));
  if (name === null) return;
  await action(async () => {
    const thumbnail = await makeThumbnail(file);
    const form = new FormData();
    form.append("name", name);
    form.append("image", file, file.name);
    form.append("thumbnail", thumbnail, "thumbnail.webp");
    const result = await api("/api/themes/import", { method: "POST", body: form });
    state.selectedId = result.id;
  }, "图片已导入本地主题库。");
});

setInterval(() => {
  api("/api/heartbeat", { method: "POST", body: "{}" }).catch(() => {});
}, 15_000);

refresh({ keepSelection: false }).catch((error) => toast(error.message, true));
