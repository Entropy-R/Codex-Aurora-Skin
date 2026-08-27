import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const repositoryRoot = path.resolve(root, "..");
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");

const common = read("scripts/common-linux.sh");
assert.doesNotMatch(common, /^\s*HOME=/m);
assert.match(common, /USER_HOME="\$\{HOME:-\}"/);
assert.match(common, /dpkg-query -S/);
assert.match(common, /rpm -qf/);
assert.match(common, /\/proc\/\$pid\/exe/);
assert.match(common, /--remote-debugging-address=127\.0\.0\.1/);
assert.match(common, /port_belongs_to_chatgpt/);
assert.match(common, /pid_is_chatgpt "\$pid" && return 0/);
assert.match(common, /cdp_browser_id/);
assert.match(common, /cdp_browser_id "\$1" >\/dev\/null 2>&1/);
assert.doesNotMatch(common, /--remote-debugging-address=0\.0\.0\.0/);

const start = read("scripts/start-aurora-skin-linux.sh");
assert.match(start, /verified_cdp_endpoint/);
assert.match(start, /--restart-existing/);
assert.match(start, /mark_state_active/);

const restore = read("scripts/restore-aurora-skin-linux.sh");
assert.match(restore, /--remove/);
assert.match(restore, /stop_recorded_injector/);
assert.match(restore, /--restart-codex/);

const installer = read("scripts/install-aurora-skin-linux.sh");
assert.match(installer, /\.engine-staging-/);
assert.match(installer, /engine\.backup\./);
assert.match(installer, /拒绝覆盖无关/);

const releaseBuilder = read("installer/build-release.sh");
assert.match(releaseBuilder, /--owner=0 --group=0 --numeric-owner/);
assert.match(releaseBuilder, /_buildhost codex-aurora-skin-builder/);

const fixtureTool = fs.readFileSync(path.join(repositoryRoot, "tools", "capture-dom-fixture.mjs"), "utf8");
const doctorTool = fs.readFileSync(path.join(repositoryRoot, "tools", "doctor-selectors.mjs"), "utf8");
for (const tool of [fixtureTool, doctorTool]) {
  assert.match(tool, /XDG_DATA_HOME/);
  assert.match(tool, /codex-aurora-skin["',)]*, ["']state["',)]*, ["']state\.json/);
}

console.log("PASS: Linux package identity, CDP ownership, restore, and installer contracts.");
