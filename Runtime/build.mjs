// Bundles the document runtime into the app's resources: one self-contained script plus the
// component reference that's sent to the model.
import { build } from "esbuild";
import { copyFileSync, mkdirSync } from "node:fs";

const outdir = new URL("../ANY/Resources/DocumentRuntime/", import.meta.url).pathname;
mkdirSync(outdir, { recursive: true });

await build({
  entryPoints: ["src/runtime.tsx"],
  outfile: `${outdir}runtime.js`,
  bundle: true,
  minify: true,
  format: "iife",
  target: "safari18",
  platform: "browser",
  jsxFactory: "h",
  jsxFragment: "Fragment",
  legalComments: "none",
  define: { "process.env.NODE_ENV": '"production"' },
  logLevel: "info",
});

copyFileSync("kit-reference.md", `${outdir}kit-reference.md`);
