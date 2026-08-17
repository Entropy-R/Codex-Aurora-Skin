import assert from "node:assert/strict";
import fs from "node:fs/promises";
import { gradeDoctorResult, pageDoctor, selectorMatchesScope } from "./doctor-selectors.mjs";

const contract = JSON.parse(await fs.readFile(new URL("./selectors.json", import.meta.url), "utf8"));
const resultFor = (baseState, hits, overlay = false) => gradeDoctorResult(contract, {
  baseState,
  overlay,
  appearance: "dark",
  probes: contract.selectors.map(({ key }) => ({ key, count: hits.includes(key) ? 1 : 0 })),
});

const home = resultFor("home", [
  "shell-main", "left-panel", "header-tint", "home-icon", "home-route", "home-route-css",
]);
assert.equal(home.pass, true);
assert.equal(home.exitCode, 0);
assert.equal(home.tiers.L1.length, 6);
assert.equal(home.tiers.L2.find(({ key }) => key === "project-selector").status, "miss(config)");

const brokenHome = resultFor("home", ["shell-main", "left-panel", "header-tint", "home-icon"]);
assert.equal(brokenHome.pass, false);
assert.equal(brokenHome.exitCode, 1);

const settings = resultFor("settings", ["appearance-radio"]);
assert.equal(settings.pass, true);
assert.equal(settings.tiers.L1.length, 0, "Settings must not inherit home/all L1 requirements");
assert.deepEqual(settings.tiers.L2.map(({ key }) => key), ["settings-panel", "appearance-radio"]);

const unknown = resultFor("unknown", []);
assert.equal(unknown.pass, false, "Unknown app surfaces must never receive a false-green result");
assert.equal(unknown.exitCode, 1);

const selectorFor = (key) => contract.selectors.find((entry) => entry.key === key)?.selector;
assert.match(selectorFor("shell-main"), /data-app-shell-main-surface/);
assert.match(selectorFor("shell-main"), /_MainContentSurface_/);
assert.match(selectorFor("header-tint"), /data-app-shell-header-edge-scroll/);
assert.match(selectorFor("composer-chrome"), /data-composer-surface-variant/);
assert.match(selectorFor("composer-toolbar"), /data-composer-footer-responsive/);

const pageResultFor = (hits) => {
  const hitSet = new Set(hits);
  const originalDocument = globalThis.document;
  const originalMatchMedia = globalThis.matchMedia;
  globalThis.document = {
    documentElement: { classList: { contains: (name) => name === "electron-dark" } },
    querySelector(selector) {
      return this.querySelectorAll(selector)[0] || null;
    },
    querySelectorAll(selector) {
      const contractKey = contract.selectors.find((entry) => entry.selector === selector)?.key;
      if (contractKey && hitSet.has(contractKey)) return [{}];
      const testid = /^\[data-testid="([^"]+)"\]$/.exec(selector)?.[1];
      return testid && hitSet.has(`testid:${testid}`) ? [{}] : [];
    },
  };
  globalThis.matchMedia = () => ({ matches: false });
  try {
    return pageDoctor(contract.selectors, contract.stableTestids);
  } finally {
    globalThis.document = originalDocument;
    globalThis.matchMedia = originalMatchMedia;
  }
};

const codex26810 = pageResultFor(["shell-main", "left-panel", "header-tint", "composer-chrome"]);
assert.equal(codex26810.baseState, "thread");
assert.equal(gradeDoctorResult(contract, codex26810).pass, true);

const modernSettings = pageResultFor(["settings-panel"]);
assert.equal(modernSettings.baseState, "settings");
assert.equal(gradeDoctorResult(contract, modernSettings).pass, true);

const unknownPage = pageResultFor([]);
assert.equal(unknownPage.baseState, "unknown");
assert.equal(gradeDoctorResult(contract, unknownPage).pass, false);

assert.equal(selectorMatchesScope("home+thread", { baseState: "thread", overlay: false }), true);
assert.equal(selectorMatchesScope("home config", { baseState: "home", overlay: false }), true);
assert.equal(selectorMatchesScope("overlay", { baseState: "home", overlay: true }), true);

console.log("PASS: selector doctor applies state scopes and L1 grading.");
