/**
 * jxproxy — Embedded Proxy Server
 *
 * A lightweight proxy that intercepts Anthropic Messages API traffic from
 * the modified Claude Code CLI and routes it to configured providers.
 *
 * Exposes:
 *   POST /v1/messages           → Anthropic Messages (streaming)
 *   POST /v1/messages/count_tokens → Token counting
 *   GET  /v1/models             → Model listing
 *   GET  /health                → Health check
 *   POST /stop                  → Stop active sessions
 *
 * All other requests (HEAD/OPTIONS) return 204 for compatibility probes.
 *
 * Usage:
 *   bun run proxy/server.ts
 *   # or as a compiled binary: ./dist/jxproxy-proxy
 *   # or embedded: bun build ./proxy/server.ts --compile
 *
 * Environment:
 *   JXPROXY_PORT          — Proxy listen port (default: 5529)
 *   JXPROXY_PROVIDER      — Provider backend (direct, openrouter, opencode-zen, opencode-go, openai, local)
 *   JXPROXY_AUTH_TOKEN    — Token Claude Code sends as x-api-key (default: jxproxy)
 *   ANTHROPIC_API_KEY     — API key for direct Anthropic routing
 *   OPENROUTER_API_KEY    — API key for OpenRouter routing
 *   OPENCODE_API_KEY      — API key for OpenCode Zen/Go
 *   FALLBACK_PROVIDERS    — Comma-separated fallback list (nvidia→openai, ollama→local)
 *   OPENAI_BASE_URL       — Custom base URL for openai / nvidia provider
 *   LOCAL_LLM_BASE_URL    — Base URL for local / ollama provider
 *   LOCAL_LLM_MODEL       — Default model for local / ollama provider
 *   MODEL, MODEL_OPUS, MODEL_SONNET, MODEL_HAIKU — Model routing
 */

const DEFAULT_PORT = 5529;

/** Timeout for upstream provider API calls (120 seconds for vision/slow models). */
const UPSTREAM_TIMEOUT_MS = 120_000;

// --- Type Definitions ---

interface MessagesRequest {
  model: string;
  messages: Array<{
    role: "user" | "assistant" | "system";
    content: string | Array<{ type: string; [key: string]: unknown }>;
  }>;
  system?: string | Array<{ type: string; text: string }>;
  max_tokens?: number;
  stream?: boolean;
  stop_sequences?: string[];
  temperature?: number;
  top_p?: number;
  top_k?: number;
  metadata?: Record<string, unknown>;
  tools?: Array<{
    name: string;
    description?: string;
    input_schema?: Record<string, unknown>;
  }>;
  tool_choice?: { type: "auto" | "any" | "tool"; name?: string };
  thinking?: { type: "enabled"; budget_tokens: number };
}

interface ModelInfo {
  id: string;
  object: string;
  created: number;
  owned_by: string;
  display_name?: string;
}

// --- Configuration ---

interface ProxyConfig {
  port: number;
  provider: "direct" | "openrouter" | "opencode-zen" | "opencode-go" | "openai" | "local";
  anthropicApiKey: string;
  openrouterApiKey: string;
  opencodeApiKey: string;
  openaiApiKey: string;
  model: string;
  modelOpus: string;
  modelSonnet: string;
  modelHaiku: string;
  enableThinking: boolean;
  authToken: string;
  openaiBaseUrl: string;
  localLlmBaseUrl: string;
  localLlmModel: string;
  /** Ordered list of fallback provider names (e.g. "nvidia,local") */
  fallbackProviders: string[];
}

function loadConfig(): ProxyConfig {
  return {
    port: parseInt(process.env.JXPROXY_PORT || String(DEFAULT_PORT), 10),
    provider: (process.env.JXPROXY_PROVIDER || "direct") as ProxyConfig["provider"],
    anthropicApiKey: process.env.ANTHROPIC_API_KEY || "",
    openrouterApiKey: process.env.OPENROUTER_API_KEY || "",
    opencodeApiKey: process.env.OPENCODE_API_KEY || "",
    openaiApiKey: process.env.OPENAI_API_KEY || "",
    model: process.env.MODEL || "claude-sonnet-5-20251001",
    modelOpus: process.env.MODEL_OPUS || "",
    modelSonnet: process.env.MODEL_SONNET || "",
    modelHaiku: process.env.MODEL_HAIKU || "",
    enableThinking: process.env.ENABLE_MODEL_THINKING !== "false",
    authToken: process.env.JXPROXY_AUTH_TOKEN || "jxproxy",
    openaiBaseUrl: process.env.OPENAI_BASE_URL || "https://api.openai.com/v1",
    localLlmBaseUrl: process.env.LOCAL_LLM_BASE_URL || "http://127.0.0.1:11434/v1",
    localLlmModel: process.env.LOCAL_LLM_MODEL || "qwen3:latest",
    fallbackProviders: parseFallbackProviders(process.env.FALLBACK_PROVIDERS || ""),
  };
}

