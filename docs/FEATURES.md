# jxproxy — Feature Flags

All 88 feature flags from upstream Claude Code, audited and categorized.

## Status Summary

| Category | Working | Broken | Total |
|----------|--------:|-------:|------:|
| Default feature | 1 | 0 | 1 |
| Experimental (Interaction & UI) | 14 | 0 | 14 |
| Experimental (Agent, Memory & Planning) | 10 | 0 | 10 |
| Experimental (Tools, Permissions & Remote) | 13 | 0 | 13 |
| Bundle-clean support flags | 17 | 0 | 17 |
| Easy reconstruction | 0 | 16 | 16 |
| Medium-sized gaps | 0 | 15 | 15 |
| Large missing subsystems | 0 | 3 | 3 |
| **Total** | **55** | **34** | **89** |

## Working (55 — all enabled in jxproxy)

### Default
- `VOICE_MODE` — Voice toggling, dictation keybindings, voice UI

### Interaction & UI (14)
- `AWAY_SUMMARY` — Away-from-keyboard summary in REPL
- `HISTORY_PICKER` — Interactive prompt history picker
- `HOOK_PROMPTS` — Passes prompt text into hook execution flows
- `KAIROS_BRIEF` — Brief-only transcript layout
- `KAIROS_CHANNELS` — Channel notices and MCP/channel callback plumbing
- `LODESTONE` — Deep-link / protocol-registration flows
- `MESSAGE_ACTIONS` — Message action entrypoints
- `NEW_INIT` — Newer `/init` decision path
- `QUICK_SEARCH` — Prompt quick-search behavior
- `SHOT_STATS` — Shot-distribution stats views
- `TOKEN_BUDGET` — Token budget tracking, prompt triggers, warning UI
- `ULTRAPLAN` — Enables `/ultraplan`, prompt triggers, exit-plan affordances
- `ULTRATHINK` — Extra thinking-depth mode switch
- `VOICE_MODE` — Voice toggling, dictation keybindings, voice UI

### Agent, Memory & Planning (10)
- `AGENT_MEMORY_SNAPSHOT` — Stores extra custom-agent memory snapshot state
- `AGENT_TRIGGERS` — Local cron/trigger tools and bundled trigger skills
- `AGENT_TRIGGERS_REMOTE` — Remote trigger tool path
- `BUILTIN_EXPLORE_PLAN_AGENTS` — Built-in explore/plan agent presets
- `CACHED_MICROCOMPACT` — Cached microcompact state through query/API flows
- `COMPACTION_REMINDERS` — Reminder copy around compaction and attachments
- `EXTRACT_MEMORIES` — Post-query memory extraction hooks
- `PROMPT_CACHE_BREAK_DETECTION` — Cache-break detection around compaction/query/API
- `TEAMMEM` — Team-memory files, watcher hooks, UI messages
- `VERIFICATION_AGENT` — Verification-agent guidance in prompts and task/todo tooling

### Tools, Permissions & Remote (13)
- `BASH_CLASSIFIER` — Classifier-assisted bash permission decisions
- `BRIDGE_MODE` — Remote Control / REPL bridge command
- `CCR_AUTO_CONNECT` — CCR auto-connect default path
- `CCR_MIRROR` — Outbound-only CCR mirror sessions
- `CCR_REMOTE_SETUP` — Remote setup command path
- `CHICAGO_MCP` — Computer-use MCP integration
- `CONNECTOR_TEXT` — Connector-text block handling in API/logging/UI
- `MCP_RICH_OUTPUT` — Richer MCP UI rendering
- `NATIVE_CLIPBOARD_IMAGE` — macOS clipboard image fast path
- `POWERSHELL_AUTO_MODE` — PowerShell-specific auto-mode permission handling
- `TREE_SITTER_BASH` — Tree-sitter bash parser backend
- `TREE_SITTER_BASH_SHADOW` — Tree-sitter bash shadow rollout path
- `UNATTENDED_RETRY` — Unattended retry in API retry flows

### Bundle-Clean Support Flags (17)
- `ABLATION_BASELINE` — CLI ablation/baseline entrypoint toggle
- `ALLOW_TEST_VERSIONS` — Allows test versions in native installer flows
- `ANTI_DISTILLATION_CC` — Anti-distillation request metadata
- `BREAK_CACHE_COMMAND` — Injects break-cache command path
- `COWORKER_TYPE_TELEMETRY` — Adds coworker-type telemetry fields
- `DOWNLOAD_USER_SETTINGS` — Settings-sync pull paths
- `DUMP_SYSTEM_PROMPT` — System-prompt dump path
- `FILE_PERSISTENCE` — File persistence plumbing
- `HARD_FAIL` — Stricter failure/logging behavior
- `IS_LIBC_GLIBC` — Forces glibc environment detection
- `IS_LIBC_MUSL` — Forces musl environment detection
- `NATIVE_CLIENT_ATTESTATION` — Native attestation marker in system header
- `PERFETTO_TRACING` — Perfetto tracing hooks
- `SKILL_IMPROVEMENT` — Skill-improvement hooks
- `SKIP_DETECTION_WHEN_AUTOUPDATES_DISABLED` — Skips updater detection when auto-updates off
- `SLOW_OPERATION_LOGGING` — Slow-operation logging
- `UPLOAD_USER_SETTINGS` — Settings-sync push paths

