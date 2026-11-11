export type FrameMessage =
  | { t: "ready"; text?: string; height: number }
  | { t: "height"; height: number }
  | { t: "error"; stage: "compile" | "run" | "render"; message: string }
  | { t: "copy"; text: string }
  | { t: "link"; href: string };

declare global {
  interface Window {
    webkit?: { messageHandlers?: { any?: { postMessage(message: unknown): void } } };
  }
}

export function post(message: FrameMessage) {
  window.webkit?.messageHandlers?.any?.postMessage(message);
}
