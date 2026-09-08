import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const managerRoot = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(managerRoot, "..");

function waitForUrl(child) {
  return new Promise((resolve, reject) => {
    let output = "";
    const timer = setTimeout(() => reject(new Error(`管理器启动超时：${output}`)), 10_000);
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      output += chunk;
      const match = /MANAGER_URL=(http:\/\/127\.0\.0\.1:\d+\/\?bootstrap=[a-f0-9]{64})/.exec(output);
      if (match) {
        clearTimeout(timer);
        resolve(match[1]);
      }
    });
    child.once("exit", (code) => {
      clearTimeout(timer);
      reject(new Error(`管理器提前退出：${code} ${output}`));
    });
  });
}

test("本地管理 API 校验 Host、令牌并返回离线目录", async (t) => {
  const stateRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aurora-skin-server-"));
  const child = spawn(process.execPath, [
    path.join(managerRoot, "server.mjs"),
    "--platform", "windows",
    "--engine-root", repositoryRoot,
    "--state-root", stateRoot,
    "--active-root", path.join(stateRoot, "active-theme"),
    "--node", process.execPath,
    "--injector", path.join(repositoryRoot, "windows", "scripts", "injector.mjs"),
    "--start", path.join(repositoryRoot, "windows", "scripts", "start-aurora-skin.ps1"),
    "--restore", path.join(repositoryRoot, "windows", "scripts", "restore-aurora-skin.ps1"),
  ], { stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
  t.after(async () => {
    child.kill();
    await fs.rm(stateRoot, { recursive: true, force: true });
  });

  const managerUrl = new URL(await waitForUrl(child));
  const token = managerUrl.searchParams.get("bootstrap");
  const base = managerUrl.origin;

  const apiClient = await fetch(`${base}/api-client.mjs`);
  assert.equal(apiClient.status, 200);
  assert.match(await apiClient.text(), /export async function requestJson/);

  const unauthorized = await fetch(`${base}/api/bootstrap`);
  assert.equal(unauthorized.status, 401);

  const hostileHost = await fetch(`${base}/api/bootstrap`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Origin: "http://localhost.invalid",
    },
  });
  assert.equal(hostileHost.status, 403);

  const bootstrap = await fetch(`${base}/api/bootstrap`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  assert.equal(bootstrap.status, 200);
  const payload = await bootstrap.json();
  assert.equal(payload.ok, true);
  assert.equal(payload.themes.length, 1);
  assert.equal(payload.activeThemeId, "preset-red-white-abstract");

  const headers = { Authorization: `Bearer ${token}` };
  const form = new FormData();
  form.append("name", "接口导入主题");
  form.append("image", new Blob([await fs.readFile(path.join(
    repositoryRoot,
    "library",
    "preset-red-white-abstract",
    "background.png",
  ))]), "background.png");
  form.append("thumbnail", new Blob([await fs.readFile(path.join(
    repositoryRoot,
    "library",
    "preset-red-white-abstract",
    "thumbnail.webp",
  ))]), "thumbnail.webp");
  const imported = await fetch(`${base}/api/themes/import`, {
    method: "POST",
    headers,
    body: form,
  });
  assert.equal(imported.status, 201);
  const importedId = (await imported.json()).id;

  const renamed = await fetch(`${base}/api/themes/${importedId}`, {
    method: "PATCH",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ name: "接口重命名主题" }),
  });
  assert.equal(renamed.status, 200);
  const deleted = await fetch(`${base}/api/themes/${importedId}`, {
    method: "DELETE",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ confirm: true }),
  });
  assert.equal(deleted.status, 200);
});
