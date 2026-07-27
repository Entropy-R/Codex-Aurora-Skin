import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ThemeStore, DEFAULT_THEME_ID } from "./theme-store.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

async function fixture(t) {
  const stateRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aurora-skin-store-"));
  t.after(() => fs.rm(stateRoot, { recursive: true, force: true }));
  const store = await new ThemeStore({
    engineRoot: repositoryRoot,
    stateRoot,
    activeRoot: path.join(stateRoot, "active-theme"),
  }).initialize();
  return { store, stateRoot };
}

test("初始化离线目录并应用 v2 浅暗参数", async (t) => {
  const { store, stateRoot } = await fixture(t);
  const themes = await store.listThemes();
  assert.deepEqual(themes.map(({ id }) => id), [
    "preset-red-white-abstract",
  ]);
  assert.equal(await store.activeThemeId(), DEFAULT_THEME_ID);

  await store.updateVisual(DEFAULT_THEME_ID, "dark", {
    brightness: 0.47,
    overlayOpacity: 0.31,
    surfaceOpacity: 0.54,
  });
  await store.updateVisual(DEFAULT_THEME_ID, "light", {
    brightness: 0.88,
    overlayOpacity: 0.1,
    surfaceOpacity: 0.4,
  });
  const active = JSON.parse(await fs.readFile(
    path.join(stateRoot, "active-theme", "theme.json"),
    "utf8",
  ));
  assert.equal(active.schemaVersion, 2);
  assert.equal(active.appearance, "auto");
  assert.deepEqual(active.visual.dark, {
    brightness: 0.47,
    overlayOpacity: 0.31,
    surfaceOpacity: 0.54,
  });
  assert.deepEqual(active.visual.light, {
    brightness: 0.88,
    overlayOpacity: 0.32,
    surfaceOpacity: 0.6,
  });
});

test("拒绝越界参数，导入用户主题后可重命名并安全删除", async (t) => {
  const { store } = await fixture(t);
  await assert.rejects(
    store.updateVisual(DEFAULT_THEME_ID, "light", {
      brightness: 0.2,
      overlayOpacity: 0.1,
      surfaceOpacity: 0.65,
    }),
    /0.35/,
  );

  const imageBytes = await fs.readFile(
    path.join(repositoryRoot, "library", "preset-red-white-abstract", "background.png"),
  );
  const thumbnailBytes = await fs.readFile(
    path.join(repositoryRoot, "library", "preset-red-white-abstract", "thumbnail.webp"),
  );
  const imported = await store.importTheme({
    name: "我的离线主题",
    imageBytes,
    thumbnailBytes,
  });
  await store.renameTheme(imported.theme.id, "重命名主题");
  await store.applyTheme(imported.theme.id);
  await assert.rejects(store.deleteTheme(imported.theme.id, false), /二次确认/);
  await store.deleteTheme(imported.theme.id, true);
  assert.equal(await store.activeThemeId(), DEFAULT_THEME_ID);
  await assert.rejects(store.resolveTheme(imported.theme.id));
});

test("内置主题只读且主题 ID 不能用于目录逃逸", async (t) => {
  const { store } = await fixture(t);
  await assert.rejects(store.renameTheme(DEFAULT_THEME_ID, "非法重命名"), /不能重命名/);
  await assert.rejects(store.deleteTheme(DEFAULT_THEME_ID, true), /不能删除/);
  await assert.rejects(store.resolveTheme("../outside"), /ID 不合法/);
});

test("活动用户主题回退验证失败时不删除并恢复原主题", async (t) => {
  const { store } = await fixture(t);
  const imageBytes = await fs.readFile(
    path.join(repositoryRoot, "library", "preset-red-white-abstract", "background.png"),
  );
  const thumbnailBytes = await fs.readFile(
    path.join(repositoryRoot, "library", "preset-red-white-abstract", "thumbnail.webp"),
  );
  const imported = await store.importTheme({
    name: "删除回退测试",
    imageBytes,
    thumbnailBytes,
  });
  await store.applyTheme(imported.theme.id);
  await assert.rejects(
    store.deleteTheme(imported.theme.id, true, async () => {
      throw new Error("模拟热验证失败");
    }),
    /模拟热验证失败/,
  );
  assert.equal(await store.activeThemeId(), imported.theme.id);
  assert.equal((await store.resolveTheme(imported.theme.id)).theme.name, "删除回退测试");
});

test("拒绝状态目录之外的活动主题路径", async (t) => {
  const stateRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aurora-skin-path-"));
  t.after(() => fs.rm(stateRoot, { recursive: true, force: true }));
  const store = new ThemeStore({
    engineRoot: repositoryRoot,
    stateRoot,
    activeRoot: path.join(path.dirname(stateRoot), "outside-active-theme"),
  });
  await assert.rejects(store.initialize(), /越出平台状态目录/);
});

test("读取旧版 v1 用户主题时生成安全 v2 活动快照且不改写原文件", async (t) => {
  const stateRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aurora-skin-v1-"));
  t.after(() => fs.rm(stateRoot, { recursive: true, force: true }));
  const legacyRoot = path.join(stateRoot, "themes", "20260727-legacy");
  await fs.mkdir(legacyRoot, { recursive: true });
  await fs.copyFile(
    path.join(repositoryRoot, "library", "preset-red-white-abstract", "background.png"),
    path.join(legacyRoot, "background.png"),
  );
  const original = {
    id: "20260727-legacy",
    name: "旧版主题",
    image: "background.png",
    appearance: "dark",
  };
  await fs.writeFile(path.join(legacyRoot, "theme.json"), `${JSON.stringify(original)}\n`);
  const store = await new ThemeStore({
    engineRoot: repositoryRoot,
    stateRoot,
    activeRoot: path.join(stateRoot, "active-theme"),
  }).initialize();
  const legacy = (await store.listThemes()).find(({ id }) => id === original.id);
  assert.deepEqual(legacy.visual.dark, {
    brightness: 0.62,
    overlayOpacity: 0.28,
    surfaceOpacity: 0.78,
  });
  await store.applyTheme(original.id);
  const active = JSON.parse(await fs.readFile(
    path.join(stateRoot, "active-theme", "theme.json"),
    "utf8",
  ));
  assert.equal(active.schemaVersion, 2);
  assert.equal(active.appearance, "auto");
  assert.deepEqual(
    JSON.parse(await fs.readFile(path.join(legacyRoot, "theme.json"), "utf8")),
    original,
  );
});
