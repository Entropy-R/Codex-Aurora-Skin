#!/usr/bin/env node

import http from "node:http";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { randomBytes } from "node:crypto";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import { ThemeStore, VISUAL_LIMITS } from "./theme-store.mjs";
import { HeartbeatLease } from "./heartbeat-lease.mjs";

const execFileAsync = promisify(execFile);
const here = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.join(here, "web");
const MAX_JSON_BYTES = 64 * 1024;
const MAX_IMPORT_BYTES = 18 * 1024 * 1024;
const HEARTBEAT_TIMEOUT_MS = 120_000;
const HEARTBEAT_SUSPEND_GAP_MS = 15_000;
const ACTIVE_VERIFY_TIMEOUT_MS = 45_000;

function parseArgs(argv) {
  const options = {
    platform: process.platform === "darwin"
      ? "macos"
      : process.platform === "win32"
        ? "windows"
        : process.platform === "linux" ? "linux" : process.platform,
    engineRoot: path.resolve(here, ".."),
    stateRoot: null,
    activeRoot: null,
    nodePath: process.execPath,
    injectorPath: null,
    startScript: null,
    restoreScript: null,
    open: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--platform") options.platform = argv[++index];
    else if (arg === "--engine-root") options.engineRoot = path.resolve(argv[++index]);
    else if (arg === "--state-root") options.stateRoot = path.resolve(argv[++index]);
    else if (arg === "--active-root") options.activeRoot = path.resolve(argv[++index]);
    else if (arg === "--node") options.nodePath = path.resolve(argv[++index]);
    else if (arg === "--injector") options.injectorPath = path.resolve(argv[++index]);
    else if (arg === "--start-script" || arg === "--start") options.startScript = path.resolve(argv[++index]);
    else if (arg === "--restore-script" || arg === "--restore") options.restoreScript = path.resolve(argv[++index]);
    else if (arg === "--open") options.open = true;
    else throw new Error(`未知管理器参数：${arg}`);
  }
  if (!["windows", "macos", "linux"].includes(options.platform)) {
    throw new Error("平台参数不受支持");
  }
  for (const [key, value] of Object.entries({
    stateRoot: options.stateRoot,
    activeRoot: options.activeRoot,
    injectorPath: options.injectorPath,
    startScript: options.startScript,
    restoreScript: options.restoreScript,
  })) {
    if (!value) throw new Error(`缺少管理器参数：${key}`);
  }
  return options;
}

const options = parseArgs(process.argv.slice(2));
const token = randomBytes(32).toString("hex");
const sessionPath = path.join(options.stateRoot, "manager-session.json");
const heartbeatLease = new HeartbeatLease({
  timeoutMs: HEARTBEAT_TIMEOUT_MS,
  suspendGapMs: HEARTBEAT_SUSPEND_GAP_MS,
});
let shuttingDown = false;
let server;

async function readJson(file, fallback = null) {
  try {
    return JSON.parse(await fs.readFile(file, "utf8"));
  } catch {
    return fallback;
  }
}

async function writeJsonAtomic(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  const temporary = `${file}.${process.pid}.${randomBytes(4).toString("hex")}.tmp`;
  await fs.writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  await fs.rename(temporary, file);
}

function managerUrl(port, secret = token) {
  // Windows 通过 Shell 打开 URL 时可能丢失 fragment。启动令牌改放在
  // 一次性查询参数中，前端读取后立即写入当前标签页并清理地址栏。
  return `http://127.0.0.1:${port}/?bootstrap=${secret}`;
}

async function openBrowser(url) {
  const command = options.platform === "macos"
    ? "/usr/bin/open"
    : options.platform === "linux" ? "xdg-open" : "explorer.exe";
  const child = spawn(command, [url], { detached: true, stdio: "ignore", windowsHide: true });
  child.unref();
}

async function existingManager() {
  const snapshot = await readJson(sessionPath);
  if (!snapshot || !Number.isInteger(snapshot.pid) || !Number.isInteger(snapshot.port) ||
      !/^[a-f0-9]{64}$/.test(snapshot.token || "")) return null;
  try {
    process.kill(snapshot.pid, 0);
    const response = await fetch(`http://127.0.0.1:${snapshot.port}/api/ping`, {
      headers: { Authorization: `Bearer ${snapshot.token}` },
      signal: AbortSignal.timeout(900),
    });
    if (response.ok) return snapshot;
  } catch {}
  return null;
}

