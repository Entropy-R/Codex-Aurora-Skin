import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const script = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "scripts",
  "theme-config.mjs",
);

test("旧版 macOS 配置只迁移仍等于托管值的外观键", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "aurora-skin-mac-migration-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const config = path.join(root, "config.toml");
  const backup = path.join(root, "theme-backup.json");
  const archive = path.join(root, "theme-backup.archived.json");
  await fs.writeFile(
    config,
    '[desktop]\nappearanceTheme = "light"\nappearanceDarkCodeThemeId = "user-dark-code"\n',
  );
  await fs.writeFile(backup, `${JSON.stringify({
    schemaVersion: 1,
    platform: "darwin",
    createdAt: new Date().toISOString(),
    configPath: config,
    values: {
      appearanceTheme: 'appearanceTheme = "system"',
      appearanceDarkCodeThemeId: 'appearanceDarkCodeThemeId = "original-dark-code"',
    },
  }, null, 2)}\n`);

  await execFileAsync(process.execPath, [
    script, "migrate", config, backup, "light", archive,
  ]);
  const content = await fs.readFile(config, "utf8");
  assert.match(content, /appearanceTheme = "system"/);
  assert.match(content, /appearanceDarkCodeThemeId = "user-dark-code"/);
  await assert.rejects(fs.access(backup));
  await fs.access(archive);
});
