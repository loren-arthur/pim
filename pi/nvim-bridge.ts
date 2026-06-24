import net from "node:net";
import { Type } from "typebox";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

let nextId = 1;

function bridgePort(): number {
  const raw = process.env.PIM_NVIM_BRIDGE_PORT;
  const port = raw ? Number(raw) : NaN;
  if (!Number.isInteger(port) || port <= 0) {
    throw new Error("PIM_NVIM_BRIDGE_PORT is not set; start pi through pim.nvim");
  }
  return port;
}

function bridgeToken(): string {
  const token = process.env.PIM_NVIM_BRIDGE_TOKEN;
  if (!token) throw new Error("PIM_NVIM_BRIDGE_TOKEN is not set; start pi through pim.nvim");
  return token;
}

function callBridge(method: string, params: unknown, signal?: AbortSignal): Promise<unknown> {
  const id = `pim-${nextId++}`;
  const payload = JSON.stringify({ id, token: bridgeToken(), method, params }) + "\n";

  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host: "127.0.0.1", port: bridgePort() });
    let buffer = "";
    let settled = false;

    const finish = (fn: () => void) => {
      if (settled) return;
      settled = true;
      signal?.removeEventListener("abort", onAbort);
      socket.destroy();
      fn();
    };

    const onAbort = () => finish(() => reject(new Error("cancelled")));
    signal?.addEventListener("abort", onAbort, { once: true });

    socket.on("connect", () => socket.write(payload));
    socket.on("error", (error) => finish(() => reject(error)));
    socket.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      const newline = buffer.indexOf("\n");
      if (newline === -1) return;
      const line = buffer.slice(0, newline).replace(/\r$/, "");
      try {
        const response = JSON.parse(line) as { ok: boolean; result?: unknown; error?: string };
        if (response.ok) finish(() => resolve(response.result));
        else finish(() => reject(new Error(response.error || "bridge request failed")));
      } catch (error) {
        finish(() => reject(error));
      }
    });
    socket.on("end", () => {
      if (!settled) finish(() => reject(new Error("bridge closed before response")));
    });
  });
}

function textResult(label: string, result: unknown) {
  return {
    content: [{ type: "text" as const, text: `${label}: ${JSON.stringify(result, null, 2)}` }],
    details: result,
  };
}

export default function pimNvimBridge(pi: ExtensionAPI) {
  pi.registerTool({
    name: "nvim_open_file",
    label: "Open File in Neovim",
    description: "Open a file in the user's Neovim session and optionally jump to a line/column.",
    promptSnippet: "Open files in the user's Neovim session.",
    promptGuidelines: [
      "Use nvim_open_file when the user asks to navigate to or inspect a specific file in Neovim.",
    ],
    parameters: Type.Object({
      path: Type.String({ description: "File path to open" }),
      line: Type.Optional(Type.Number({ description: "1-based line number" })),
      col: Type.Optional(Type.Number({ description: "1-based column number" })),
      mode: Type.Optional(Type.Union([
        Type.Literal("edit"),
        Type.Literal("split"),
        Type.Literal("vsplit"),
        Type.Literal("tab"),
      ], { description: "How to open the file" })),
    }),
    async execute(_toolCallId, params, signal) {
      const result = await callBridge("nvim_open_file", params, signal);
      return textResult("Opened file in Neovim", result);
    },
  });

  pi.registerTool({
    name: "nvim_highlight_range",
    label: "Highlight Range in Neovim",
    description: "Highlight a line range in the user's Neovim session, opening the file if needed.",
    promptSnippet: "Highlight relevant file ranges in Neovim.",
    promptGuidelines: [
      "Use nvim_highlight_range when explaining code and you want to visually point the user at relevant lines.",
    ],
    parameters: Type.Object({
      path: Type.Optional(Type.String({ description: "File path. Defaults to current buffer if omitted." })),
      startLine: Type.Number({ description: "1-based start line" }),
      endLine: Type.Optional(Type.Number({ description: "1-based end line" })),
      hlGroup: Type.Optional(Type.String({ description: "Neovim highlight group, defaults to PimHighlight" })),
      label: Type.Optional(Type.String({ description: "Virtual text label to show on the highlighted range, defaults to pi" })),
      labelHlGroup: Type.Optional(Type.String({ description: "Highlight group for the virtual text label, defaults to PimMuted" })),
      labelPosition: Type.Optional(Type.Union([
        Type.Literal("eol"),
        Type.Literal("right_align"),
        Type.Literal("overlay"),
        Type.Literal("inline"),
      ], { description: "Where to render the virtual text label" })),
      virtualText: Type.Optional(Type.Boolean({ description: "Whether to show the virtual text label" })),
      clearExisting: Type.Optional(Type.Boolean({ description: "Whether to clear existing pim highlights in the target buffer before adding this one" })),
      openMode: Type.Optional(Type.Union([
        Type.Literal("edit"),
        Type.Literal("split"),
        Type.Literal("vsplit"),
        Type.Literal("tab"),
      ])),
    }),
    async execute(_toolCallId, params, signal) {
      const result = await callBridge("nvim_highlight_range", params, signal);
      return textResult("Highlighted range in Neovim", result);
    },
  });

  pi.registerTool({
    name: "nvim_clear_highlights",
    label: "Clear Neovim Highlights",
    description: "Clear highlights created by pim in Neovim.",
    parameters: Type.Object({
      path: Type.Optional(Type.String({ description: "Optional file path to clear only one buffer" })),
    }),
    async execute(_toolCallId, params, signal) {
      const result = await callBridge("nvim_clear_highlights", params, signal);
      return textResult("Cleared Neovim highlights", result);
    },
  });

  pi.registerTool({
    name: "nvim_open_terminal",
    label: "Open Terminal in Neovim",
    description: "Open a terminal split/tab in the user's Neovim session.",
    promptSnippet: "Open terminal panes in Neovim when useful for user-visible commands.",
    promptGuidelines: [
      "Use nvim_open_terminal only when the user wants a visible interactive terminal in Neovim; use bash for ordinary non-interactive shell commands.",
    ],
    parameters: Type.Object({
      cmd: Type.Optional(Type.String({ description: "Command to run, defaults to shell" })),
      cwd: Type.Optional(Type.String({ description: "Working directory for the terminal" })),
      mode: Type.Optional(Type.Union([
        Type.Literal("split"),
        Type.Literal("vsplit"),
        Type.Literal("tab"),
      ])),
    }),
    async execute(_toolCallId, params, signal) {
      const result = await callBridge("nvim_open_terminal", params, signal);
      return textResult("Opened terminal in Neovim", result);
    },
  });

  pi.registerTool({
    name: "nvim_get_current_context",
    label: "Get Current Neovim Context",
    description: "Get the current Neovim cwd, file, cursor, filetype, and diagnostics.",
    promptSnippet: "Inspect the user's current Neovim file/cursor/diagnostics context.",
    promptGuidelines: [
      "Use nvim_get_current_context when the user's request depends on what they are viewing in Neovim and they did not provide an explicit selection.",
    ],
    parameters: Type.Object({}),
    async execute(_toolCallId, params, signal) {
      const result = await callBridge("nvim_get_current_context", params, signal);
      return textResult("Current Neovim context", result);
    },
  });
}
