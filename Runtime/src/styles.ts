/// Matches the app: black, white and gray only, the same type scale and spacing steps. Blocks sit
/// on light "surfaces" over the card's fill, like widgets in a chat answer.
export const styles = String.raw`
:root {
  color-scheme: light dark;
  --fg: rgba(0, 0, 0, 0.85);
  --fg2: rgba(0, 0, 0, 0.5);
  --fg3: rgba(0, 0, 0, 0.3);
  --fill: rgba(0, 0, 0, 0.035);
  --fill2: rgba(0, 0, 0, 0.06);
  --fill3: rgba(0, 0, 0, 0.1);
  --line: rgba(0, 0, 0, 0.07);
  --strong: rgba(0, 0, 0, 0.85);
  --inverse: #fff;
  --surface: rgba(255, 255, 255, 0.62);
  --surface-hover: rgba(255, 255, 255, 0.9);
  --surface-line: rgba(0, 0, 0, 0.06);
  --shadow: 0 0.5px 1.5px rgba(0, 0, 0, 0.05);
  --mono: ui-monospace, "SF Mono", Menlo, monospace;
  --ease: cubic-bezier(0.2, 0.8, 0.2, 1);
}
@media (prefers-color-scheme: dark) {
  :root {
    --fg: rgba(255, 255, 255, 0.86);
    --fg2: rgba(255, 255, 255, 0.55);
    --fg3: rgba(255, 255, 255, 0.32);
    --fill: rgba(255, 255, 255, 0.04);
    --fill2: rgba(255, 255, 255, 0.07);
    --fill3: rgba(255, 255, 255, 0.13);
    --line: rgba(255, 255, 255, 0.08);
    --strong: rgba(255, 255, 255, 0.88);
    --inverse: #000;
    --surface: rgba(255, 255, 255, 0.055);
    --surface-hover: rgba(255, 255, 255, 0.09);
    --surface-line: rgba(255, 255, 255, 0.07);
    --shadow: 0 0 0 0 transparent;
  }
}

* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
body {
  font: 13px/1.55 -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans", sans-serif;
  color: var(--fg);
  -webkit-font-smoothing: antialiased;
  overflow-wrap: anywhere;
  cursor: default;
}
/* Matches the host's bleed: the view extends this far past the card's text edges. */
#root { display: flow-root; padding: 4px 8px; }
p { margin: 0; }
code { font-family: var(--mono); font-size: 0.9em; background: var(--fill2); border-radius: 4px; padding: 0.5px 4px; }
strong { font-weight: 600; }
a { color: inherit; text-decoration: underline; text-decoration-color: var(--fg3); text-underline-offset: 2px; cursor: pointer; }
button { font: inherit; color: inherit; }

/* Entrance: blocks rise in one after another once the host reveals the document on screen.
   Until then everything is fully visible, since animations don't run while the view is hidden. */
@keyframes k-in { from { opacity: 0; transform: translateY(4px); } to { opacity: 1; transform: none; } }
.k-reveal .k-doc > * { animation: k-in 0.36s var(--ease) both; }
.k-reveal .k-doc > *:nth-child(2) { animation-delay: 0.04s; }
.k-reveal .k-doc > *:nth-child(3) { animation-delay: 0.08s; }
.k-reveal .k-doc > *:nth-child(4) { animation-delay: 0.12s; }
.k-reveal .k-doc > *:nth-child(5) { animation-delay: 0.16s; }
.k-reveal .k-doc > *:nth-child(n+6) { animation-delay: 0.2s; }
.k-reveal .k-bar-fill { animation: k-grow 0.6s var(--ease) both 0.15s; }
@media (prefers-reduced-motion: reduce) { .k-reveal .k-doc > *, .k-reveal .k-bar-fill { animation: none; } }

/* MARK: Layout */
.k-doc { display: flex; flex-direction: column; gap: 14px; }
.k-stack { display: flex; flex-direction: column; }
.k-stack.row { flex-direction: row; align-items: center; }
.k-stack.wrap { flex-wrap: wrap; }
.gap-xs { gap: 4px; } .gap-sm { gap: 8px; } .gap-md { gap: 12px; } .gap-lg { gap: 16px; }
.k-grid { display: grid; }
.k-section { display: flex; flex-direction: column; gap: 8px; }
.k-section-header { display: flex; align-items: baseline; gap: 6px; }
.k-section-heading { font-size: 12px; font-weight: 600; color: var(--fg); }
.k-section-count { font-size: 11px; color: var(--fg3); font-variant-numeric: tabular-nums; }
.k-section-description { color: var(--fg2); font-size: 12px; }
.k-divider { height: 1px; background: var(--line); border: 0; margin: 0; }
.k-divider-label { display: flex; align-items: center; gap: 8px; color: var(--fg3); font-size: 11px; }
.k-divider-label::before, .k-divider-label::after { content: ""; flex: 1; height: 1px; background: var(--line); }

.k-surface { background: var(--surface); border-radius: 12px; box-shadow: inset 0 0 0 0.5px var(--surface-line), var(--shadow); }
.k-card { padding: 12px 14px; display: flex; flex-direction: column; gap: 6px; }
.k-card-title { font-size: 12px; font-weight: 600; }

/* MARK: Text */
.k-heading { font-size: 13px; font-weight: 600; }
.k-text.muted { color: var(--fg2); }
.k-text.sm { font-size: 12px; }
.k-text.lg { font-size: 15px; }
.k-note { font-size: 11px; color: var(--fg3); }

.k-translation { position: relative; white-space: pre-wrap; border-radius: 10px; margin: -6px -8px; padding: 6px 8px; transition: background 0.15s; letter-spacing: -0.005em; }
.k-translation.xl { font-size: 22px; line-height: 1.3; font-weight: 600; letter-spacing: -0.015em; }
.k-translation.lg { font-size: 17px; line-height: 1.45; font-weight: 500; }
.k-translation.md { font-size: 15px; line-height: 1.55; }
.k-translation:hover { background: var(--fill2); }
.k-translation:active { background: var(--fill3); }

/* Copy feedback shared by everything clickable-to-copy. */
.k-mark { font-weight: 500; color: var(--fg); }
.k-copy-hint { font-size: 11px; color: var(--fg3); opacity: 0; transition: opacity 0.15s; white-space: nowrap; pointer-events: none; }
.k-copy-hint::after { content: "点击复制"; }
.k-copied .k-copy-hint { opacity: 1; color: var(--fg2); }
.k-copied .k-copy-hint::after { content: "✓ 已复制"; }
:hover > .k-copy-hint, :hover > * > .k-copy-hint { opacity: 1; }
.k-translation .k-copy-hint { position: absolute; right: 8px; bottom: 6px; }

.k-quote { margin: 0; padding: 2px 0 2px 12px; border-left: 2px solid var(--fill3); color: var(--fg2); }
.k-quote cite { display: block; font-style: normal; font-size: 11px; color: var(--fg3); margin-top: 4px; }
.k-list { margin: 0; padding-left: 18px; display: flex; flex-direction: column; gap: 3px; }
.k-list li::marker { color: var(--fg3); }
.k-pre { margin: 0; padding: 10px 14px; font-family: var(--mono); font-size: 12px; line-height: 1.6; white-space: pre; overflow-x: auto; }

.k-badge { display: inline-flex; align-items: center; height: 18px; padding: 0 7px; border-radius: 9px; font-size: 11px; font-weight: 500; background: var(--fill2); color: var(--fg2); white-space: nowrap; vertical-align: 1px; }
.k-badge.info { background: transparent; box-shadow: inset 0 0 0 1px var(--fill3); }
.k-badge.success { background: var(--fill3); color: var(--fg); }
.k-badge.warning { background: transparent; color: var(--fg); box-shadow: inset 0 0 0 1px var(--strong); }
.k-badge.danger { background: var(--strong); color: var(--inverse); }
.k-tags { display: flex; flex-wrap: wrap; gap: 6px; }

.k-callout { display: flex; gap: 10px; padding: 10px 14px; }
.k-callout-icon { flex: none; width: 20px; height: 20px; border-radius: 10px; display: grid; place-items: center; background: var(--fill2); color: var(--fg2); margin-top: 0.5px; }
.k-callout.warning .k-callout-icon, .k-callout.danger .k-callout-icon { background: var(--strong); color: var(--inverse); }
.k-callout-body { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.k-callout-title { font-weight: 600; }
.k-callout-text { color: var(--fg2); }

.k-props { display: grid; grid-template-columns: max-content 1fr; gap: 6px 16px; margin: 0; }
.k-props dt { color: var(--fg2); }
.k-props dd { margin: 0; }

.k-facts { display: grid; gap: 1px; overflow: hidden; }
.k-fact { padding: 8px 14px; display: flex; flex-direction: column; gap: 1px; box-shadow: 0 0 0 0.5px var(--surface-line); }
.k-fact-label { font-size: 11px; color: var(--fg2); }
.k-fact-value { font-weight: 500; }

/* MARK: Steps & timeline */
.k-steps, .k-timeline { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; }
.k-step, .k-event { position: relative; display: flex; gap: 10px; padding-bottom: 12px; }
.k-step:last-child, .k-event:last-child { padding-bottom: 0; }
.k-step:not(:last-child)::before { content: ""; position: absolute; left: 9.5px; top: 22px; bottom: 2px; width: 1px; background: var(--line); }
.k-step-dot { flex: none; width: 20px; height: 20px; border-radius: 10px; display: grid; place-items: center; font-size: 11px; font-weight: 600; background: var(--fill2); color: var(--fg2); font-variant-numeric: tabular-nums; }
.k-step.done .k-step-dot { background: var(--strong); color: var(--inverse); }
.k-step.doing .k-step-dot { background: var(--surface); box-shadow: inset 0 0 0 1.5px var(--strong); color: var(--fg); }
.k-step-body, .k-event-body { display: flex; flex-direction: column; gap: 1px; padding-top: 1px; min-width: 0; }
.k-step-title, .k-event-title { font-weight: 500; }
.k-step-text, .k-event-text { color: var(--fg2); font-size: 12px; }
.k-event:not(:last-child)::before { content: ""; position: absolute; left: 3.5px; top: 14px; bottom: 0; width: 1px; background: var(--line); }
.k-event-dot { flex: none; width: 8px; height: 8px; border-radius: 4px; background: var(--strong); margin-top: 6px; }
.k-event-date { font-size: 11px; color: var(--fg3); font-variant-numeric: tabular-nums; }

/* MARK: Data */
.k-table-wrap { overflow-x: auto; }
.k-table { border-collapse: collapse; width: 100%; font-size: 12px; }
.k-table th { text-align: left; font-weight: 500; color: var(--fg2); font-size: 11px; padding: 8px 14px 6px; }
.k-table td { padding: 7px 14px; border-top: 0.5px solid var(--line); vertical-align: top; }
.k-table td:first-child { font-weight: 500; }
.k-table.dense td { padding: 4px 14px; }

.k-metrics { display: grid; gap: 8px; }
.k-metric { padding: 10px 14px; display: flex; flex-direction: column; gap: 1px; }
.k-metric-label { color: var(--fg2); font-size: 11px; }
.k-metric-value { font-size: 20px; font-weight: 600; letter-spacing: -0.01em; font-variant-numeric: tabular-nums; }
.k-metric-hint { color: var(--fg3); font-size: 11px; }

.k-bars { display: grid; grid-template-columns: max-content 1fr max-content; gap: 8px 12px; align-items: center; font-size: 12px; }
.k-bar-track { height: 6px; border-radius: 3px; background: var(--fill2); overflow: hidden; }
.k-bar-fill { height: 100%; border-radius: 3px; background: var(--fg); transform-origin: left; }
@keyframes k-grow { from { transform: scaleX(0); } }
.k-bar-value { color: var(--fg2); font-variant-numeric: tabular-nums; text-align: right; }

.k-meter { display: flex; flex-direction: column; gap: 6px; }
.k-meter-head { display: flex; justify-content: space-between; font-size: 12px; }
.k-meter-label { font-weight: 500; }
.k-meter-value { color: var(--fg2); }
.k-meter-track { display: grid; grid-template-columns: repeat(5, 1fr); gap: 3px; }
.k-meter-seg { height: 4px; border-radius: 2px; background: var(--fill2); }
.k-meter-seg.on { background: var(--strong); }
.k-meter-ends { display: flex; justify-content: space-between; font-size: 11px; color: var(--fg3); }

/* MARK: Language */
.k-word { padding: 14px 16px; display: flex; flex-direction: column; gap: 10px; }
.k-word-head { display: flex; flex-direction: column; gap: 4px; }
.k-word-title { display: flex; align-items: baseline; flex-wrap: wrap; gap: 4px 10px; }
.k-word-word { font-size: 24px; font-weight: 600; letter-spacing: -0.02em; line-height: 1.2; }
.k-word-reading { font-family: var(--mono); font-size: 12px; color: var(--fg2); }
.k-word-meta { display: flex; align-items: center; flex-wrap: wrap; gap: 6px; }
.k-dots { display: inline-flex; gap: 2px; vertical-align: middle; }
.k-dots i { width: 5px; height: 5px; border-radius: 2.5px; background: var(--fill3); }
.k-dots i.on { background: var(--strong); }
.k-word-level { display: inline-flex; align-items: center; gap: 5px; font-size: 11px; color: var(--fg2); margin-left: 2px; }
.k-word-translation::before { content: "译"; font-size: 11px; font-weight: 600; color: var(--fg3); }
.k-word-translation { position: relative; display: flex; align-items: baseline; gap: 8px; font-size: 17px; font-weight: 500; padding: 8px 10px; margin: 0 -10px -6px; border-radius: 8px; border-top: 0.5px solid var(--line); transition: background 0.15s; }
.k-word-translation:hover { background: var(--fill); }
.k-word-translation .k-copy-hint { margin-left: auto; }
.k-word-body { display: flex; flex-direction: column; gap: 8px; }

.k-term { display: flex; align-items: baseline; flex-wrap: wrap; gap: 4px 8px; }
.k-term-word { font-size: 20px; font-weight: 600; letter-spacing: -0.01em; }
.k-term-reading { font-family: var(--mono); font-size: 12px; color: var(--fg2); }

.k-senses { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 10px; counter-reset: sense; }
.k-sense { display: flex; gap: 10px; counter-increment: sense; }
.k-sense::before { content: counter(sense); flex: none; width: 18px; height: 18px; border-radius: 9px; background: var(--fill2); color: var(--fg2); font-size: 10px; font-weight: 600; display: grid; place-items: center; margin-top: 1px; }
.k-sense-body { display: flex; flex-direction: column; gap: 4px; min-width: 0; }
.k-sense-meaning { font-weight: 500; }
.k-sense-note { color: var(--fg2); font-size: 12px; }

.k-examples { display: flex; flex-direction: column; gap: 6px; }
.k-example { padding: 2px 0 2px 10px; border-left: 2px solid var(--fill3); display: flex; flex-direction: column; gap: 1px; }
.k-example-target { color: var(--fg2); font-size: 12px; }
.k-example-note { color: var(--fg3); font-size: 11px; }

.k-options { display: grid; gap: 8px; }
.k-option { position: relative; padding: 9px 12px; display: flex; flex-direction: column; gap: 2px; transition: background 0.15s, transform 0.15s var(--ease); }
.k-option:hover { background: var(--surface-hover); }
.k-option:active { transform: scale(0.985); }
.k-option-head { display: flex; align-items: baseline; gap: 8px; }
.k-option-text { font-weight: 500; font-size: 14px; }
.k-option-head .k-copy-hint { position: absolute; right: 12px; bottom: 9px; }
.k-option-note { font-size: 12px; color: var(--fg2); }

.k-glossary { display: grid; gap: 8px; }
.k-gloss { padding: 9px 12px; display: flex; flex-direction: column; gap: 1px; }
.k-gloss-term { font-size: 11px; color: var(--fg2); }
.k-gloss-translation { font-weight: 500; font-size: 14px; }
.k-gloss-note { font-size: 11px; color: var(--fg3); }

.k-parallel { display: flex; flex-direction: column; }
.k-pair { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; padding: 9px 14px; transition: background 0.15s; }
.k-pair + .k-pair { border-top: 0.5px solid var(--line); }
.k-pair:hover { background: var(--fill); }
.k-pair:first-child { border-radius: 12px 12px 0 0; }
.k-pair:last-child { border-radius: 0 0 12px 12px; }
.k-pair:only-child { border-radius: 12px; }
.k-pair-source { color: var(--fg2); font-size: 12px; }

.k-breakdown { display: flex; flex-wrap: wrap; gap: 6px; }
.k-token { display: flex; flex-direction: column; align-items: center; gap: 1px; padding: 6px 10px; border-radius: 10px; background: var(--surface); box-shadow: inset 0 0 0 0.5px var(--surface-line); min-width: 40px; }
.k-token-reading { font-family: var(--mono); font-size: 10px; color: var(--fg3); }
.k-token-text { font-size: 15px; font-weight: 500; line-height: 1.3; }
.k-token-gloss { font-size: 11px; color: var(--fg2); }

/* MARK: Cards */
.k-entity { padding: 14px 16px; display: flex; flex-direction: column; gap: 10px; }
.k-entity-head { display: flex; gap: 12px; align-items: center; }
.k-entity-glyph { flex: none; width: 44px; height: 44px; border-radius: 12px; background: var(--fill2); display: grid; place-items: center; font-size: 22px; font-weight: 600; color: var(--fg2); }
.k-entity-title { font-size: 17px; font-weight: 600; letter-spacing: -0.01em; line-height: 1.3; }
.k-entity-subtitle { font-size: 12px; color: var(--fg2); }
.k-entity-summary { color: var(--fg); }
.k-fact-inline { display: flex; flex-direction: column; gap: 1px; }
.k-entity-facts { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px 16px; padding-top: 10px; border-top: 0.5px solid var(--line); }

.k-compare { display: grid; gap: 8px; }
.k-choice { padding: 12px 14px; display: flex; flex-direction: column; gap: 8px; }
.k-choice.recommended { box-shadow: inset 0 0 0 1px var(--strong), var(--shadow); }
.k-choice-head { display: flex; flex-direction: column; gap: 2px; }
.k-choice-title { font-size: 14px; font-weight: 600; display: flex; align-items: center; gap: 6px; }
.k-choice-subtitle { font-size: 12px; color: var(--fg2); }
.k-choice-points { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 4px; font-size: 12px; }
.k-choice-points li { display: flex; gap: 6px; }
.k-choice-points li::before { content: "–"; color: var(--fg3); }
.k-choice-verdict { font-size: 12px; color: var(--fg2); padding-top: 8px; border-top: 0.5px solid var(--line); }

.k-proscons { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.k-proscons ul { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 4px; font-size: 12px; }
.k-proscons li { display: flex; gap: 6px; }
.k-proscons .pro li::before { content: "+"; color: var(--fg); font-weight: 600; }
.k-proscons .con li::before { content: "−"; color: var(--fg2); font-weight: 600; }

.k-flashcard { cursor: pointer; padding: 18px 16px; min-height: 96px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; text-align: center; transition: transform 0.14s ease-in; }
.k-flashcard.turning { transform: scaleX(0); }
.k-flashcard:not(.turning) { transition: transform 0.22s var(--ease); }
.k-flashcard-main { font-size: 20px; font-weight: 600; letter-spacing: -0.01em; }
.k-flashcard-hint { font-size: 11px; color: var(--fg3); }

.k-quiz { padding: 12px 14px; display: flex; flex-direction: column; gap: 10px; }
.k-quiz-question { font-weight: 600; }
.k-quiz-options { display: flex; flex-direction: column; gap: 6px; }
.k-quiz-option { appearance: none; border: 0; text-align: left; display: flex; align-items: center; gap: 8px; padding: 7px 10px; border-radius: 8px; background: var(--fill); cursor: pointer; transition: background 0.15s; }
.k-quiz-option:hover:not(:disabled) { background: var(--fill2); }
.k-quiz-option:disabled { cursor: default; }
.k-quiz-mark { flex: none; width: 16px; height: 16px; border-radius: 8px; box-shadow: inset 0 0 0 1.5px var(--fill3); display: grid; place-items: center; font-size: 10px; font-weight: 700; }
.k-quiz-option.correct { background: var(--fill2); }
.k-quiz-option.correct .k-quiz-mark { background: var(--strong); color: var(--inverse); box-shadow: none; }
.k-quiz-option.wrong { color: var(--fg2); text-decoration: line-through; text-decoration-color: var(--fg3); }
.k-quiz-option.wrong .k-quiz-mark { box-shadow: inset 0 0 0 1.5px var(--fg2); color: var(--fg2); }
.k-quiz-explanation { font-size: 12px; color: var(--fg2); animation: k-in 0.3s var(--ease) both; }

.k-disclosure { padding: 0; }
.k-disclosure summary { list-style: none; display: flex; align-items: center; gap: 6px; padding: 9px 14px; font-weight: 500; cursor: pointer; border-radius: 12px; }
.k-disclosure summary::-webkit-details-marker { display: none; }
.k-disclosure summary:hover { background: var(--fill); }
.k-disclosure summary svg { color: var(--fg3); transition: transform 0.2s var(--ease); }
.k-disclosure[open] summary svg { transform: rotate(90deg); }
.k-disclosure-body { padding: 0 14px 12px 34px; color: var(--fg2); display: flex; flex-direction: column; gap: 6px; }

/* MARK: Controls */
.k-segmented { display: inline-flex; align-self: flex-start; padding: 2px; border-radius: 8px; background: var(--fill2); gap: 2px; }
.k-segmented button { appearance: none; border: 0; background: transparent; font-size: 12px; color: var(--fg2); padding: 3px 12px; border-radius: 6px; cursor: default; transition: background 0.15s, color 0.15s; }
.k-segmented button[aria-checked="true"] { background: var(--inverse); color: var(--fg); box-shadow: 0 0.5px 1.5px rgba(0, 0, 0, 0.16); }
@media (prefers-color-scheme: dark) { .k-segmented button[aria-checked="true"] { background: var(--fill3); } }
.k-tabs { display: flex; flex-direction: column; gap: 10px; }
.k-tab-panel { animation: k-in 0.25s var(--ease) both; }

.k-error { color: var(--fg2); font-size: 12px; background: var(--fill); border-radius: 8px; padding: 8px 12px; }
`;
