/**
 * Stub for @ant/claude-for-chrome-mcp
 *
 * Anthropic-internal package for Claude in Chrome integration.
 * The require() calls in package.ts are wrapped in try/catch,
 * so a failure returns null gracefully. The dynamic import()
 * variant is used only when the appropriate feature is enabled.
 */

export const BROWSER_TOOLS: any[] = [];

export function createClaudeForChromeMcpServer(_options?: any): any {
  return null;
}

export default {
  BROWSER_TOOLS,
  createClaudeForChromeMcpServer,
};
