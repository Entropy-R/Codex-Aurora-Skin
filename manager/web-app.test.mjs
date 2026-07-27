import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const managerRoot = path.dirname(fileURLToPath(import.meta.url));

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
