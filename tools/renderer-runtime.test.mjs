import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";

function styleDeclaration() {
  const values = new Map();
  return {
    values,
    getPropertyValue(name) { return values.get(name) || ""; },
    setProperty(name, value) { values.set(name, String(value)); },
    removeProperty(name) { values.delete(name); },
    [Symbol.iterator]() { return values.keys(); },
  };
}

function classList(initial) {
  const values = new Set(initial);
  const writes = [];
  return {
    values,
    writes,
    contains(value) { return values.has(value); },
    add(...names) { writes.push(["add", ...names]); names.forEach((name) => values.add(name)); },
    remove(...names) { writes.push(["remove", ...names]); names.forEach((name) => values.delete(name)); },
    toggle(name, enabled) { writes.push(["toggle", name, enabled]); if (enabled) values.add(name); else values.delete(name); },
  };
}

function makeFixture({ nativeAppearance = "dark", settings = false, adopted = true } = {}) {
  const attrs = new Map();
  const rootStyle = styleDeclaration();
  const rootClasses = classList([nativeAppearance === "dark" ? "electron-dark" : "electron-light"]);
  const nodes = new Map();
  const observers = [];
  const timers = new Map();
  const intervals = new Map();
  const listeners = new Map();
  const revoked = [];
  const attributeLog = [];
  const page = {
    route: settings ? "settings" : "home",
    shellPresent: !settings,
    homeUtility: false,
    searchInputs: [],
    projectSelectors: [],
  };
  let nextId = 0;
  let nextBlob = 0;
  const makeElement = ({ parentElement = null, matches = [], closest = {} } = {}) => {
    const elementAttrs = new Map();
    return {
      parentElement,
      getAttribute(name) { return elementAttrs.get(name) ?? null; },
      setAttribute(name, value) { elementAttrs.set(name, String(value)); },
      removeAttribute(name) { elementAttrs.delete(name); },
      matches(selector) { return matches.includes(selector); },
      closest(selector) { return closest[selector] || null; },
    };
  };
  const shellMain = makeElement();
  const sidebar = makeElement();
  const header = makeElement();
  const composerToolbar = makeElement();
  const composer = makeElement();
  composer.querySelector = (selector) =>
    selector.includes("composer-toolbar") || selector.includes("composer-footer") ||
      selector.includes("ComposerLayoutFooter")
      ? composerToolbar : null;
  const root = {
    classList: rootClasses,
    style: rootStyle,
    getAttribute(name) { return attrs.get(name) ?? null; },
    setAttribute(name, value) {
      attrs.set(name, String(value));
      attributeLog.push([name, String(value)]);
    },
    removeAttribute(name) { attrs.delete(name); },
    appendChild(node) { node.parentElement = root; if (node.id) nodes.set(node.id, node); return node; },
  };
  const body = {
    appendChild(node) { node.parentElement = body; if (node.id) nodes.set(node.id, node); return node; },
  };
  const makeStyleNode = () => {
    const node = {
      id: "",
      textContent: "",
      parentElement: null,
      dataset: {},
      remove() { if (node.id) nodes.delete(node.id); node.parentElement = null; },
    };
    return node;
  };
  const document = {
    documentElement: root,
    head: root,
    body,
    adoptedStyleSheets: adopted ? [] : undefined,
    createElement(tag) { return tag === "style" ? makeStyleNode() : { tagName: tag }; },
    getElementById(id) { return nodes.get(id) || null; },
    querySelector(selector) {
      if (page.route === "settings" &&
        (selector.includes("settings-panel-slug") || selector.includes("appearance-theme") ||
          selector.includes("theme-preview"))) return { selector };
      if (selector === 'main, [role="main"]') return page.shellPresent ? shellMain : null;
      if (selector.includes("main-surface") || selector.includes("MainContentSurface") ||
        selector.includes("app-shell-main-surface")) return page.shellPresent ? shellMain : null;
      if (selector.includes("aside.app-shell-left-panel")) {
        return page.shellPresent ? sidebar : null;
      }
      if (selector.includes("app-header-tint") || selector.includes("app-shell-header-edge-scroll") ||
        selector.includes("_Header_")) {
        return page.shellPresent ? header : null;
      }
      if (selector.includes("[role=\"main\"]") || selector.includes("[data-testid=\"home-icon\"]")) {
        return page.route === "home" ? { selector } : null;
      }
      if (selector.includes("composer-surface-chrome") ||
        selector.includes("data-composer-surface-variant")) {
        return page.route === "home" || page.route === "thread" ? composer : null;
      }
      if (selector.includes("_homeUtilityBar_")) return page.homeUtility ? { selector } : null;
      if (selector.includes("group\\/project-selector")) return page.projectSelectors[0] || null;
      return null;
    },
    querySelectorAll(selector) {
      if (selector === 'input[type="text"]') return page.searchInputs;
      if (selector.includes("group\\/project-selector")) return page.projectSelectors;
      return [];
    },
  };
  const navigation = {
    addEventListener(type, callback) { listeners.set(`navigation:${type}`, callback); },
    removeEventListener(type) { listeners.delete(`navigation:${type}`); },
  };
  class MockMutationObserver {
    constructor(callback) { this.callback = callback; this.options = null; observers.push(this); }
    observe(target, options) { this.target = target; this.options = options; }
    disconnect() { this.disconnected = true; }
  }
  class MockSheet {
    replaceSync(text) { this.text = text; }
  }
  const window = {
    navigation,
    matchMedia() {
      return {
        matches: nativeAppearance === "dark",
        addEventListener(type, callback) { listeners.set(`media:${type}`, callback); },
        removeEventListener(type) { listeners.delete(`media:${type}`); },
      };
    },
    addEventListener() {},
    removeEventListener() {},
  };
  const context = {
    window,
    document,
    MutationObserver: MockMutationObserver,
    CSSStyleSheet: adopted ? MockSheet : undefined,
    Blob,
    Uint8Array,
    atob,
    URL: {
      createObjectURL() { nextBlob += 1; return `blob:fixture-${nextBlob}`; },
      revokeObjectURL(value) { revoked.push(value); },
    },
    performance: { now: () => 1 },
    setTimeout(callback, delay) { const id = ++nextId; timers.set(id, { callback, delay }); return id; },
    clearTimeout(id) { timers.delete(id); },
    setInterval(callback, delay) { const id = ++nextId; intervals.set(id, { callback, delay }); return id; },
    clearInterval(id) { intervals.delete(id); },
    console,
  };
  const payloadFor = (theme = {}) => {
    const template = fixture.template;
    return template
      .replace("__AURORA_SKIN_CSS_JSON__", JSON.stringify(".fixture { color: red; }"))
      .replace("__AURORA_SKIN_ART_JSON__", JSON.stringify("data:image/png;base64,AA=="))
      .replace("__AURORA_SKIN_THEME_JSON__", JSON.stringify({ id: "fixture", appearance: "auto", ...theme }))
      .replace("__AURORA_SKIN_VERSION_JSON__", JSON.stringify("test"))
      .replace("__AURORA_SKIN_STYLE_REVISION_JSON__", JSON.stringify("css-rev"))
      .replace("__AURORA_SKIN_PAYLOAD_REVISION_JSON__", JSON.stringify("payload-rev"));
  };
  const flushTimers = (maximumDelay = Infinity) => {
    for (const [id, timer] of [...timers]) {
      if (timer.delay <= maximumDelay) { timers.delete(id); timer.callback(); }
    }
  };
  const setRoute = (route, { shellPresent = route !== "settings" } = {}) => {
    page.route = route;
    page.shellPresent = shellPresent;
  };
  const addSearch = () => {
    const sticky = makeElement({ matches: ["div.sticky"] });
    const directHost = makeElement({ matches: ["div.no-drag"] });
    const input = makeElement({
      parentElement: directHost,
      closest: { "div.sticky": sticky },
    });
    page.searchInputs.push(input);
    return { directHost, input, sticky };
  };
  const addProject = () => {
    const host = makeElement({ matches: ["div"] });
    const fadeMask = makeElement({ parentElement: host, matches: [".horizontal-scroll-fade-mask"] });
    const project = makeElement({ closest: { ".horizontal-scroll-fade-mask": fadeMask } });
    page.projectSelectors.push(project);
    return { fadeMask, host, project };
  };
  return {
    addProject, addSearch, attributeLog, attrs, context, document, flushTimers,
    composer, composerToolbar, header, intervals, listeners, nodes, observers, page, payloadFor,
    revoked, root, shellMain, sidebar,
    rootClasses, rootStyle, setRoute, timers, window,
  };
}

