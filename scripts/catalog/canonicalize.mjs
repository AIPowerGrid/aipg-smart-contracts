#!/usr/bin/env node

import { readFile } from "node:fs/promises";

function assertValidUnicode(value, location) {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) {
        throw new Error(`${location} contains an unpaired high surrogate`);
      }
      index += 1;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      throw new Error(`${location} contains an unpaired low surrogate`);
    }
  }
}

function canonicalize(value, location = "$") {
  if (value === null || typeof value === "boolean") {
    return JSON.stringify(value);
  }
  if (typeof value === "string") {
    assertValidUnicode(value, location);
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new Error(`${location} contains a non-finite number`);
    }
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item, index) => canonicalize(item, `${location}[${index}]`)).join(",")}]`;
  }
  if (typeof value === "object") {
    const keys = Object.keys(value).sort();
    return `{${keys
      .map((key) => {
        assertValidUnicode(key, `${location} key`);
        return `${JSON.stringify(key)}:${canonicalize(value[key], `${location}.${key}`)}`;
      })
      .join(",")}}`;
  }
  throw new Error(`${location} contains unsupported JSON data`);
}

if (process.argv.length !== 3) {
  console.error("Usage: canonicalize.mjs <json-file>");
  process.exit(2);
}

try {
  const source = await readFile(process.argv[2], "utf8");
  process.stdout.write(canonicalize(JSON.parse(source)));
} catch (error) {
  console.error(`JCS error: ${error.message}`);
  process.exit(1);
}