const currentManager = await existingManager();
if (currentManager) {
  if (options.open) await openBrowser(managerUrl(currentManager.port, currentManager.token));
  process.stdout.write(`MANAGER_URL=${managerUrl(currentManager.port, currentManager.token)}\n`);
  process.exit(0);
}

const store = await new ThemeStore({
  engineRoot: options.engineRoot,
  stateRoot: options.stateRoot,
  activeRoot: options.activeRoot,
}).initialize();

function sendJson(response, status, value) {
  const body = Buffer.from(`${JSON.stringify(value)}\n`);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": body.length,
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
  });
  response.end(body);
}

function sendError(response, status, error) {
  sendJson(response, status, { ok: false, error: error?.message || String(error) });
}

async function readBody(request, limit) {
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > limit) throw Object.assign(new Error("请求体超过允许大小"), { statusCode: 413 });
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function readRequestJson(request) {
  const bytes = await readBody(request, MAX_JSON_BYTES);
  if (!bytes.length) return {};
  const value = JSON.parse(bytes.toString("utf8"));
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("JSON 请求必须是对象");
  return value;
}

function authenticated(request) {
  return request.headers.authorization === `Bearer ${token}`;
}

function validOrigin(request, port) {
  const expectedHost = `127.0.0.1:${port}`;
  if (request.headers.host !== expectedHost) return false;
  const origin = request.headers.origin;
  return !origin || origin === `http://${expectedHost}`;
}

async function sessionStatus() {
  const state = await readJson(path.join(options.stateRoot, "state.json"));
  if (!state || !Number.isInteger(Number(state.port))) {
    return { active: false, state: "off", canRestart: true };
  }
  const port = Number(state.port);
  try {
    const response = await fetch(`http://127.0.0.1:${port}/json/version`, {
      signal: AbortSignal.timeout(1000),
    });
    if (!response.ok) throw new Error();
    const version = await response.json();
    if ((options.platform === "windows" || options.platform === "linux") && state.browserId) {
      const id = /^ws:\/\/(?:127\.0\.0\.1|localhost):\d+\/devtools\/browser\/([A-Za-z0-9._-]+)$/
        .exec(String(version.webSocketDebuggerUrl || ""))?.[1];
      if (id !== state.browserId) throw new Error();
    }
    return {
      active: state.session ? state.session === "active" : true,
      state: state.session || "active",
      port,
      appliedThemeId: state.appliedThemeId || await store.activeThemeId(),
      canRestart: true,
    };
  } catch {
    return { active: false, state: "stale", port, canRestart: true };
  }
}

async function runPlatformAction(action) {
  const windows = options.platform === "windows";
  const executable = windows
    ? (process.env.SystemRoot ? path.join(process.env.SystemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe") : "powershell.exe")
    : "/bin/bash";
  const script = action === "start" ? options.startScript : options.restoreScript;
  const args = windows
    ? ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "RemoteSigned", "-File", script,
      action === "start" ? "-RestartExisting" : "-ForceRestart"]
    : [script, action === "start" ? "--restart-existing" : "--restart-codex"];
  const result = await execFileAsync(executable, args, {
    timeout: 150_000,
    windowsHide: true,
    maxBuffer: 2 * 1024 * 1024,
  });
  return { stdout: result.stdout?.trim() || "", stderr: result.stderr?.trim() || "" };
}

async function verifyActive() {
  const status = await sessionStatus();
  if (!status.active) return { applied: false, pending: true };
  const state = await readJson(path.join(options.stateRoot, "state.json"));
  const baseArgs = [
    options.injectorPath,
    "--verify",
    "--port", String(state.port),
    "--theme-dir", options.activeRoot,
    "--timeout-ms", "5000",
  ];
  if (options.platform === "windows") baseArgs.push("--browser-id", String(state.browserId || ""));
  let lastError = null;
  const deadline = Date.now() + ACTIVE_VERIFY_TIMEOUT_MS;
  while (Date.now() < deadline) {
    try {
      await execFileAsync(options.nodePath, baseArgs, {
        timeout: 10_000,
        windowsHide: true,
        maxBuffer: 2 * 1024 * 1024,
      });
      return { applied: true, pending: false };
    } catch (error) {
      lastError = error;
      if (Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 1200));
      }
    }
  }
  throw new Error(`主题热更新校验失败：${lastError?.stderr || lastError?.message || "未知错误"}`);
}

