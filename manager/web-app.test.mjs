import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const managerRoot = path.dirname(fileURLToPath(import.meta.url));

test("运行中的管理页随心跳显示会话结束，不重绘主题编辑区域", async () => {
  const source = await fs.readFile(path.join(managerRoot, "web", "app.js"), "utf8");
  const elements = new Map();
  function element() {
    return {
      classList: { toggle() {}, add() {}, remove() {} },
      addEventListener() {}, append() {}, replacements: 0,
      replaceChildren() { this.replacements++; },
    };
  }
  let heartbeat;
  const context = vm.createContext({
    URLSearchParams,
    location: { hash: "", search: "", pathname: "/" },
    sessionStorage: { getItem() { return "test-token"; } },
    history: { replaceState() {} },
    document: {
      getElementById(id) {
        if (!elements.has(id)) elements.set(id, element());
        return elements.get(id);
      },
      querySelectorAll() { return []; }, createElement: element,
    },
    fetch() { throw new Error("UI test must not access live services"); },
    async requestJson(_fetch, _token, apiPath) {
      if (apiPath === "/api/heartbeat") return { session: { active: false, state: "stale" } };
      assert.equal(apiPath, "/api/bootstrap");
      return { themes: [], session: { active: true, state: "active" } };
    },
    setInterval(callback) { heartbeat = callback; },
  });
  vm.runInContext(source.replace(/^import[^\n]+\n/, ""), context);
  await new Promise(setImmediate);
  assert.equal(elements.get("session-text").textContent, "Codex 主题会话运行中");
  const replacements = elements.get("theme-sections").replacements;
  heartbeat();
  await new Promise(setImmediate);
  assert.match(elements.get("session-text").textContent, /更新或关闭后需重新启用/);
  assert.equal(elements.get("start-session").textContent, "重新启用主题");
  assert.equal(elements.get("theme-sections").replacements, replacements);
});

test("管理器预览使用真实 DOM ID，令牌在当前标签页刷新后可恢复", async () => {
  const source = await fs.readFile(path.join(managerRoot, "web", "app.js"), "utf8");

  assert.doesNotMatch(source, /elements\.(?:previewImage|previewOverlay)\b/);
  assert.match(source, /sessionStorage\.getItem\("dreamSkinManagerToken"\)/);
  assert.match(source, /query\.get\("bootstrap"\)/);
  assert.match(source, /sessionStorage\.setItem\("dreamSkinManagerToken", launchToken\)/);
  assert.match(source, /history\.replaceState\(null, "", location\.pathname\)/);
});

test("遮罩调节使用面向用户的背景压暗名称", async () => {
  const html = await fs.readFile(path.join(managerRoot, "web", "index.html"), "utf8");

  assert.match(html, />背景压暗程度</);
  assert.doesNotMatch(html, />暗色遮罩</);
});

test("管理器提供界面底色强度并参与预览与提交", async () => {
  const [html, source] = await Promise.all([
    fs.readFile(path.join(managerRoot, "web", "index.html"), "utf8"),
    fs.readFile(path.join(managerRoot, "web", "app.js"), "utf8"),
  ]);

  assert.match(html, />界面底色强度</);
  assert.match(html, /id="surface"[^>]*min="0\.2"[^>]*max="1"/);
  assert.match(source, /surfaceOpacity:\s*Number\(elements\.surface\.value\)/);
  assert.match(source, /--preview-surface-opacity/);
});
