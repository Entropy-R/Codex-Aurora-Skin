import fs from "node:fs/promises";
import path from "node:path";
import { randomBytes } from "node:crypto";
import { classifyImage, MAX_IMAGE_BYTES } from "./image-metadata.mjs";

export const VISUAL_LIMITS = Object.freeze({
  brightness: Object.freeze({ min: 0.35, max: 1.2, fallback: 0.9 }),
  overlayOpacity: Object.freeze({ min: 0, max: 0.7, fallback: 0.32 }),
  surfaceOpacity: Object.freeze({ min: 0.2, max: 1, fallback: 0.65 }),
});
const LIGHT_VISUAL_MINIMUMS = Object.freeze({
  overlayOpacity: 0.32,
  surfaceOpacity: 0.60,
});
export const DEFAULT_THEME_ID = "preset-red-white-abstract";
// 兼容旧版以时间戳或用户自定义 slug 命名的主题目录；路径仍只允许单段安全字符。
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{1,79}$/;
const SAFE_FILE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,239}$/;
const MODES = ["light", "dark"];

const clone = (value) => JSON.parse(JSON.stringify(value));
const isObject = (value) => value && typeof value === "object" && !Array.isArray(value);
const rounded = (value) => Math.round(value * 100) / 100;

function cleanText(value, label, max = 120) {
  if (typeof value !== "string") throw new Error(`${label} 必须是文本`);
  const text = value.trim();
  if (!text || text.length > max || /[\u0000-\u001f\u007f-\u009f]/u.test(text)) {
    throw new Error(`${label} 长度或字符不合法`);
  }
  return text;
}

function boundedNumber(value, key, fallback) {
  const limits = VISUAL_LIMITS[key];
  if (value === null || value === undefined || value === "") return fallback;
  const number = Number(value);
  if (!Number.isFinite(number) || number < limits.min || number > limits.max) {
    throw new Error(`${key} 必须在 ${limits.min} 到 ${limits.max} 之间`);
  }
  return rounded(number);
}

function safeModeNumber(value, key, fallback, mode) {
  const number = boundedNumber(value, key, fallback);
  const minimum = mode === "light" ? LIGHT_VISUAL_MINIMUMS[key] : undefined;
  return minimum === undefined ? number : rounded(Math.max(number, minimum));
}

export function normalizeVisual(value, fallback = null) {
  const source = isObject(value) ? value : {};
  const inherited = isObject(fallback) ? fallback : {};
  const result = {};
  for (const mode of MODES) {
    const modeValue = isObject(source[mode]) ? source[mode] : {};
    const modeFallback = isObject(inherited[mode]) ? inherited[mode] : {};
    result[mode] = {
      brightness: boundedNumber(
        modeValue.brightness,
        "brightness",
        boundedNumber(
          modeFallback.brightness,
          "brightness",
          mode === "dark" ? 0.62 : VISUAL_LIMITS.brightness.fallback,
        ),
      ),
      overlayOpacity: safeModeNumber(
        modeValue.overlayOpacity,
        "overlayOpacity",
        boundedNumber(
          modeFallback.overlayOpacity,
          "overlayOpacity",
          mode === "dark" ? 0.28 : VISUAL_LIMITS.overlayOpacity.fallback,
        ),
        mode,
      ),
      surfaceOpacity: safeModeNumber(
        modeValue.surfaceOpacity,
        "surfaceOpacity",
        boundedNumber(
          modeFallback.surfaceOpacity,
          "surfaceOpacity",
          mode === "dark" ? 0.78 : VISUAL_LIMITS.surfaceOpacity.fallback,
        ),
        mode,
      ),
    };
  }
  return result;
}

function normalizeArt(value) {
  const art = isObject(value) ? value : {};
  const unit = (candidate, fallback) => {
    if (candidate === null || candidate === undefined || candidate === "") return fallback;
    const number = Number(candidate);
    if (!Number.isFinite(number) || number < 0 || number > 1) {
      throw new Error("主题焦点必须在 0 到 1 之间");
    }
    return number;
  };
  const choice = (candidate, values, fallback) =>
    values.includes(candidate) ? candidate : fallback;
  return {
    focusX: unit(art.focusX, 0.72),
    focusY: unit(art.focusY, 0.45),
    safeArea: choice(art.safeArea, ["auto", "left", "right", "center", "none"], "auto"),
    taskMode: choice(art.taskMode, ["auto", "ambient", "banner", "off"], "auto"),
  };
}

