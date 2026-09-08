#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const toolsRoot = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(toolsRoot, "..");

function read(relativePath) {
  return fs.readFileSync(path.join(projectRoot, relativePath), "utf8");
}

function readVersion(relativePath) {
  const value = read(relativePath).trim();
  if (!/^\d+\.\d+\.\d+$/.test(value)) {
    throw new Error(`${relativePath} must contain a three-part semantic version`);
  }
  return value;
}

function extractVersion(relativePath, pattern, label) {
  const matches = [...read(relativePath).matchAll(pattern)];
  if (matches.length !== 1) {
    throw new Error(`${relativePath} must define exactly one ${label}`);
  }
  return matches[0][1];
}

const expected = readVersion("macos/VERSION");
const versions = new Map([
  ["windows/VERSION", readVersion("windows/VERSION")],
  ["macos/package.json", JSON.parse(read("macos/package.json")).version],
  [
    "macos/scripts/common-macos.sh",
    extractVersion(
      "macos/scripts/common-macos.sh",
      /^SKIN_VERSION="([^"]+)"$/gm,
      "SKIN_VERSION",
    ),
  ],
  [
    "macos/scripts/injector.mjs",
    extractVersion(
      "macos/scripts/injector.mjs",
      /^const SKIN_VERSION = "([^"]+)";$/gm,
      "SKIN_VERSION",
    ),
  ],
  [
    "windows/scripts/injector.mjs",
    extractVersion(
      "windows/scripts/injector.mjs",
      /^const SKIN_VERSION = "([^"]+)";$/gm,
      "SKIN_VERSION",
    ),
  ],
]);

for (const [source, version] of versions) {
  if (version !== expected) {
    throw new Error(`${source} has version ${version}; expected ${expected}`);
  }
}

const sync = spawnSync(
  process.execPath,
  [path.join(toolsRoot, "sync-runtime-assets.mjs"), "--check"],
  {
    cwd: projectRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  },
);
if (sync.status !== 0) {
  process.stderr.write(sync.stdout);
  process.stderr.write(sync.stderr);
  throw new Error("shared runtime assets are not synchronized");
}

console.log(`PASS: project version ${expected} and shared runtime assets are consistent.`);