async function applyAndVerify(id) {
  const previousId = await store.activeThemeId();
  await store.applyTheme(id);
  try {
    return await verifyActive();
  } catch (error) {
    if (previousId && previousId !== id) {
      await store.applyTheme(previousId).catch(() => {});
    }
    throw error;
  }
}

async function serveFile(response, file, contentType, extraHeaders = {}) {
  const bytes = await fs.readFile(file);
  response.writeHead(200, {
    "Content-Type": contentType,
    "Content-Length": bytes.length,
    "Cache-Control": contentType.startsWith("image/") ? "private, max-age=300" : "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    ...extraHeaders,
  });
  response.end(bytes);
}

async function routeApi(request, response, url) {
  if (request.method === "GET" && url.pathname === "/api/ping") {
    return sendJson(response, 200, { ok: true, pid: process.pid });
  }
  if (request.method === "POST" && url.pathname === "/api/heartbeat") {
    heartbeatLease.heartbeat();
    return sendJson(response, 200, { ok: true });
  }
  if (request.method === "GET" && url.pathname === "/api/bootstrap") {
    heartbeatLease.heartbeat();
    return sendJson(response, 200, {
      ok: true,
      product: "Codex Aurora Skin",
      themes: await store.listThemes(),
      activeThemeId: await store.activeThemeId(),
      session: await sessionStatus(),
      visualLimits: VISUAL_LIMITS,
    });
  }
  const assetMatch = /^\/api\/themes\/([^/]+)\/(thumbnail|background)$/.exec(url.pathname);
  if (request.method === "GET" && assetMatch) {
    const file = await store.assetPath(decodeURIComponent(assetMatch[1]), assetMatch[2]);
    const extension = path.extname(file).toLowerCase();
    const contentType = extension === ".webp" ? "image/webp"
      : extension === ".png" ? "image/png" : "image/jpeg";
    return serveFile(response, file, contentType);
  }
  const applyMatch = /^\/api\/themes\/([^/]+)\/apply$/.exec(url.pathname);
  if (request.method === "POST" && applyMatch) {
    const id = decodeURIComponent(applyMatch[1]);
    const result = await applyAndVerify(id);
    return sendJson(response, 200, { ok: true, id, ...result });
  }
  const visualMatch = /^\/api\/themes\/([^/]+)\/visual$/.exec(url.pathname);
  if (request.method === "PATCH" && visualMatch) {
    const id = decodeURIComponent(visualMatch[1]);
    const body = await readRequestJson(request);
    const update = body.reset
      ? await store.resetVisual(id, body.mode)
      : await store.updateVisual(id, body.mode, body);
    // 未激活主题没有可供 Codex 验证的画面；只持久化参数，
    // 等用户明确应用该主题后再由 apply 接口完成热验证。
    if (id !== await store.activeThemeId()) {
      return sendJson(response, 200, {
        ok: true,
        id,
        visual: update.visual,
        applied: false,
        pending: true,
      });
    }
    try {
      const result = await verifyActive();
      return sendJson(response, 200, { ok: true, id, visual: update.visual, ...result });
    } catch (error) {
      await store.restoreOverrides(update.previous, id);
      throw error;
    }
  }
  if (request.method === "POST" && url.pathname === "/api/themes/import") {
    const contentType = String(request.headers["content-type"] || "");
    if (!contentType.startsWith("multipart/form-data;")) throw new Error("导入请求必须使用 multipart/form-data");
    const bytes = await readBody(request, MAX_IMPORT_BYTES);
    const fetchRequest = new Request("http://127.0.0.1/api/themes/import", {
      method: "POST",
      headers: { "Content-Type": contentType },
      body: bytes,
    });
    const form = await fetchRequest.formData();
    const image = form.get("image");
    const thumbnail = form.get("thumbnail");
    if (!(image instanceof Blob) || !(thumbnail instanceof Blob)) throw new Error("导入请求缺少图片或缩略图");
    const pack = await store.importTheme({
      name: String(form.get("name") || ""),
      imageBytes: new Uint8Array(await image.arrayBuffer()),
      thumbnailBytes: new Uint8Array(await thumbnail.arrayBuffer()),
    });
    return sendJson(response, 201, { ok: true, id: pack.theme.id });
  }
  const themeMatch = /^\/api\/themes\/([^/]+)$/.exec(url.pathname);
  if (request.method === "PATCH" && themeMatch) {
    const id = decodeURIComponent(themeMatch[1]);
    const body = await readRequestJson(request);
    const name = await store.renameTheme(id, body.name);
    return sendJson(response, 200, { ok: true, id, name });
  }
  if (request.method === "DELETE" && themeMatch) {
    const id = decodeURIComponent(themeMatch[1]);
    const body = await readRequestJson(request);
    await store.deleteTheme(id, body.confirm === true, verifyActive);
    const result = await verifyActive();
    return sendJson(response, 200, { ok: true, id, ...result });
  }
  if (request.method === "POST" && url.pathname === "/api/session/start") {
    const body = await readRequestJson(request);
    if (body.confirmRestart !== true) throw new Error("启动或重启 Codex 需要用户明确确认");
    await runPlatformAction("start");
    return sendJson(response, 200, { ok: true, session: await sessionStatus() });
  }
  if (request.method === "POST" && url.pathname === "/api/restore") {
    const body = await readRequestJson(request);
    if (body.confirm !== true) throw new Error("恢复官方外观需要用户明确确认");
    await runPlatformAction("restore");
    return sendJson(response, 200, { ok: true, session: await sessionStatus() });
  }
  sendJson(response, 404, { ok: false, error: "接口不存在" });
}