function normalizedTheme(raw, directoryId) {
  if (!isObject(raw)) throw new Error("theme.json 根节点必须是对象");
  const id = cleanText(raw.id || directoryId, "主题 ID", 80);
  if (!SAFE_ID.test(id)) throw new Error(`主题 ID 不合法：${id}`);
  const image = cleanText(raw.image, "主题图片路径", 240);
  if (!SAFE_FILE.test(image) || path.isAbsolute(image)) throw new Error("主题图片必须是目录内文件");
  const thumbnail = typeof raw.thumbnail === "string" && SAFE_FILE.test(raw.thumbnail)
    ? raw.thumbnail : null;
  return {
    schemaVersion: raw.schemaVersion === 2 ? 2 : 1,
    id,
    name: cleanText(raw.name || id, "主题名称", 80),
    image,
    ...(thumbnail ? { thumbnail } : {}),
    appearance: "auto",
    art: normalizeArt(raw.art),
    visual: normalizeVisual(raw.visual),
  };
}

async function exists(file) {
  try {
    await fs.access(file);
    return true;
  } catch {
    return false;
  }
}

async function writeJsonAtomic(file, value) {
  const directory = path.dirname(file);
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const temporary = path.join(directory, `.${path.basename(file)}.${process.pid}.${randomBytes(6).toString("hex")}.tmp`);
  await fs.writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
  await fs.rename(temporary, file);
}

