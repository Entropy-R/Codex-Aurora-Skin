#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const candidates = [
  path.resolve(here, "../../macos/scripts/injector.mjs"),
  path.resolve(here, "../vendor/injector.mjs"),
];
const implementation = candidates.find((candidate) => fs.existsSync(candidate));

if (!implementation) {
  throw new Error("Linux injector implementation is missing from the engine");
}

process.env.CODEX_AURORA_SKIN_ASSETS_ROOT ||= path.resolve(here, "../assets");
const { main } = await import(pathToFileURL(implementation).href);
await main(process.argv.slice(2));
