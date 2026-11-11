import { h, render as mount } from "preact";
import { transform } from "sucrase";
import { Boundary, kit } from "./kit";
import { post } from "./bridge";
import { styles } from "./styles";

/// Module names a document may import from. "react" is accepted because models reach for it
/// out of habit; it resolves to the same hooks.
const MODULES = new Set(["@any/kit", "react", "preact", "preact/hooks"]);

/// Capabilities documents must not have. The page's CSP is the real boundary; this just makes
/// mistakes fail loudly instead of hanging.
const BLOCKED_GLOBALS = ["fetch", "XMLHttpRequest", "WebSocket", "EventSource", "Worker", "SharedWorker", "open", "localStorage", "sessionStorage", "indexedDB"];

function lockDown() {
  for (const name of BLOCKED_GLOBALS) {
    try {
      Object.defineProperty(window, name, { value: undefined, configurable: false, writable: false });
    } catch {
      // Some properties can't be redefined; CSP still blocks the request.
    }
  }
}

class StageError extends Error {
  constructor(readonly stage: "compile" | "run", message: string) {
    super(message);
  }
}

function compile(source: string) {
  for (const match of source.matchAll(/\bfrom\s*["']([^"']+)["']/g)) {
    if (!MODULES.has(match[1])) throw new StageError("compile", `只能从 "@any/kit" 导入，发现 "${match[1]}"。`);
  }
  let code: string;
  try {
    code = transform(source, {
      transforms: ["typescript", "jsx", "imports"],
      jsxPragma: "h",
      jsxFragmentPragma: "Fragment",
      production: true,
    }).code;
  } catch (error) {
    throw new StageError("compile", error instanceof Error ? error.message : String(error));
  }

  const module = { exports: {} as Record<string, unknown> };
  const require = (name: string) => {
    if (!MODULES.has(name)) throw new StageError("run", `无法导入 "${name}"。`);
    return kit;
  };
  try {
    new Function("require", "exports", "module", "h", "Fragment", code)(require, module.exports, module, kit.h, kit.Fragment);
  } catch (error) {
    throw new StageError("run", error instanceof Error ? `${error.name}: ${error.message}` : String(error));
  }

  const component = module.exports.default;
  if (typeof component !== "function") throw new StageError("run", "缺少 export default 的组件函数。");
  const text = typeof module.exports.text === "string" ? module.exports.text : undefined;
  return { component: component as () => unknown, text };
}

let lastHeight = 0;

/// Includes the root's padding: the host extends the view by the same amount.
function measure(): number {
  return Math.ceil(document.getElementById("root")?.getBoundingClientRect().height ?? 0);
}

function reportHeight() {
  const height = measure();
  if (height === lastHeight) return;
  lastHeight = height;
  post({ t: "height", height });
}

function render(source: string) {
  const root = document.getElementById("root")!;
  try {
    const { component, text } = compile(source);
    // The first render is synchronous, so the layout can be measured right away; animation
    // frames don't run while the view is off screen.
    mount(h(Boundary, null, h(component as never, null)), root);
    lastHeight = measure();
    post({ t: "ready", text, height: lastHeight });
  } catch (error) {
    const stage = error instanceof StageError ? error.stage : "run";
    post({ t: "error", stage, message: error instanceof Error ? error.message : String(error) });
  }
}

function boot() {
  const style = document.createElement("style");
  style.textContent = styles;
  document.head.appendChild(style);

  new ResizeObserver(reportHeight).observe(document.getElementById("root")!);
  window.addEventListener("error", (event) => post({ t: "error", stage: "run", message: event.message }));
  window.addEventListener("unhandledrejection", (event) => post({ t: "error", stage: "run", message: String(event.reason) }));
  document.addEventListener("click", (event) => {
    const link = (event.target as Element | null)?.closest?.("a[href]");
    if (!link) return;
    event.preventDefault();
    post({ t: "link", href: link.getAttribute("href") ?? "" });
  }, true);
  document.addEventListener("selectionchange", () => {
    post({ t: "selection", text: window.getSelection()?.toString() ?? "" });
  });

  lockDown();
}

boot();
/// Plays the entrance animation; called by the host when the document comes on screen.
function reveal() {
  document.documentElement.classList.add("k-reveal");
}

(window as unknown as { ANYKit: unknown }).ANYKit = { render, reveal };

/// The host page carries the module as JSON in a non-executing script element.
const embedded = document.getElementById("any-source")?.textContent;
if (embedded) render(JSON.parse(embedded));