function contained(root, candidate) {
  const relative = path.relative(path.resolve(root), path.resolve(candidate));
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

async function assertNoLinkEscape(root, candidate) {
  if (!contained(root, candidate)) throw new Error("主题路径越出受管目录");
  const realRoot = await fs.realpath(root);
  const realCandidate = await fs.realpath(candidate);
  if (!contained(realRoot, realCandidate)) throw new Error("主题路径通过链接越出受管目录");
  return realCandidate;
}

async function safeRemove(root, candidate) {
  // macOS 的临时目录可能通过 /var -> /private/var 别名返回真实路径；
  // 删除前统一解析两端，同时继续拒绝链接逃逸和根目录本身。
  const realRoot = await fs.realpath(root);
  const realCandidate = await fs.realpath(candidate);
  if (!contained(realRoot, realCandidate) || realRoot === realCandidate) {
    throw new Error("拒绝删除受管根目录之外的路径");
  }
  await fs.rm(realCandidate, { recursive: true, force: true });
}

export class ThemeStore {
  constructor({ engineRoot, stateRoot, activeRoot }) {
    this.engineRoot = path.resolve(engineRoot);
    this.libraryRoot = path.join(this.engineRoot, "library");
    this.stateRoot = path.resolve(stateRoot);
    this.userRoot = path.join(this.stateRoot, "themes");
    this.activeRoot = path.resolve(activeRoot);
    this.overridesPath = path.join(this.stateRoot, "overrides.json");
    this.catalog = null;
  }

  async initialize() {
    if (!contained(this.stateRoot, this.userRoot) || !contained(this.stateRoot, this.activeRoot)) {
      throw new Error("主题状态路径越出平台状态目录");
    }
    await fs.mkdir(this.stateRoot, { recursive: true, mode: 0o700 });
    await fs.mkdir(this.userRoot, { recursive: true, mode: 0o700 });
    await fs.mkdir(path.dirname(this.activeRoot), { recursive: true, mode: 0o700 });
    const realStateRoot = await fs.realpath(this.stateRoot);
    for (const directory of [this.stateRoot, this.userRoot, path.dirname(this.activeRoot)]) {
      const stat = await fs.lstat(directory);
      if (!stat.isDirectory() || stat.isSymbolicLink() ||
          !contained(realStateRoot, await fs.realpath(directory))) {
        throw new Error(`主题状态目录不安全：${directory}`);
      }
    }
    if (await exists(this.activeRoot)) {
      const activeStat = await fs.lstat(this.activeRoot);
      if (!activeStat.isDirectory() || activeStat.isSymbolicLink() ||
          !contained(realStateRoot, await fs.realpath(this.activeRoot))) {
        throw new Error("活动主题目录不安全");
      }
    }
    const libraryStat = await fs.lstat(this.libraryRoot);
    if (!libraryStat.isDirectory() || libraryStat.isSymbolicLink() ||
        !contained(this.engineRoot, this.libraryRoot)) {
      throw new Error("内置主题目录不安全");
    }
    this.catalog = await this.#readCatalog();
    if (!(await exists(path.join(this.activeRoot, "theme.json")))) {
      await this.applyTheme(DEFAULT_THEME_ID);
    }
    return this;
  }

  async #readCatalog() {
    const raw = JSON.parse(await fs.readFile(path.join(this.libraryRoot, "catalog.json"), "utf8"));
    if (!isObject(raw) || raw.schemaVersion !== 1 || !Array.isArray(raw.themes)) {
      throw new Error("内置主题目录格式不受支持");
    }
    const seen = new Set();
    const themes = [];
    for (const entry of raw.themes) {
      if (!isObject(entry) || !SAFE_ID.test(entry.id) || seen.has(entry.id) ||
          !SAFE_FILE.test(entry.directory)) throw new Error("内置主题目录包含非法条目");
      const directory = path.join(this.libraryRoot, entry.directory);
      const pack = await this.readThemePack(directory, "builtin");
      if (pack.theme.id !== entry.id) throw new Error(`内置主题 ID 不匹配：${entry.id}`);
      themes.push({
        id: entry.id,
        directory,
        license: cleanText(entry.license || "项目内可分发素材", "素材许可", 160),
      });
      seen.add(entry.id);
    }
    if (!seen.has(DEFAULT_THEME_ID)) throw new Error("内置主题目录缺少默认主题");
    return { schemaVersion: 1, themes };
  }

  async readThemePack(directory, source = "user") {
    const root = source === "builtin" ? this.libraryRoot : this.userRoot;
    const resolvedDirectory = await assertNoLinkEscape(root, directory);
    const raw = JSON.parse(await fs.readFile(path.join(resolvedDirectory, "theme.json"), "utf8"));
    const theme = normalizedTheme(raw, path.basename(resolvedDirectory));
    const imagePath = path.join(resolvedDirectory, theme.image);
    const realImage = await assertNoLinkEscape(resolvedDirectory, imagePath);
    const imageBytes = await fs.readFile(realImage);
    const metadata = classifyImage(imageBytes, path.extname(realImage));
    if (!metadata) throw new Error(`主题图片无效或超过安全限制：${theme.id}`);
    let thumbnailPath = realImage;
    if (theme.thumbnail) {
      const candidate = path.join(resolvedDirectory, theme.thumbnail);
      const realThumbnail = await assertNoLinkEscape(resolvedDirectory, candidate);
      const thumbnailBytes = await fs.readFile(realThumbnail);
      const thumbnail = classifyImage(thumbnailBytes, path.extname(realThumbnail));
      if (!thumbnail || thumbnail.format !== "webp" || thumbnail.width !== 480 ||
          thumbnail.height !== 270 || thumbnailBytes.length > 256 * 1024) {
        throw new Error(`主题缩略图必须是 480×270 且不超过 256 KB 的 WebP：${theme.id}`);
      }
      thumbnailPath = realThumbnail;
    }
    return { source, directory: resolvedDirectory, theme, imagePath: realImage, thumbnailPath, metadata };
  }

  async #readOverrides() {
    if (!(await exists(this.overridesPath))) return { schemaVersion: 1, themes: {} };
    try {
      const raw = JSON.parse(await fs.readFile(this.overridesPath, "utf8"));
      if (!isObject(raw) || raw.schemaVersion !== 1 || !isObject(raw.themes)) throw new Error();
      return raw;
    } catch {
      throw new Error("用户主题覆盖配置已损坏，请修复 overrides.json");
    }
  }

  async listThemes() {
    const overrides = await this.#readOverrides();
    const themes = [];
    for (const entry of this.catalog.themes) {
      const pack = await this.readThemePack(entry.directory, "builtin");
      themes.push(this.#publicTheme(pack, overrides.themes[pack.theme.id], entry.license));
    }
    const builtinIds = new Set(themes.map((theme) => theme.id));
    for (const item of await fs.readdir(this.userRoot, { withFileTypes: true })) {
      if (!item.isDirectory() || !SAFE_ID.test(item.name) || builtinIds.has(item.name)) continue;
      try {
        const pack = await this.readThemePack(path.join(this.userRoot, item.name), "user");
        themes.push(this.#publicTheme(pack, overrides.themes[pack.theme.id]));
      } catch {
        // 损坏的用户目录不进入可操作资源库，避免管理器误删或误应用。
      }
    }
    const activeId = await this.activeThemeId();
    return themes.map((theme) => ({ ...theme, active: theme.id === activeId }));
  }

  #publicTheme(pack, override, license = null) {
    return {
      id: pack.theme.id,
      name: pack.theme.name,
      source: pack.source,
      visual: normalizeVisual(override, pack.theme.visual),
      defaults: pack.theme.visual,
      art: pack.theme.art,
      metadata: pack.metadata,
      license,
      previewUrl: `/api/themes/${encodeURIComponent(pack.theme.id)}/thumbnail`,
    };
  }

  async resolveTheme(id) {
    if (!SAFE_ID.test(id)) throw new Error("主题 ID 不合法");
    const builtin = this.catalog.themes.find((entry) => entry.id === id);
    if (builtin) return this.readThemePack(builtin.directory, "builtin");
    return this.readThemePack(path.join(this.userRoot, id), "user");
  }

  async activeThemeId() {
    try {
      const raw = JSON.parse(await fs.readFile(path.join(this.activeRoot, "theme.json"), "utf8"));
      return typeof raw.id === "string" ? raw.id : null;
    } catch {
      return null;
    }
  }

  async effectiveTheme(pack) {
    const overrides = await this.#readOverrides();
    return {
      ...clone(pack.theme),
      schemaVersion: 2,
      appearance: "auto",
      visual: normalizeVisual(overrides.themes[pack.theme.id], pack.theme.visual),
    };
  }

  async applyTheme(id) {
    const pack = await this.resolveTheme(id);
    const theme = await this.effectiveTheme(pack);
    const stage = path.join(this.stateRoot, `.active-theme.${process.pid}.${randomBytes(6).toString("hex")}`);
    const backup = `${this.activeRoot}.previous.${process.pid}.${randomBytes(4).toString("hex")}`;
    await fs.mkdir(stage, { recursive: false, mode: 0o700 });
    try {
      const imageName = `background${path.extname(pack.imagePath).toLowerCase()}`;
      await fs.copyFile(pack.imagePath, path.join(stage, imageName));
      theme.image = imageName;
      delete theme.thumbnail;
      await writeJsonAtomic(path.join(stage, "theme.json"), theme);
      if (await exists(this.activeRoot)) await fs.rename(this.activeRoot, backup);
      try {
        await fs.rename(stage, this.activeRoot);
      } catch (error) {
        if (await exists(backup)) await fs.rename(backup, this.activeRoot);
        throw error;
      }
      if (await exists(backup)) await safeRemove(this.stateRoot, backup);
      return theme;
    } finally {
      if (await exists(stage)) await safeRemove(this.stateRoot, stage);
    }
  }

  async updateVisual(id, mode, values) {
    if (!MODES.includes(mode)) throw new Error("外观模式必须是 light 或 dark");
    const pack = await this.resolveTheme(id);
    const overrides = await this.#readOverrides();
    const previous = clone(overrides);
    const current = normalizeVisual(overrides.themes[id], pack.theme.visual);
    current[mode] = {
      brightness: boundedNumber(values?.brightness, "brightness", current[mode].brightness),
      overlayOpacity: safeModeNumber(
        values?.overlayOpacity,
        "overlayOpacity",
        current[mode].overlayOpacity,
        mode,
      ),
      surfaceOpacity: safeModeNumber(
        values?.surfaceOpacity,
        "surfaceOpacity",
        current[mode].surfaceOpacity,
        mode,
      ),
    };
    overrides.themes[id] = current;
    await writeJsonAtomic(this.overridesPath, overrides);
    if (await this.activeThemeId() === id) await this.applyTheme(id);
    return { visual: current, previous };
  }

  async restoreOverrides(snapshot, id) {
    await writeJsonAtomic(this.overridesPath, snapshot);
    if (await this.activeThemeId() === id) await this.applyTheme(id);
  }

  async resetVisual(id, mode) {
    if (!MODES.includes(mode)) throw new Error("外观模式必须是 light 或 dark");
    const pack = await this.resolveTheme(id);
    const overrides = await this.#readOverrides();
    const previous = clone(overrides);
    const current = normalizeVisual(overrides.themes[id], pack.theme.visual);
    current[mode] = clone(pack.theme.visual[mode]);
    overrides.themes[id] = current;
    await writeJsonAtomic(this.overridesPath, overrides);
    if (await this.activeThemeId() === id) await this.applyTheme(id);
    return { visual: current, previous };
  }

  async importTheme({ name, imageBytes, thumbnailBytes }) {
    const normalizedName = cleanText(name, "主题名称", 80);
    const image = classifyImage(imageBytes);
    if (!image) throw new Error(`图片必须是有效的 PNG、JPEG 或 WebP，且不超过 ${MAX_IMAGE_BYTES / 1024 / 1024} MB`);
    const thumbnail = classifyImage(thumbnailBytes, ".webp");
    if (!thumbnail || thumbnail.format !== "webp" || thumbnail.width !== 480 ||
        thumbnail.height !== 270 || thumbnailBytes.length > 256 * 1024) {
      throw new Error("缩略图必须是 480×270 且不超过 256 KB 的 WebP");
    }
    const id = `custom-${Date.now()}-${randomBytes(4).toString("hex")}`;
    const extension = image.format === "jpeg" ? ".jpg" : `.${image.format}`;
    const stage = path.join(this.userRoot, `.theme-import.${process.pid}.${randomBytes(6).toString("hex")}`);
    const destination = path.join(this.userRoot, id);
    await fs.mkdir(stage, { recursive: false, mode: 0o700 });
    try {
      await fs.writeFile(path.join(stage, `background${extension}`), imageBytes, { mode: 0o600 });
      await fs.writeFile(path.join(stage, "thumbnail.webp"), thumbnailBytes, { mode: 0o600 });
      await writeJsonAtomic(path.join(stage, "theme.json"), {
        schemaVersion: 2,
        id,
        name: normalizedName,
        image: `background${extension}`,
        thumbnail: "thumbnail.webp",
        appearance: "auto",
        art: { focusX: 0.72, focusY: 0.45, safeArea: "auto", taskMode: "auto" },
        visual: normalizeVisual(null),
      });
      await this.readThemePack(stage, "user");
      await fs.rename(stage, destination);
      return this.resolveTheme(id);
    } finally {
      if (await exists(stage)) await safeRemove(this.userRoot, stage);
    }
  }

  async renameTheme(id, name) {
    const pack = await this.resolveTheme(id);
    if (pack.source !== "user") throw new Error("内置主题不能重命名");
    const raw = JSON.parse(await fs.readFile(path.join(pack.directory, "theme.json"), "utf8"));
    raw.name = cleanText(name, "主题名称", 80);
    await writeJsonAtomic(path.join(pack.directory, "theme.json"), raw);
    if (await this.activeThemeId() === id) await this.applyTheme(id);
    return raw.name;
  }

  async deleteTheme(id, confirmed, verifyFallback = async () => {}) {
    if (!confirmed) throw new Error("删除用户主题需要二次确认");
    const pack = await this.resolveTheme(id);
    if (pack.source !== "user") throw new Error("内置主题不能删除");
    if (await this.activeThemeId() === id) {
      await this.applyTheme(DEFAULT_THEME_ID);
      try {
        await verifyFallback();
      } catch (error) {
        await this.applyTheme(id).catch(() => {});
        throw error;
      }
    }
    await safeRemove(this.userRoot, pack.directory);
    const overrides = await this.#readOverrides();
    delete overrides.themes[id];
    await writeJsonAtomic(this.overridesPath, overrides);
  }

  async assetPath(id, kind) {
    const pack = await this.resolveTheme(id);
    return kind === "thumbnail" ? pack.thumbnailPath : pack.imagePath;
  }
}
