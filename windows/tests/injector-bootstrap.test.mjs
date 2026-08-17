import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import { earlyPayloadFor, structurePassFor } from "../scripts/injector.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const injectorPath = path.resolve(here, "../scripts/injector.mjs");
const source = await fs.readFile(injectorPath, "utf8");

const visible = { visible: true };
assert.equal(structurePassFor({
  scope: { baseState: "thread", level: "L0", missingL1: ["shell-main", "header-tint"] },
}), false, "A degraded thread must not pass merely because it is L0.");
assert.equal(structurePassFor({
  scope: { baseState: "thread", level: "L1", missingL1: [] },
  shell: visible, sidebar: visible, header: visible,
}), true);
assert.equal(structurePassFor({
  scope: { baseState: "settings", level: "L0", missingL1: [] }, settingsAnchor: visible,
}), true);
assert.equal(structurePassFor({
  scope: { baseState: "unknown", level: "L0", missingL1: ["shell-main"] },
}), false);

function createFixture() {
  const domReady = [];
  const timers = new Map();
  const intervals = new Map();
  let nextTimer = 1;
  let nextInterval = 1;
  const markers = {
    shell: false, sidebar: false, main: false, settings: false,
    genericMain: false, composerInput: false, brand: false,
  };
  let root = {};
  let body = {};
  const context = {
    window: { installs: [] },
    location: { protocol: "app:" },
    document: {
      get documentElement() { return root; },
      get body() { return body; },
      addEventListener(type, callback) { if (type === "DOMContentLoaded") domReady.push(callback); },
      querySelector(selector) {
        if (selector.includes("main-surface") || selector.includes("MainContentSurface") ||
          selector.includes("app-shell-main-surface")) return markers.shell ? {} : null;
        if (selector === "aside.app-shell-left-panel") return markers.sidebar ? {} : null;
        if (selector === "[role=\"main\"]") return markers.main ? {} : null;
        if (selector === 'main, [role="main"]') return markers.genericMain ? {} : null;
        if (selector.includes("data-codex-composer") || selector.includes("role=\"textbox\"")) {
          return markers.composerInput ? {} : null;
        }
        if (selector.includes("app-shell-header-context-menu-surface")) return markers.brand ? {} : null;
        if (selector.includes("settings-panel-slug") || selector.includes("appearance-theme") ||
          selector.includes("theme-preview")) {
          return markers.settings ? {} : null;
        }
        return null;
      },
    },
    setTimeout(callback) {
      const id = nextTimer++;
      timers.set(id, callback);
      return id;
    },
    clearTimeout(id) { timers.delete(id); },
    setInterval(callback) {
      const id = nextInterval++;
      intervals.set(id, callback);
      return id;
    },
    clearInterval(id) { intervals.delete(id); },
  };
  return {
    context,
    markers,
    makeNotReady() { root = null; body = null; },
    makeReady() { root = {}; body = {}; },
    fireDomReady() { for (const callback of [...domReady]) callback(); },
    tick() { for (const callback of [...intervals.values()]) callback(); },
    observers: [],
  };
}

const guarded = createFixture();
vm.runInNewContext(earlyPayloadFor('window.installs.push("guarded")', "guarded"), guarded.context);
assert.deepEqual(guarded.context.window.installs, [], "Auxiliary app targets must remain untouched.");
assert.equal(guarded.observers.length, 0, "Early bootstrap must not install a broad MutationObserver.");
guarded.markers.shell = true;
guarded.tick();
assert.deepEqual(guarded.context.window.installs, [], "A shell without its sidebar is not sufficient for identity.");
guarded.markers.sidebar = true;
guarded.tick();
assert.deepEqual(guarded.context.window.installs, ["guarded"]);

const generic = createFixture();
vm.runInNewContext(earlyPayloadFor('window.installs.push("generic")', "generic"), generic.context);
generic.markers.genericMain = true;
generic.markers.composerInput = true;
generic.tick();
assert.deepEqual(generic.context.window.installs, [], "Generic probing must require the Codex brand anchor.");
generic.markers.brand = true;
generic.tick();
assert.deepEqual(generic.context.window.installs, ["generic"]);

const generations = createFixture();
generations.makeNotReady();
generations.markers.shell = true;
generations.markers.sidebar = true;
vm.runInNewContext(earlyPayloadFor('window.installs.push("old")', "old"), generations.context);
vm.runInNewContext(earlyPayloadFor('window.installs.push("new")', "new"), generations.context);
generations.makeReady();
generations.fireDomReady();
assert.deepEqual(
  generations.context.window.installs,
  ["new"],
  "A stale early script must yield to the newest watcher generation.",
);
assert.equal(generations.context.window.__CODEX_AURORA_SKIN_EARLY_APPLIED__, "new");

const earlyStart = source.indexOf("export function earlyPayloadFor");
const earlySource = source.slice(earlyStart, earlyStart + 2200);
assert.ok(earlyStart >= 0, "Early payload helper must remain exported for bootstrap tests.");
assert.doesNotMatch(earlySource, /MutationObserver|childList|subtree/,
  "Early bootstrap must not observe the entire renderer DOM.");
assert.match(earlySource, /DOMContentLoaded/);
assert.match(earlySource, /setInterval\(install, 250\)/);
const registrationStart = source.indexOf("earlyScriptId = await registerEarlyPayload");
const evaluateStart = source.indexOf("await session.evaluate(earlyPayloadFor", registrationStart);
const probeStart = source.indexOf("const probe = await waitForCodexProbe", registrationStart);
assert.ok(registrationStart >= 0 && evaluateStart > registrationStart && probeStart > evaluateStart,
  "New targets must register and run the early payload before full shell probing.");
assert.match(source, /if \(earlyInjectionFallback\) attachLoadFallback\(/,
  "Load-event reinjection must be attached only when early injection falls back.");
assert.match(source, /if \(!fallbackTargets\.get\(id\)\) return;/,
  "Fallback listeners must stay inert after a successful early registration.");
assert.match(source, /Page\.removeScriptToEvaluateOnNewDocument/,
  "Watcher shutdown and theme refresh must unregister persistent Page scripts.");
assert.match(source, /fs\.readFile\(loadedTheme\.themePath,\s*"utf8"\)/,
  "Theme refresh must hash JSON content instead of trusting same-length timestamp metadata.");
assert.match(source, /createHash\("sha256"\)\.update\(themeText,\s*"utf8"\)/);
assert.doesNotMatch(source, /scope\?\.level === 'L0'\s*\|\|/,
  "L0 must not bypass native structure verification.");
assert.match(source, /const l1StructurePass = \["home", "thread"\]\.includes/);
assert.match(source, /const settingsStructurePass = result\.scope\?\.baseState === "settings"/);
assert.match(source, /Boolean\(result\.settingsAnchor\?\.visible\)/);

console.log("PASS: Windows early injection is L0-ready, generation-safe, ordered before probing, and fallback-scoped.");