// --- Model Routing ---

function resolveModel(config: ProxyConfig, incomingModel: string): string {
  const lower = incomingModel.toLowerCase();

  // Direct provider model refs (e.g., "openrouter/anthropic/claude-sonnet-5")
  if (incomingModel.includes("/")) {
    return incomingModel;
  }

  // Tier-based routing
  if (lower.includes("opus") && config.modelOpus) return config.modelOpus;
  if (lower.includes("sonnet") && config.modelSonnet) return config.modelSonnet;
  if (lower.includes("haiku") && config.modelHaiku) return config.modelHaiku;

  return config.model;
}

function resolveBaseUrl(config: ProxyConfig): string {
  switch (config.provider) {
    case "direct":
      return "https://api.anthropic.com";
    case "openrouter":
      return "https://openrouter.ai/api/v1";
    case "opencode-zen":
      return "https://opencode.ai/zen/v1";
    case "opencode-go":
      return "https://opencode.ai/zen/go/v1";
    case "openai":
      return config.openaiBaseUrl;
    case "local":
      return config.localLlmBaseUrl;
  }
}

function resolveApiKey(config: ProxyConfig): string {
  switch (config.provider) {
    case "direct":
      return config.anthropicApiKey;
    case "openrouter":
      return config.openrouterApiKey;
    case "opencode-zen":
    case "opencode-go":
      return config.opencodeApiKey;
    case "openai":
      return config.openaiApiKey;
    case "local":
      return ""; // No auth for local
  }
}

// --- Fallback Provider Aliases ---

/**
 * Parse a comma-separated FALLBACK_PROVIDERS string into an ordered list.
 * Returns empty array if unset or blank.
 */