## Broken (34 — reconstruction notes)

### Easy Reconstruction (16)
These flags have a small blocker — a missing file or wrapper — and could likely be restored with focused effort.

| Flag | Missing Piece |
|------|---------------|
| `AUTO_THEME` | `src/utils/systemThemeWatcher.js` |
| `BG_SESSIONS` | `src/cli/bg.js` |
| `BUDDY` | `src/commands/buddy/index.js` |
| `BUILDING_CLAUDE_APPS` | `src/claude-api/csharp/claude-api.md` |
| `COMMIT_ATTRIBUTION` | `src/utils/attributionHooks.js` |
| `FORK_SUBAGENT` | `src/commands/fork/index.js` |
| `HISTORY_SNIP` | `src/commands/force-snip.js` |
| `KAIROS_GITHUB_WEBHOOKS` | `src/tools/SubscribePRTool/SubscribePRTool.js` |
| `KAIROS_PUSH_NOTIFICATION` | `src/tools/PushNotificationTool/PushNotificationTool.js` |
| `MCP_SKILLS` | `src/skills/mcpSkills.js` |
| `MEMORY_SHAPE_TELEMETRY` | `src/memdir/memoryShapeTelemetry.js` |
| `OVERFLOW_TEST_TOOL` | `src/tools/OverflowTestTool/OverflowTestTool.js` |
| `RUN_SKILL_GENERATOR` | `src/runSkillGenerator.js` |
| `TEMPLATES` | `src/cli/handlers/templateJobs.js` |
| `TORCH` | `src/commands/torch.js` |
| `TRANSCRIPT_CLASSIFIER` | `src/utils/permissions/yolo-classifier-prompts/auto_mode_system_prompt.txt` |

### Medium-Sized Gaps (15)
These require a larger reconstruction effort — the missing piece is more than a single file.

| Flag | Missing Subsystem |
|------|-------------------|
| `BYOC_ENVIRONMENT_RUNNER` | `src/environment-runner/main.js` |
| `CONTEXT_COLLAPSE` | `src/tools/CtxInspectTool/CtxInspectTool.js` |
| `COORDINATOR_MODE` | `src/coordinator/workerAgent.js` |
| `DAEMON` | `src/daemon/workerRegistry.js` |
| `DIRECT_CONNECT` | `src/server/parseConnectUrl.js` |
| `EXPERIMENTAL_SKILL_SEARCH` | `src/services/skillSearch/localSearch.js` |
| `MONITOR_TOOL` | `src/tools/MonitorTool/MonitorTool.js` |
| `REACTIVE_COMPACT` | `src/services/compact/reactiveCompact.js` |
| `REVIEW_ARTIFACT` | `src/hunter.js` |
| `SELF_HOSTED_RUNNER` | `src/self-hosted-runner/main.js` |
| `SSH_REMOTE` | `src/ssh/createSSHSession.js` |
| `TERMINAL_PANEL` | `src/tools/TerminalCaptureTool/TerminalCaptureTool.js` |
| `UDS_INBOX` | `src/utils/udsMessaging.js` |
| `WEB_BROWSER_TOOL` | `src/tools/WebBrowserTool/WebBrowserTool.js` |
| `WORKFLOW_SCRIPTS` | `src/commands/workflows/index.js` |

### Large Missing Subsystems (3)
These require substantial upstream source that is not present in the fork.

| Flag | Missing Subsystem |
|------|-------------------|
| `KAIROS` | `src/assistant/index.js` — full assistant stack |
| `KAIROS_DREAM` | `src/dream.js` — dream-task behavior |
| `PROACTIVE` | `src/proactive/index.js` — proactive task/tool stack |

## Building with Custom Feature Flags

```bash
# Build with default features + specific experimental flags
bun run build --feature=ULTRAPLAN --feature=ULTRATHINK

# Full unlock (all 55 working)
bun run build        # Default — enables all working flags

# Dev build with custom set
bun run scripts/build.ts --dev --feature=AGENT_TRIGGERS --feature=TEAMMEM

# Target specific OS
bun run scripts/build.ts --target=linux-arm64
bun run scripts/build.ts --target=bun-windows-x64
```
