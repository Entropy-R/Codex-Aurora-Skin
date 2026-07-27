#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const libraryRoot = path.join(repositoryRoot, "library");
const integrity = JSON.parse(await fs.readFile(path.join(libraryRoot, "integrity.json"), "utf8"));
const catalog = JSON.parse(await fs.readFile(path.join(libraryRoot, "catalog.json"), "utf8"));

if (integrity.schemaVersion !== 1 || !integrity.files ||
    catalog.schemaVersion !== 1 || !Array.isArray(catalog.themes)) {
  throw new Error("内置资源完整性清单格式不受支持");
}

const expectedThemeFiles = new Set();
for (const entry of catalog.themes) {
  if (!entry.id || !entry.directory || !entry.license) {
    throw new Error("内置资源目录缺少 ID、目录或许可记录");
  }
  const theme = JSON.parse(await fs.readFile(
    path.join(libraryRoot, entry.directory, "theme.json"),
    "utf8",
  ));
  if (theme.schemaVersion !== 2 || theme.id !== entry.id || theme.appearance !== "auto" ||
      !theme.image || !theme.thumbnail) {
    throw new Error(`内置主题协议不完整：${entry.id}`);
  }
  expectedThemeFiles.add(`${entry.directory}/theme.json`);
  expectedThemeFiles.add(`${entry.directory}/${theme.image}`);
  expectedThemeFiles.add(`${entry.directory}/${theme.thumbnail}`);
}

const declared = new Set(Object.keys(integrity.files));
if (!declared.has("catalog.json") ||
    [...expectedThemeFiles].some((relative) => !declared.has(relative)) ||
    declared.size !== expectedThemeFiles.size + 1) {
  throw new Error("内置资源完整性清单与 catalog.json 不一致");
}

async function listFiles(directory, prefix = "") {
  const files = [];
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) files.push(...await listFiles(path.join(directory, entry.name), relative));
    else if (entry.isFile() && relative !== "integrity.json") files.push(relative);
    else if (!entry.isFile()) throw new Error(`内置资源目录不允许链接或特殊文件：${relative}`);
  }
  return files;
}
const actualFiles = new Set(await listFiles(libraryRoot));
if (actualFiles.size !== declared.size ||
    [...actualFiles].some((relative) => !declared.has(relative))) {
  throw new Error("内置资源目录包含未登记文件或缺少登记文件");
}

for (const [relative, expected] of Object.entries(integrity.files)) {
  if (!/^[a-f0-9]{64}$/.test(expected) || path.isAbsolute(relative) ||
      relative.split(/[\\/]/u).includes("..")) {
    throw new Error(`内置资源清单路径或哈希不合法：${relative}`);
  }
  const bytes = await fs.readFile(path.join(libraryRoot, relative));
  const actual = createHash("sha256").update(bytes).digest("hex");
  if (actual !== expected) throw new Error(`内置资源哈希不匹配：${relative}`);
}

process.stdout.write(`PASS: ${catalog.themes.length} 个内置主题资源及许可记录完整。\n`);
