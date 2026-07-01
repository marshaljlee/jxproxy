#!/usr/bin/env bun
/**
 * jxproxy Build Script
 *
 * Compiles the modified Claude Code CLI into a single standalone binary
 * with all 54 working experimental features enabled.
 *
 * Usage:
 *   bun run scripts/build.ts
 *   bun run scripts/build.ts --dev              # Dev variant with debug info
 *   bun run scripts/build.ts --feature=EXTRA    # Add a specific feature flag
 *   bun run scripts/build.ts --target=linux-arm64  # Cross-compile target
 *
 * Based on the free-code build system.
 */

import { $ } from "bun";
import { existsSync, mkdirSync, copyFileSync } from "fs";
import { resolve } from "path";
import { argv, exit, version } from "process";

// --- Feature Flags ---

const DEFAULT_FEATURES = ["VOICE_MODE"];

const EXPERIMENTAL_FEATURES = [
  // Interaction & UI (14)
  "AWAY_SUMMARY",
  "HISTORY_PICKER",
  "HOOK_PROMPTS",
  "KAIROS_BRIEF",
  "KAIROS_CHANNELS",
  "LODESTONE",
  "MESSAGE_ACTIONS",
  "NEW_INIT",
  "QUICK_SEARCH",
  "SHOT_STATS",
  "TOKEN_BUDGET",
  "ULTRAPLAN",
  "ULTRATHINK",
  "VOICE_MODE",

  // Agent, Memory & Planning (10)
  "AGENT_MEMORY_SNAPSHOT",
  "AGENT_TRIGGERS",
  "AGENT_TRIGGERS_REMOTE",
  "BUILTIN_EXPLORE_PLAN_AGENTS",
  "CACHED_MICROCOMPACT",
  "COMPACTION_REMINDERS",
  "EXTRACT_MEMORIES",
  "PROMPT_CACHE_BREAK_DETECTION",
  "TEAMMEM",
  "VERIFICATION_AGENT",

  // Tools, Permissions & Remote (13)
  "BASH_CLASSIFIER",
  "BRIDGE_MODE",
  "CCR_AUTO_CONNECT",
  "CCR_MIRROR",
  "CCR_REMOTE_SETUP",
  "CHICAGO_MCP",
  "CONNECTOR_TEXT",
  "MCP_RICH_OUTPUT",
  "NATIVE_CLIPBOARD_IMAGE",
  "POWERSHELL_AUTO_MODE",
  "TREE_SITTER_BASH",
  "TREE_SITTER_BASH_SHADOW",
  "UNATTENDED_RETRY",

  // Bundle-clean support flags (17)
  "ABLATION_BASELINE",
  "ALLOW_TEST_VERSIONS",
  "ANTI_DISTILLATION_CC",
  "BREAK_CACHE_COMMAND",
  "COWORKER_TYPE_TELEMETRY",
  "DOWNLOAD_USER_SETTINGS",
  "DUMP_SYSTEM_PROMPT",
  "FILE_PERSISTENCE",
  "HARD_FAIL",
  "IS_LIBC_GLIBC",
  "IS_LIBC_MUSL",
  "NATIVE_CLIENT_ATTESTATION",
  "PERFETTO_TRACING",
  "SKILL_IMPROVEMENT",
  "SKIP_DETECTION_WHEN_AUTOUPDATES_DISABLED",
  "SLOW_OPERATION_LOGGING",
  "UPLOAD_USER_SETTINGS",
];

// --- Parse CLI Arguments ---

const isDev = argv.includes("--dev");
const customFeatures: string[] = [];
const featureArgs: string[] = [];
let outputTarget = "bun";

for (const arg of argv.slice(2)) {
  if (arg === "--dev") continue;
  if (arg.startsWith("--feature=")) {
    const feature = arg.split("=")[1];
    customFeatures.push(feature);
    continue;
  }
  if (arg.startsWith("--target=")) {
    outputTarget = arg.split("=")[1];
    continue;
  }
  featureArgs.push(arg);
}

// --- Build Feature Set ---

const featureSet = new Set(DEFAULT_FEATURES);

if (customFeatures.length === 0) {
  // Full unlock: enable all experimental features
  for (const f of EXPERIMENTAL_FEATURES) {
    featureSet.add(f);
  }
} else {
  for (const f of customFeatures) {
    featureSet.add(f);
  }
}

const features = [...featureSet];
const featureFlags = features.map((f) => `--feature=${f}`);

// --- Build Configuration ---

const SOURCE_DIR = resolve(import.meta.dir, "..", "src");
const OUT_DIR = resolve(import.meta.dir, "..", "dist");
const OUT_FILE = resolve(OUT_DIR, isDev ? "jxproxy-dev" : "jxproxy");
const ENTRY = resolve(SOURCE_DIR, "entrypoints", "cli.tsx");

if (!existsSync(SOURCE_DIR)) {
  console.error(
    "✗ Source directory not found at", SOURCE_DIR,
    "\n  Run 'bun run bootstrap' first to fetch the base source."
  );
  exit(1);
}

if (!existsSync(ENTRY)) {
  console.error(
    "✗ Entry point not found at", ENTRY,
    "\n  Run 'bun run patch' to apply jxproxy patches."
  );
  exit(1);
}

if (!existsSync(OUT_DIR)) {
  mkdirSync(OUT_DIR, { recursive: true });
}

