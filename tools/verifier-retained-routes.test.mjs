import assert from "node:assert/strict";
import fs from "node:fs/promises";
import vm from "node:vm";
import { verifySession as verifyMac } from "../macos/scripts/injector.mjs";
import { verifySession as verifyWindows } from "../windows/scripts/injector.mjs";

const contract = JSON.parse(await fs.readFile(new URL("./selectors.json", import.meta.url), "utf8"));
const version = (await fs.readFile(new URL("../macos/VERSION", import.meta.url), "utf8")).trim();
const makeNode = (visible) => ({
  getBoundingClientRect: () => ({ x: 0, y: 0, width: visible ? 700 : 0, height: visible ? 90 : 0 }),
  checkVisibility: () => visible,
  closest() { return this; },
  querySelector: () => null,
});
const hidden = makeNode(false);
const visible = makeNode(true);
const selectorKeys = new Map(contract.selectors.map(({ selector, key }) => [selector, key]));
const sheet = {};
const context = {
  innerWidth: 1512,
  innerHeight: 949,
  getComputedStyle: () => ({ display: "block", visibility: "visible", backgroundColor: "rgba(0, 0, 0, 0)" }),
  window: { __CODEX_AURORA_SKIN_STATE__: {
    version, styleMode: "adopted", styleSheet: sheet,
    scope: { baseState: "thread", level: "L1", missingL1: [] },
  } },
  document: {
    documentElement: {
      getAttribute: (name) => name === "data-aurora-skin" ? "active" : null,
      scrollWidth: 1512, clientWidth: 1512, scrollHeight: 949, clientHeight: 949,
    },
    body: visible,
    adoptedStyleSheets: [sheet],
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; },
    querySelectorAll(selector) {
      const key = selectorKeys.get(selector);
      if (["home-icon", "home-route", "home-route-css"].includes(key)) return [hidden];
      if (["shell-main", "left-panel", "header-tint", "composer-chrome"].includes(key)) return [hidden, visible];
      return [];
    },
  },
};

for (const [platform, verify] of [["macOS", verifyMac], ["Windows", verifyWindows]]) {
  const result = await verify({ evaluate: (expression) => vm.runInNewContext(expression, context) });
  assert.equal(result.homePresent, false, `${platform}: 隐藏首页不得触发首页布局校验。`);
  assert.equal(result.shell.visible, true, `${platform}: 必须跳过第一个隐藏的主表面副本。`);
  assert.equal(result.composer.visible, true);
  assert.equal(result.pass, true, `${platform}: 可见对话应通过验证。`);
}
console.log("PASS: 两端 verifier 均忽略隐藏路由并选择可见的主表面与输入框。");
