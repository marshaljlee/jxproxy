/**
 * Stub for @ant/computer-use-mcp
 *
 * This module is an Anthropic-internal package that provides the Computer Use
 * MCP server. In the open-source free-code fork, all code paths that actually
 * call into this module are gated behind:
 *   - process.env.USER_TYPE === 'ant' (always false in jxproxy)
 *   - feature('CHICAGO_MCP') (off by default)
 *   - process.platform === 'darwin' (platform checks)
 *
 * These stubs exist so that Bun's bundler can resolve the static imports
 * at build time. The runtime values are never actually used because the
 * guarded code paths are eliminated by dead-code removal.
 */

// ── Runtime values (never actually invoked) ──────────────────────────

export const API_RESIZE_PARAMS = null as any;
export const targetImageSize = null as any;
export const buildComputerUseTools = null as any;
export const createComputerUseMcpServer = null as any;
export const bindSessionContext = null as any;
export const DEFAULT_GRANT_FLAGS = 0;

// ── Type-only exports ───────────────────────────────────────────────

export type ComputerExecutor = any;
export type DisplayGeometry = any;
export type FrontmostApp = any;
export type InstalledApp = any;
export type ResolvePrepareCaptureResult = any;
export type RunningApp = any;
export type ScreenshotResult = any;

export type ComputerUseSessionContext = any;
export type CuCallToolResult = any;
export type CuPermissionRequest = any;
export type CuPermissionResponse = any;
export type ScreenshotDims = any;