// --- Build Version Info ---

const versionInfo = readVersionInfo();

// --- Compile ---

console.log(`\n  jxproxy build`);
console.log(`  ${"=".repeat(60)}`);
console.log(`  Features: ${features.length} enabled`);
console.log(`  Dev mode: ${isDev ? "yes" : "no"}`);
console.log(`  Target:   ${outputTarget}`);
console.log(`  Output:   ${OUT_FILE}`);
console.log(`  ${"=".repeat(60)}\n`);

const cmd = [
  "bun",
  "build",
  ENTRY,
  "--compile",
  `--target=${outputTarget}`,
  "--format", "esm",
  "--minify",
  "--bytecode",
  "--packages", "bundle",
  "--conditions", "bun",
  "--outfile", OUT_FILE,
  ...featureFlags,
  // Telemetry packages excluded from bundle (they exist in the base source
  // but are dead-code-eliminated — we externalize to shrink the binary)
  "--external", "@opentelemetry/api",
  "--external", "@opentelemetry/exporter-trace-otlp-grpc",
  "--external", "@opentelemetry/resources",
  "--external", "@opentelemetry/semantic-conventions",
  "--external", "@opentelemetry/sdk-node",
  "--external", "@opentelemetry/sdk-trace-base",
  "--external", "@opentelemetry/sdk-trace-node",
  "--external", "@sentry/node",
  "--external", "@growthbook/growthbook",
  // Native addons
  "--external", "audio-capture-napi",
  "--external", "image-processor-napi",
  "--external", "keyring-napi",
  "--external", "microphone-napi",
  "--external", "speaker-napi",
  "--external", "pasteboard-napi",
  // Compile-time defines
  "--define", `MACRO.VERSION="${versionInfo.version}"`,
  "--define", `MACRO.BUILD_TIME="${versionInfo.buildTime}"`,
  "--define", `MACRO.PACKAGE_URL="@jxproxy/cli"`,
  "--define", `MACRO.NATIVE_PACKAGE_URL=undefined`,
  "--define", `MACRO.FEEDBACK_CHANNEL="github"`,
  "--define", `MACRO.ISSUES_EXPLAINER="Report issues at github.com/your-org/jxproxy"`,
  "--define", `process.env.NODE_ENV="${isDev ? "development" : "production"}"`,
  "--define", `process.env.CLAUDE_CODE_EXPERIMENTAL_BUILD="${isDev ? "true" : "true"}"`,
  "--define", `process.env.USER_TYPE="external"`,
  "--define", `process.env.CLAUDE_CODE_FORCE_FULL_LOGO="true"`,
  "--define", `process.env.CLAUDE_CODE_VERIFY_PLAN="false"`,
  "--define", `process.env.CCR_FORCE_BUNDLE="true"`,
  // Telemetry kill switches — override any runtime checks
  "--define", `process.env.CLAUDE_CODE_DISABLE_TELEMETRY="true"`,
  "--define", `process.env.OTEL_SDK_DISABLED="true"`,
  "--define", `process.env.SENTRY_DSN=""`,
  "--define", `process.env.DO_NOT_TRACK="1"`,
  ...featureArgs,
];

const proc = Bun.spawnSync(cmd, {
  env: { ...process.env, NODE_ENV: isDev ? "development" : "production" },
  stdio: ["inherit", "inherit", "inherit"],
});

if (proc.exitCode !== 0) {
  console.error(`\n✗ Build failed with exit code ${proc.exitCode}`);
  exit(proc.exitCode);
}

// Make executable
await $`chmod 0o755 ${OUT_FILE}`;

// --- Build Proxy Binary Separately ---

console.log(`\n  ✓ jxproxy CLI built: ${OUT_FILE}`);

const PROXY_ENTRY = resolve(import.meta.dir, "..", "proxy", "server.ts");
const PROXY_OUT = resolve(OUT_DIR, "jxproxy-proxy");

if (existsSync(PROXY_ENTRY)) {
  console.log(`\n  Building proxy server...\n`);

  const proxyCmd = [
    "bun",
    "build",
    PROXY_ENTRY,
    "--compile",
    `--target=${outputTarget}`,
    "--minify",
    "--bytecode",
    "--packages", "bundle",
    "--outfile", PROXY_OUT,
  ];

  const proxyProc = Bun.spawnSync(proxyCmd, {
    stdio: ["inherit", "inherit", "inherit"],
  });

  if (proxyProc.exitCode === 0) {
    await $`chmod 0o755 ${PROXY_OUT}`;
    console.log(`\n  ✓ jxproxy proxy built: ${PROXY_OUT}`);
  } else {
    console.warn(`  ⚠ Proxy build failed (exit ${proxyProc.exitCode}) — CLI only`);
  }
}

console.log(`\n  Done. Run ./${OUT_FILE} or set up with the platform installer.\n`);

// --- Helpers ---

function readVersionInfo() {
  try {
    const pkg = require(resolve(import.meta.dir, "..", "package.json"));
    const sha = ($`git rev-parse --short=8 HEAD`.text() || "unknown").trim();
    return {
      version: `${pkg.version}+${sha}`,
      buildTime: new Date().toISOString(),
    };
  } catch {
    return {
      version: "0.1.0+local",
      buildTime: new Date().toISOString(),
    };
  }
}