function unscopedCssRules(css) {
  const rules = [];
  let start = 0;
  let quote = null;
  let index = 0;
  while (index < css.length) {
    if (!quote && css.startsWith("/*", index)) {
      const end = css.indexOf("*/", index + 2);
      index = end < 0 ? css.length : end + 2;
      continue;
    }
    const character = css[index];
    if (quote) {
      if (character === "\\") index += 2;
      else { if (character === quote) quote = null; index += 1; }
      continue;
    }
    if (character === "\"" || character === "'") { quote = character; index += 1; continue; }
    if (character === "{") {
      const prelude = css.slice(start, index).trim();
      if (prelude && !prelude.startsWith("@") &&
        !prelude.includes('html[data-aurora-skin="active"]') &&
        !prelude.includes(':root[data-aurora-skin="active"]')) {
        rules.push(prelude);
      }
      start = index + 1;
    } else if (character === "}") {
      start = index + 1;
    }
    index += 1;
  }
  return rules;
}

export async function runRendererRuntimeTest(assetRoot) {
  const template = await fs.readFile(path.join(assetRoot, "renderer-inject.js"), "utf8");
  const css = await fs.readFile(path.join(assetRoot, "aurora-skin.css"), "utf8");
  fixture.template = template;

  assert.match(template, /adoptedStyleSheets/);
  assert.match(template, /CSSStyleSheet/);
  assert.match(template, /window\.navigation/);
  assert.match(template, /electron-dark/);
  assert.doesNotMatch(template, /electron-opaque|home-suggestion-list-item/,
    "Runtime payload must not carry retired selector documentation/fossils.");
  assert.doesNotMatch(template, /classList\.(add|remove|toggle)/);
  assert.doesNotMatch(template, /getBoundingClientRect|ResizeObserver|childList|subtree/);
  // The new contract intentionally keeps the `data-dream-*` attribute names
  // and `--dream-*` custom properties.  Only the retired DOM marker classes
  // and the measured fossil selector must be absent from the canonical CSS.
  assert.doesNotMatch(css, /(?:^|[.#\s])(?:codex-aurora-skin|aurora-skin-home|dream-home|dream-task)(?:[\s.#:{>]|$)|home-suggestion-list-item/);
  assert.match(css, /html\[data-aurora-skin="active"\]/);
  assert.doesNotMatch(css, /:has\(/,
    "Runtime CSS must use low-frequency DOM markers instead of relational selectors.");
  assert.match(css, /\[data-dream-route="home"\]/);
  assert.match(css, /\[data-dream-search-band="true"\]/);
  assert.match(css, /\[data-dream-search-input="true"\]/);
  assert.match(css, /\[data-dream-project-host="true"\]/);
  assert.doesNotMatch(css, /flex:\s*0 0 440px|min-height:\s*440px|flex-basis:\s*408px|min-height:\s*408px/,
    "主页布局不得用固定高度把原生输入框推到视口之外。");
  assert.doesNotMatch(css, /__DREAM_SELECTOR_HOME_ROUTE_CSS__\s*>\s*div/,
    "主页结构会随 Codex 升级变化，皮肤不得按直接子节点层级重排原生输入区。");
  assert.match(css, /filter:\s*brightness\(var\(--ds-art-brightness\)\)/);
  assert.doesNotMatch(css, /body\s*\{[^}]*filter:\s*brightness/s,
    "Background brightness must never filter the native app body and controls.");
  assert.doesNotMatch(css, /body\s*\{[^}]*font-family\s*:/s,
    "皮肤不得覆盖 Codex 原生全局字体。");
  assert.doesNotMatch(css, /(?:__DREAM_SELECTOR_MARKDOWN__|\[class\*="_markdown"\])\s*\{[^}]*text-shadow\s*:/s,
    "皮肤不得给会话正文增加文字描边或阴影。");
  assert.doesNotMatch(css, /--ds-task-(?:shade|fade|immersive)/,
    "Home and task routes must use one background composition instead of route-specific global tints.");
  assert.match(css, /--ds-surface-opacity:\s*\.78/);
  assert.match(css, /--ds-surface-strong:\s*rgb\(var\(--ds-panel-rgb\)\s*\/\s*var\(--ds-surface-opacity\)\)/);
  assert.doesNotMatch(css, /aurora-skin-brand-subtitle|aurora-skin-status/,
    "Thread header must not inject Aurora Skin branding or online status labels.");
  assert.match(css, /:not\(\[data-dream-route="home"\]\)\s+:is\([^{}]*data-aurora-part="main"[^{}]*\)::before\s*\{[\s\S]*?opacity:\s*1;/,
    "The task artwork layer must retain the same opacity shown by the manager preview.");
  assert.match(css, /data-aurora-part="composer"/,
    "Compiled CSS must retain the semantic composer fallback.");
  assert.match(css, /_ComposerLayoutBody_[^{}]*\{\s*background:\s*transparent\s*!important;/s,
    "The 26.810 home composer body must not repaint over LayoutRoot.");
  assert.match(css, /\.bg-gradient-to-t[^{}]*\.from-surface/,
    "The 26.810 thread composer fade must be made transparent.");
  assert.match(css, /\.bg-gradient-to-t[^{}]*\.via-surface/,
    "The 26.810 thread composer midpoint fade must be made transparent.");
  assert.doesNotMatch(css, /aurora-skin-(?:name|tagline|quote)|MAKE SOMETHING WONDERFUL|Make something wonderful/);
  assert.doesNotMatch(template, /aurora-skin-(?:name|tagline|quote)|MAKE SOMETHING WONDERFUL|Make something wonderful/);
  assert.match(template, /wide:\s*ratio\s*>=\s*1\.45/,
    "横图判定必须与 aspect=wide 共用阈值，确保首页和侧栏进入全窗口背景模式。");
  // Every home/project selector must stay behind the root skin gate.  A
  // marker-class-to-:has() conversion must never leave native layout rules
  // active after pause/restore.
  const unscoped = unscopedCssRules(css).join("\n");
  assert.doesNotMatch(unscoped, /\[role="main"\]/);
  assert.doesNotMatch(unscoped, /\.group\\\/project-selector/);

  const home = makeFixture({ nativeAppearance: "dark" });
  vm.runInNewContext(home.payloadFor({
    art: { safeArea: "left", taskMode: "banner" },
    visual: {
      light: { brightness: 0.88, overlayOpacity: 0.14, surfaceOpacity: 0.64 },
      dark: { brightness: 0.47, overlayOpacity: 0.31, surfaceOpacity: 0.53 },
    },
  }), home.context);
  const state = home.window.__CODEX_AURORA_SKIN_STATE__;
  assert.equal(home.attrs.get("data-aurora-skin"), "active");
  assert.equal(home.attrs.get("data-dream-shell"), "dark");
  assert.equal(home.attrs.get("data-dream-route"), "home");
  assert.equal(home.attrs.get("data-dream-home-utility"), "false");
  assert.equal(home.attrs.get("data-dream-shell-present"), "true");
  assert.ok(
    home.attributeLog.findIndex(([name]) => name === "data-dream-route") <
      home.attributeLog.findIndex(([name]) => name === "data-aurora-skin"),
    "The initial route marker must exist before the skin becomes active.",
  );
  assert.equal(state.styleMode, "adopted");
  assert.equal(home.document.adoptedStyleSheets.length, 1);
  assert.equal(state.scope.baseState, "home");
  assert.equal(state.scope.level, "L1");
  assert.equal(home.shellMain.getAttribute("data-aurora-part"), "main");
  assert.equal(home.sidebar.getAttribute("data-aurora-part"), "sidebar");
  assert.equal(home.header.getAttribute("data-aurora-part"), "header");
  assert.equal(home.composer.getAttribute("data-aurora-part"), "composer");
  assert.equal(home.composerToolbar.getAttribute("data-aurora-part"), "composer-toolbar");
  assert.equal(home.rootStyle.values.get("--ds-art-brightness"), "0.47");
  assert.equal(home.rootStyle.values.get("--ds-art-overlay-opacity"), "0.31");
  assert.equal(home.rootStyle.values.get("--ds-surface-opacity"), "0.53");
  assert.equal(state.metrics.routePasses, 1);
  assert.equal(state.metrics.layoutReads, 0, "Runtime must not perform layout reads");
  assert.equal(home.rootClasses.writes.length, 0, "Runtime must not write classes");
  assert.ok(home.observers.every((observer) => !observer.options?.childList && !observer.options?.subtree));

  const observer = home.observers[0];
  observer.callback([]);
  home.flushTimers(64);
  assert.equal(state.metrics.routePasses, 1, "Attribute safety pass must not be a route pass");
  home.rootClasses.values.delete("electron-dark");
  home.rootClasses.values.add("electron-light");
  observer.callback([]);
  home.flushTimers(64);
  assert.equal(home.attrs.get("data-dream-shell"), "light");
  assert.equal(home.rootStyle.values.get("--ds-art-brightness"), "0.88");
  assert.equal(home.rootStyle.values.get("--ds-art-overlay-opacity"), "0.32");
  assert.equal(home.rootStyle.values.get("--ds-surface-opacity"), "0.64");
  const navigationHandler = home.listeners.get("navigation:navigate");
  assert.equal(typeof navigationHandler, "function");
  home.setRoute("thread");
  navigationHandler();
  home.flushTimers(64);
  assert.equal(state.metrics.navigationEvents, 1);
  assert.equal(state.metrics.routePasses, 2);
  assert.equal(home.attrs.get("data-dream-route"), "thread");

  const search = home.addSearch();
  home.flushTimers(250);
  assert.equal(state.metrics.routePasses, 3);
  assert.equal(search.sticky.getAttribute("data-dream-search-band"), "true");
  assert.equal(search.directHost.getAttribute("data-dream-search-input"), "true");

  home.setRoute("home");
  home.page.homeUtility = true;
  const project = home.addProject();
  navigationHandler();
  home.flushTimers(64);
  assert.equal(home.attrs.get("data-dream-route"), "home");
  assert.equal(home.attrs.get("data-dream-home-utility"), "true");
  assert.equal(project.host.getAttribute("data-dream-project-host"), "true");
  assert.equal(search.sticky.getAttribute("data-dream-search-band"), null);
  assert.equal(search.directHost.getAttribute("data-dream-search-input"), null);

  home.setRoute("thread");
  navigationHandler();
  home.setRoute("home");
  navigationHandler();
  home.flushTimers(64);
  assert.equal(state.metrics.navigationEvents, 4);
  assert.equal(home.attrs.get("data-dream-route"), "home",
    "A stale navigation retry must not overwrite the latest route.");
  assert.equal(home.timers.size, 3, "Only the latest navigation retry generation may remain queued.");

  const safetyInterval = home.intervals.get(state.timer);
  assert.equal(safetyInterval.delay, 30000);
  const routePassesBeforeSafety = state.metrics.routePasses;
  safetyInterval.callback();
  assert.equal(state.metrics.routePasses, routePassesBeforeSafety + 1,
    "The safety pass must reconcile route and local markers.");

  assert.equal(state.cleanup(), true);
  assert.equal(project.host.getAttribute("data-dream-project-host"), null);
  assert.equal(home.shellMain.getAttribute("data-aurora-part"), null);
  assert.equal(home.composer.getAttribute("data-aurora-part"), null);
  assert.equal(home.composerToolbar.getAttribute("data-aurora-part"), null);
  assert.equal(home.timers.size, 0);
  assert.equal(home.attrs.size, 0);

  const settings = makeFixture({ nativeAppearance: "light", settings: true });
  vm.runInNewContext(settings.payloadFor(), settings.context);
  assert.equal(settings.window.__CODEX_AURORA_SKIN_STATE__.scope.baseState, "settings");
  assert.equal(settings.window.__CODEX_AURORA_SKIN_STATE__.scope.level, "L0");
  assert.equal(settings.attrs.get("data-dream-route"), "settings");
  assert.equal(settings.attrs.get("data-dream-shell-present"), "false");
  assert.equal(settings.attrs.get("data-aurora-skin"), "active");
  assert.equal(settings.document.adoptedStyleSheets.length, 1);

  const unknown = makeFixture({ nativeAppearance: "light" });
  unknown.setRoute("unknown", { shellPresent: false });
  vm.runInNewContext(unknown.payloadFor(), unknown.context);
  assert.equal(unknown.window.__CODEX_AURORA_SKIN_STATE__.scope.baseState, "unknown");
  assert.equal(unknown.window.__CODEX_AURORA_SKIN_STATE__.scope.level, "L0");
  assert.equal(unknown.attrs.get("data-dream-route"), "unknown");

  const explicit = makeFixture({ nativeAppearance: "light" });
  const result = vm.runInNewContext(explicit.payloadFor({ appearance: "dark", quote: "TEST QUOTE" }), explicit.context);
  assert.equal(result.shell, "dark", "Explicit appearance must beat native appearance");
  assert.equal(explicit.attrs.get("data-dream-shell"), "dark");
  const oldState = explicit.window.__CODEX_AURORA_SKIN_STATE__;
  vm.runInNewContext(explicit.payloadFor({ appearance: "dark" }), explicit.context);
  assert.equal(oldState.cleanup(), false, "A stale cleanup must not remove the replacement");
  const replacement = explicit.window.__CODEX_AURORA_SKIN_STATE__;
  assert.equal(explicit.document.adoptedStyleSheets.length, 1);
  assert.equal(replacement.cleanup(), true);
  assert.equal(explicit.document.adoptedStyleSheets.length, 0);
  assert.equal(explicit.attrs.size, 0);
  assert.equal(explicit.rootStyle.values.size, 0);
  assert.equal(explicit.window.__CODEX_AURORA_SKIN_STATE__, undefined);
  assert.deepEqual(explicit.revoked, ["blob:fixture-1", "blob:fixture-2"]);

  const fallback = makeFixture({ nativeAppearance: "dark", adopted: false });
  vm.runInNewContext(fallback.payloadFor(), fallback.context);
  const fallbackState = fallback.window.__CODEX_AURORA_SKIN_STATE__;
  assert.equal(fallbackState.styleMode, "style");
  assert.ok(fallback.nodes.has("codex-aurora-skin-style"));
  assert.equal(fallbackState.cleanup(), true);
  assert.equal(fallback.nodes.has("codex-aurora-skin-style"), false);

  console.log(`PASS: unified renderer runtime (${path.basename(assetRoot)})`);
}

const fixture = { template: "" };