server = http.createServer(async (request, response) => {
  const port = server.address()?.port;
  try {
    if (!validOrigin(request, port)) return sendError(response, 403, new Error("请求来源不受信任"));
    const url = new URL(request.url || "/", `http://127.0.0.1:${port}`);
    if (url.pathname.startsWith("/api/")) {
      if (!authenticated(request)) return sendError(response, 401, new Error("管理器令牌无效"));
      return await routeApi(request, response, url);
    }
    if (request.method !== "GET") return sendError(response, 405, new Error("请求方法不受支持"));
    if (url.pathname === "/" || url.pathname === "/index.html") {
      return serveFile(response, path.join(webRoot, "index.html"), "text/html; charset=utf-8", {
        "Content-Security-Policy": "default-src 'self'; img-src 'self' blob:; style-src 'self'; script-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      });
    }
    if (url.pathname === "/app.js") return serveFile(response, path.join(webRoot, "app.js"), "text/javascript; charset=utf-8");
    if (url.pathname === "/api-client.mjs") return serveFile(response, path.join(webRoot, "api-client.mjs"), "text/javascript; charset=utf-8");
    if (url.pathname === "/styles.css") return serveFile(response, path.join(webRoot, "styles.css"), "text/css; charset=utf-8");
    return sendError(response, 404, new Error("页面不存在"));
  } catch (error) {
    sendError(response, error?.statusCode || 400, error);
  }
});

server.listen(0, "127.0.0.1", async () => {
  const port = server.address().port;
  await writeJsonAtomic(sessionPath, { schemaVersion: 1, pid: process.pid, port, token, createdAt: new Date().toISOString() });
  const url = managerUrl(port);
  process.stdout.write(`MANAGER_URL=${url}\n`);
  if (options.open) await openBrowser(url);
});

const idleTimer = setInterval(() => {
  if (!shuttingDown && heartbeatLease.tick() === "expired") {
    shuttingDown = true;
    server.close();
  }
}, 5000);
idleTimer.unref();

async function cleanup() {
  clearInterval(idleTimer);
  const snapshot = await readJson(sessionPath);
  if (snapshot?.pid === process.pid) await fs.rm(sessionPath, { force: true });
}

server.on("close", async () => {
  await cleanup();
  process.exit(0);
});
process.on("SIGINT", () => server.close());
process.on("SIGTERM", () => server.close());
