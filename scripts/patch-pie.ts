#!/usr/bin/env bun
/**
 * PIE Patcher — Converts ET_EXEC (non-PIE) linux-arm64 ELF binaries to ET_DYN (PIE)
 *
 * Bun's cross-compilation for linux-arm64 produces ET_EXEC binaries that can't
 * run on Android (blocks non-PIE exec). The code IS position-independent
 * (no TEXTREL, no R_AARCH64_RELATIVE needed). This script fixes just e_type.
 *
 * Usage: bun run scripts/patch-pie.ts <binary> [binary2 ...]
 *
 * After patching: patchelf --set-interpreter works, Android allows PIE execve.
 */

import { readFileSync, writeFileSync } from "fs";
import { exit } from "process";

const ET_EXEC = 2;
const ET_DYN = 3;

function main() {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    console.error("Usage: patch-pie.ts <binary> [binary2 ...]");
    exit(1);
  }

  for (const path of args) {
    patch(path);
  }
}

function patch(path: string) {
  const orig = readFileSync(path);
  const data = Buffer.from(orig);

  // Validate ELF
  if (data[0] !== 0x7f || data[1] !== 0x45 || data[2] !== 0x4c || data[3] !== 0x46) {
    console.error(`  ✗ Not a valid ELF: ${path}`);
    return;
  }
  if (data[4] !== 2) {
    console.error(`  ✗ Not 64-bit ELF: ${path}`);
    return;
  }

  const e_type = data.readUInt16LE(16);
  if (e_type !== ET_EXEC) {
    console.log(`  − Already PIE (e_type=${e_type}), skipping: ${path}`);
    return;
  }

  // Change e_type ET_EXEC (2) → ET_DYN (3)
  data.writeUInt16LE(ET_DYN, 16);
  writeFileSync(path, data);

  // Verify
  const check = Buffer.from(readFileSync(path));
  const newType = check.readUInt16LE(16);
  if (newType === ET_DYN) {
    console.log(`  ✓ PIE patched: ${path}`);
  } else {
    console.error(`  ✗ Patch failed: e_type is ${newType}`);
  }
}

main();
