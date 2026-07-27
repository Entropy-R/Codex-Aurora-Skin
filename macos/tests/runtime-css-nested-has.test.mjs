import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// Relational selectors participate in Chromium's continuous style
// invalidation. Route and local relationship checks therefore belong to the
// low-frequency renderer runtime, never the canonical or generated CSS.
const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

const files = [
  "runtime/aurora-skin.css",
  "macos/assets/aurora-skin.css",
  "windows/assets/aurora-skin.css",
];

for (const file of files) {
  test(`no CSS :has() in ${file}`, () => {
    const css = readFileSync(join(root, file), "utf8");
    assert.doesNotMatch(css, /:has\(/, `CSS :has() found in ${file}`);
  });
}
