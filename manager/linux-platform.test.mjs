import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(here, "..");

test("manager accepts the Linux platform and serves its authenticated API", async (context) => {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "aurora-linux-manager-"));
  const stateRoot = path.join(temporary, "state");
  const activeRoot = path.join(stateRoot, "theme");
  await fs.mkdir(stateRoot, { recursive: true });
  const child = spawn(process.execPath, [
    path.join(here, "server.mjs"),
    "--platform", "linux",
    "--engine-root", repositoryRoot,
    "--state-root", stateRoot,
    "--active-root", activeRoot,
    "--node", process.execPath,
    "--injector", path.join(repositoryRoot, "linux", "scripts", "injector.mjs"),
    "--start", "/bin/true",
    "--restore", "/bin/true",
  ], { stdio: ["ignore", "pipe", "pipe"] });
  let stderr = "";
  child.stderr.on("data", (chunk) => { stderr += chunk; });

  context.after(async () => {
    child.kill("SIGTERM");
    await fs.rm(temporary, { recursive: true, force: true });
  });

  const line = await new Promise((resolve, reject) => {
    let output = "";
    const timeout = setTimeout(() => reject(new Error("manager startup timed out")), 5000);
    child.stdout.on("data", (chunk) => {
      output += chunk;
      const match = /^MANAGER_URL=(.+)$/m.exec(output);
      if (match) {
        clearTimeout(timeout);
        resolve(match[1]);
      }
    });
    child.once("exit", (code) => {
      if (stderr.includes("listen EPERM")) {
        clearTimeout(timeout);
        resolve(null);
        return;
      }
      reject(new Error(`manager exited early: ${code}\n${stderr}`));
    });
  });
  if (!line) {
    context.skip("sandbox does not permit a loopback listener");
    return;
  }
  const managerUrl = new URL(line);
  const token = managerUrl.searchParams.get("bootstrap");
  const response = await fetch(new URL("/api/ping", managerUrl), {
    headers: { Authorization: `Bearer ${token}` },
  });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).ok, true);
});