function parseFallbackProviders(raw: string): string[] {
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

/**
 * Resolve a friendly provider name to a canonical provider type.
 * Known aliases:
 *   "nvidia"  → "openai"  (uses OPENAI_BASE_URL / OPENAI_API_KEY)
 *   "ollama"  → "local"   (uses LOCAL_LLM_BASE_URL / LOCAL_LLM_MODEL)
 * Everything else is returned as-is.
 */
type ProviderName = ProxyConfig["provider"];
function resolveProviderName(name: string): ProviderName {
  switch (name.toLowerCase()) {
    case "nvidia":
      return "openai";
    case "ollama":
      return "local";
    default:
      return name as ProviderName;
  }
}

/**
 * Try an ordered list of provider+model pairs and return the first success.
 * - Connection errors, timeouts, and 5xx are retryable → try next provider.
 * - 4xx responses ARE retryable for fallback chains → try next provider.
 * - Returns the last error response if all providers fail.
 */
async function tryProviders(
  handlers: Array<() => Promise<Response>>,
): Promise<Response> {
  let lastResponse: Response | null = null;

  for (const handler of handlers) {
    try {
      const resp = await handler();
      if (resp.status < 300) {
        // 2xx success — return immediately
        return resp;
      }
      // 4xx or 5xx — try next provider in the chain
      lastResponse = resp;
    } catch (err) {
      // Network errors, timeouts, DNS failures — retryable
      lastResponse = new Response(
        JSON.stringify({
          type: "error",
          error: {
            type: "api_error",
            message: `Provider unavailable: ${(err as Error).message || "unknown error"}`,
          },
        }),
        { status: 502, headers: { "Content-Type": "application/json" } },
      );
    }
  }

  // All providers failed — return the last error
  return lastResponse || new Response(
    JSON.stringify({ type: "error", error: { type: "api_error", message: "No providers available" } }),
    { status: 503, headers: { "Content-Type": "application/json" } },
  );
}

// --- Protocol Conversion ---

/**
 * Convert an Anthropic Messages request to an OpenAI Chat Completion request
 * for providers that use the OpenAI protocol (OpenAI, local LLMs, etc.).
 */
function toOpenAIChat(req: MessagesRequest): Record<string, unknown> {
  const messages = req.messages.map((msg) => {
    const content = typeof msg.content === "string"
      ? msg.content
      : msg.content.map((c) => {
          if (c.type === "text") {
            return { type: "text", text: (c as { text: string }).text };
          }
          if (c.type === "image") {
            const src = (c as { source: { type: string; media_type: string; data: string } }).source;
            return {
              type: "image_url",
              image_url: { url: `data:${src.media_type};${src.type},${src.data}` },
            };
          }
          return null;
        }).filter(Boolean);

    return { role: msg.role, content };
  });

  // Prepend system message if provided
  if (req.system) {
    const sysContent = typeof req.system === "string"
      ? req.system
      : req.system.map((s) => s.text).join("\n");

    messages.unshift({ role: "system", content: sysContent });
  }

  const body: Record<string, unknown> = {
    model: req.model,
    messages,
    max_tokens: req.max_tokens ?? 4096,
    stream: req.stream !== false,
    temperature: req.temperature ?? 0.7,
    stop: req.stop_sequences,
  };

  if (req.tools && req.tools.length > 0) {
    body.tools = req.tools.map((t) => ({
      type: "function",
      function: {
        name: t.name,
        description: t.description,
        parameters: t.input_schema,
      },
    }));
    body.tool_choice = req.tool_choice?.type === "any"
      ? "required"
      : req.tool_choice?.type === "tool"
        ? { type: "function", function: { name: req.tool_choice.name } }
        : "auto";
  }

  if (req.thinking?.type === "enabled") {
    (body as Record<string, unknown>).reasoning_effort = "high";
  }

  return body;
}

/**
 * Convert OpenAI Chat Completion chunk → Anthropic Messages SSE event.
 */
function* openAIToAnthropicSSE(
  chunk: Record<string, unknown>,
): Generator<string> {
  const choices = (chunk.choices || []) as Array<{
    delta?: { content?: string; role?: string; tool_calls?: Array<Record<string, unknown>> };
    finish_reason?: string | null;
    index: number;
  }>;

  for (const choice of choices) {
    const delta = choice.delta || {};

    if (delta.content) {
      yield `event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":${JSON.stringify(delta.content)}}}\n\n`;
    }

    if (delta.role === "assistant") {
      yield `event: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n`;
      yield `event: message_start\ndata: {"type":"message_start","message":{"role":"assistant","content":[]}}\n\n`;
    }

    if (delta.tool_calls) {
      for (const tc of delta.tool_calls) {
        const idx = tc.index as number;
        const fn = tc.function as Record<string, string> | undefined;
        if (fn?.name) {
          yield `event: content_block_start\ndata: {"type":"content_block_start","index":${idx},"content_block":{"type":"tool_use","id":"${fn.name}_${idx}","name":${JSON.stringify(fn.name)},"input":{}}}\n\n`;
        }
        if (fn?.arguments) {
          yield `event: content_block_delta\ndata: {"type":"content_block_delta","index":${idx},"delta":{"type":"input_json_delta","partial_json":${JSON.stringify(fn.arguments)}}}\n\n`;
        }
      }
    }

    if (choice.finish_reason) {
      const stopReason = choice.finish_reason === "tool_calls"
        ? "tool_use"
        : choice.finish_reason === "length"
          ? "max_tokens"
          : "end_turn";

      // Close any open content blocks
      yield `event: content_block_stop\ndata: {"type":"content_block_stop","index":${choice.index}}\n\n`;

      // Usage data (approximate from OpenAI response)
      const usage = (chunk.usage as Record<string, number>) || {};
      yield `event: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"${stopReason}","stop_sequence":null},"usage":{"output_tokens":${usage.completion_tokens || 0}}}\n\n`;
      yield `event: message_stop\ndata: {"type":"message_stop"}\n\n`;
    }
  }
}

// --- Provider Handlers ---

async function routeToAnthropicDirect(
  req: MessagesRequest,
  config: ProxyConfig,
): Promise<Response> {
  const baseUrl = resolveBaseUrl(config);
  const apiKey = resolveApiKey(config);

  if (!apiKey) {
    return new Response(
      JSON.stringify({
        type: "error",
        error: { type: "authentication_error", message: "ANTHROPIC_API_KEY not configured" },
      }),
      {
        status: 401,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  const body = { ...req, model: resolveModel(config, req.model) };

  const response = await fetch(`${baseUrl}/v1/messages`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
  });

  // Pass through upstream errors so the fallback chain can detect them
  return new Response(response.body, {
    status: response.status,
    headers: {
      "Content-Type": response.headers.get("Content-Type") || "application/json",
    },
  });
}

async function routeToOpenAI(
  req: MessagesRequest,
  config: ProxyConfig,
): Promise<Response> {
  const baseUrl = resolveBaseUrl(config);
  const apiKey = resolveApiKey(config);

  const openaiReq = toOpenAIChat({
    ...req,
    model: resolveModel(config, req.model),
  });

  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(apiKey ? { Authorization: `Bearer ${apiKey}` } : {}),
    },
    body: JSON.stringify(openaiReq),
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
  });

  // Propagate upstream errors so the fallback chain can retry
  if (!response.ok && response.status >= 400) {
    // 5xx is retryable; 4xx is not — return as-is for tryProviders to decide
    return new Response(await response.text(), {
      status: response.status,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (req.stream !== false) {
    // Convert OpenAI SSE stream to Anthropic SSE
    const reader = response.body?.getReader();
    if (!reader) {
      return new Response(
        JSON.stringify({ error: { message: "No response body" } }),
        { status: 502 },
      );
    }

    const decoder = new TextDecoder();
    const encoder = new TextEncoder();
    let buffer = "";

    const stream = new ReadableStream({
      async start(controller) {
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split("\n");
            buffer = lines.pop() || "";

            for (const line of lines) {
              if (line.startsWith("data: ")) {
                const data = line.slice(6);
                if (data === "[DONE]") {
                  controller.enqueue(
                    encoder.encode("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"),
                  );
                  continue;
                }
                try {
                  const chunk = JSON.parse(data);
                  for (const sse of openAIToAnthropicSSE(chunk)) {
                    controller.enqueue(encoder.encode(sse));
                  }
                } catch {
                  // Skip malformed chunks
                }
              }
            }
          }
        } finally {
          controller.close();
          reader.releaseLock();
        }
      },
    });

    return new Response(stream, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      },
    });
  }

  // Non-streaming: convert complete response
  const data = await response.json() as Record<string, unknown>;
  const choices = (data.choices || []) as Array<{
    message?: { content?: string; tool_calls?: Array<Record<string, unknown>> };
    finish_reason?: string;
  }>;
  const choice = choices[0]?.message;

  const anthropicResponse: Record<string, unknown> = {
    id: `msg_${Date.now()}`,
    type: "message",
    role: "assistant",
    content: [
      { type: "text", text: choice?.content || "" },
    ],
    model: req.model,
    stop_reason: choice?.finish_reason === "tool_calls" ? "tool_use" : "end_turn",
    usage: {
      input_tokens: (data.usage as Record<string, number> | undefined)?.prompt_tokens || 0,
      output_tokens: (data.usage as Record<string, number> | undefined)?.completion_tokens || 0,
    },
  };

  return new Response(JSON.stringify(anthropicResponse), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

async function routeToOpenRouter(
  req: MessagesRequest,
  config: ProxyConfig,
): Promise<Response> {
  // OpenRouter uses the same Messages API format as Anthropic
  const apiKey = resolveApiKey(config);
  if (!apiKey) {
    return new Response(
      JSON.stringify({
        error: { type: "authentication_error", message: "OPENROUTER_API_KEY not configured" },
      }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  // OpenRouter model routing: resolve tier to OpenRouter model paths
  const model = resolveModel(config, req.model);
  const openrouterModel = model.startsWith("openrouter/")
    ? model.slice("openrouter/".length)
    : model;

  const body = { ...req, model: openrouterModel };

  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      "HTTP-Referer": "https://github.com/marshaljlee/jxproxy",
      "X-Title": "jxproxy",
    },
    body: JSON.stringify(toOpenAIChat(body)),
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
  });

  if (!response.ok && response.status >= 400) {
    return new Response(await response.text(), {
      status: response.status,
      headers: { "Content-Type": "application/json" },
    });
  }

  return await openAIToAnthropicStream(response, req);
}

async function routeToLocal(
  req: MessagesRequest,
  config: ProxyConfig,
): Promise<Response> {
  const openaiReq = toOpenAIChat({
    ...req,
    model: config.localLlmModel,
  });

  const response = await fetch(`${config.localLlmBaseUrl}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(openaiReq),
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
  });

  if (!response.ok && response.status >= 400) {
    return new Response(await response.text(), {
      status: response.status,
      headers: { "Content-Type": "application/json" },
    });
  }

  return await openAIToAnthropicStream(response, req);
}

async function openAIToAnthropicStream(
  upstreamResponse: Response,
  _req: MessagesRequest,
): Promise<Response> {
  if (!upstreamResponse.body) {
    return new Response(
      JSON.stringify({ error: { message: "No upstream response body" } }),
      { status: 502 },
    );
  }

  const reader = upstreamResponse.body.getReader();
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";

  const stream = new ReadableStream({
    async start(controller) {
      let hasStarted = false;
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() || "";

          for (const line of lines) {
            if (line.startsWith("data: ")) {
              const data = line.slice(6);
              if (data === "[DONE]") {
                controller.enqueue(
                  encoder.encode('event: message_stop\ndata: {"type":"message_stop"}\n\n'),
                );
                continue;
              }
              try {
                const chunk = JSON.parse(data);
                for (const sse of openAIToAnthropicSSE(chunk)) {
                  if (!hasStarted && sse.includes("content_block_start")) {
                    hasStarted = true;
                  }
                  controller.enqueue(encoder.encode(sse));
                }
              } catch {
                // Skip parse errors
              }
            }
          }
        }

        if (!hasStarted) {
          // Not a streaming response — handle as non-streaming
          controller.enqueue(
            encoder.encode('event: message_stop\ndata: {"type":"message_stop"}\n\n'),
          );
        }
      } catch (err) {
        controller.error(err);
      } finally {
        controller.close();
        reader.releaseLock();
      }
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}

// --- Token Counting ---

async function handleTokenCount(body: MessagesRequest, config: ProxyConfig): Promise<Response> {
  // Local approximate token counting (no remote call)
  let totalChars = 0;

  for (const msg of body.messages) {
    if (typeof msg.content === "string") {
      totalChars += msg.content.length;
    } else {
      for (const block of msg.content) {
        if (block.type === "text") {
          totalChars += (block as { text?: string }).text?.length || 0;
        }
      }
    }
  }

  // Heuristic: ~4 chars per token
  const estimatedTokens = Math.ceil(totalChars / 4);

  return new Response(
    JSON.stringify({
      input_tokens: estimatedTokens,
      estimated: true,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
}

// --- Model Listing ---

function buildModelList(config: ProxyConfig): ModelInfo[] {
  const now = Math.floor(Date.now() / 1000);
  return [
    { id: "claude-opus-4-8-20250701", object: "model", created: now, owned_by: "jxproxy" },
    { id: "claude-sonnet-5-20251001", object: "model", created: now, owned_by: "jxproxy" },
    { id: "claude-haiku-4-5-20251001", object: "model", created: now, owned_by: "jxproxy" },
    { id: "claude-sonnet-5-20251001-bedrock", object: "model", created: now, owned_by: "jxproxy" },
    { id: "claude-opus-4-8-20250701-bedrock", object: "model", created: now, owned_by: "jxproxy" },
    { id: "claude-sonnet-4-20250514", object: "model", created: now, owned_by: "jxproxy" },
    { id: "claude-haiku-4-5-20251001-sonnet", object: "model", created: now, owned_by: "jxproxy" },
    { id: resolveModel(config, "opus"), object: "model", created: now, owned_by: "jxproxy" },
    { id: resolveModel(config, "sonnet"), object: "model", created: now, owned_by: "jxproxy" },
    { id: resolveModel(config, "haiku"), object: "model", created: now, owned_by: "jxproxy" },
  ];
}

// --- Server Implementation ---

function requireAuth(req: Request, config: ProxyConfig): Response | null {
  const token = config.authToken;
  if (!token) return null; // empty = no auth required

  const xApiKey = req.headers.get("x-api-key");
  const authHeader = req.headers.get("Authorization");
  const bearer = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;

  const provided = xApiKey || bearer;
  if (provided === token) return null;

  return new Response(
    JSON.stringify({
      type: "error",
      error: { type: "authentication_error", message: "Invalid or missing auth token" },
    }),
    { status: 401, headers: { "Content-Type": "application/json" } },
  );
}

function createServer(config: ProxyConfig) {
  const configMap = new Map<string, (req: MessagesRequest) => Promise<Response>>();

  configMap.set("direct", (req) => routeToAnthropicDirect(req, config));
  configMap.set("openrouter", (req) => routeToOpenRouter(req, config));
  configMap.set("opencode-zen", (req) => routeToOpenAI(req, config));
  configMap.set("opencode-go", (req) => routeToOpenAI(req, config));
  configMap.set("openai", (req) => routeToOpenAI(req, config));
  configMap.set("local", (req) => routeToLocal(req, config));

  // Build the ordered provider chain: [primary, ...fallbacks]
  const primaryProvider = resolveProviderName(config.provider);
  const primaryHandler = configMap.get(primaryProvider) || configMap.get("direct")!;

  // Fallback handlers: each gets its own provider config so resolveBaseUrl/resolveApiKey work correctly
  const fallbackHandlers = config.fallbackProviders
    .map((name) => {
      const provider = resolveProviderName(name);
      const handler = configMap.get(provider);
      if (!handler) return null;
      // Create a provider-specific config override for base URL & API key resolution
      const fbConfig: ProxyConfig = { ...config, provider };
      return (req: MessagesRequest) => {
        switch (provider) {
          case "openai":
            return routeToOpenAI(req, fbConfig);
          case "local":
            return routeToLocal(req, config); // uses config.localLlmBaseUrl directly
          default:
            return handler(req);
        }
      };
    })
    .filter((h): h is (req: MessagesRequest) => Promise<Response> => h != null);

  const providerChain = [primaryProvider, ...config.fallbackProviders.map(resolveProviderName)];

  return {
    config,
    routes: {
      async messages(req: Request): Promise<Response> {
        // HEAD / OPTIONS probes — answer locally
        if (req.method === "HEAD" || req.method === "OPTIONS") {
          return new Response(null, {
            status: 204,
            headers: { Allow: "POST, HEAD, OPTIONS" },
          });
        }

        const authErr = requireAuth(req, config);
        if (authErr) return authErr;

        let body: MessagesRequest;
        try {
          body = await req.json() as MessagesRequest;
        } catch {
          return new Response(
            JSON.stringify({ error: { type: "invalid_request_error", message: "Invalid JSON body" } }),
            { status: 400, headers: { "Content-Type": "application/json" } },
          );
        }

        // Build the ordered chain of handler calls
        const handlers: Array<() => Promise<Response>> = [
          // Primary provider
          () => primaryHandler(body),
          // Fallback providers
          ...fallbackHandlers.map((handler) => () => handler(body)),
        ];

        return tryProviders(handlers);
      },

      async countTokens(req: Request): Promise<Response> {
        if (req.method === "HEAD" || req.method === "OPTIONS") {
          return new Response(null, {
            status: 204,
            headers: { Allow: "POST, HEAD, OPTIONS" },
          });
        }
        const authErr = requireAuth(req, config);
        if (authErr) return authErr;
        const body = await req.json() as MessagesRequest;
        return handleTokenCount(body, config);
      },

      async listModels(_req: Request): Promise<Response> {
        const models = buildModelList(config);
        return new Response(
          JSON.stringify({ data: models }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      },

      async health(_req: Request): Promise<Response> {
        const chain = [
          config.provider,
          ...(config.fallbackProviders.length > 0 ? config.fallbackProviders : []),
        ];
        return new Response(
          JSON.stringify({
            status: "ok",
            provider: config.provider,
            fallbackProviders: config.fallbackProviders,
            providerChain: chain,
            version: "0.1.0",
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      },

      async stop(_req: Request): Promise<Response> {
        return new Response(
          JSON.stringify({ status: "stopped" }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      },
    },
  };
}

// --- Main Entry Point ---

if (import.meta.main) {
  const config = loadConfig();
  const server = createServer(config);
  const port = config.port;

  console.error(`\n  jxproxy proxy server`);
  console.error(`  ${"=".repeat(40)}`);
  console.error(`  Port:     ${port}`);
  console.error(`  Provider: ${config.provider}`);
  if (config.fallbackProviders.length > 0) {
    console.error(`  Fallback: ${config.fallbackProviders.join(", ")}`);
  }
  console.error(`  Model:    ${config.model}`);
  console.error(`  ${"=".repeat(40)}\n`);

  // Simple HTTP server — no external dependencies needed
  const httpServer = Bun.serve({
    port,
    hostname: "127.0.0.1",
    async fetch(req) {
      const url = new URL(req.url);
      const path = url.pathname;

      switch (path) {
        case "/v1/messages":
          return server.routes.messages(req);
        case "/v1/messages/count_tokens":
          return server.routes.countTokens(req);
        case "/v1/models":
          return server.routes.listModels(req);
        case "/health":
        case "/":
          return server.routes.health(req);
        case "/stop":
          return server.routes.stop(req);
        default:
          return new Response(null, { status: 204 });
      }
    },
  });

  console.error(`  ✓ Listening on http://127.0.0.1:${port}`);
}

export { createServer, type ProxyConfig, loadConfig };
