import { h, Fragment, Component, toChildArray, type ComponentChildren } from "preact";
import { useState, useMemo, useEffect, useRef, useCallback, useReducer, useId } from "preact/hooks";
import { post } from "./bridge";

type Tone = "neutral" | "info" | "success" | "warning" | "danger";
type Gap = "xs" | "sm" | "md" | "lg";
type Inline = ComponentChildren;

// MARK: - Helpers

const INLINE = /(`[^`]+`)|(\*\*[^*]+\*\*)/g;
/// Models like to wrap plain words in backticks; only text that looks like code keeps the code style.
const CODE_LIKE = /[(){}\[\]<>=;:/\\_.$#@]|\w-\w*\d|^\S+\(\)$/;

/// Strings get `code` and **bold**; everything else is rendered as is.
function inline(children: Inline): ComponentChildren {
  return toChildArray(children).map((child) => {
    if (typeof child !== "string") return child;
    const parts: ComponentChildren[] = [];
    let last = 0;
    for (const match of child.matchAll(INLINE)) {
      const index = match.index ?? 0;
      if (index > last) parts.push(child.slice(last, index));
      const token = match[0];
      const content = token.startsWith("`") ? token.slice(1, -1) : token.slice(2, -2);
      if (!token.startsWith("`")) parts.push(<strong>{content}</strong>);
      else if (CODE_LIKE.test(content.replace(/\*\*/g, ""))) parts.push(<code>{content.replace(/\*\*/g, "")}</code>);
      else parts.push(<span class="k-mark">{inline(content)}</span>);
      last = index + token.length;
    }
    if (last < child.length) parts.push(child.slice(last));
    return parts;
  });
}

function plainText(children: Inline): string {
  return toChildArray(children)
    .map((child) => (typeof child === "string" || typeof child === "number" ? String(child) : ""))
    .join("")
    .replace(/\*\*|`/g, "");
}

/// Copies through the host and flags the element for a moment so it can show "已复制".
function useCopy(): [boolean, (text: string) => void] {
  const [copied, setCopied] = useState(false);
  const timer = useRef<number | undefined>(undefined);
  const copy = useCallback((text: string) => {
    // A drag that selects text ends in a click too; leave the selection for ⌘C.
    if (!text || !(window.getSelection()?.isCollapsed ?? true)) return;
    post({ t: "copy", text });
    setCopied(true);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setCopied(false), 1400);
  }, []);
  return [copied, copy];
}

const CopyHint = () => <span class="k-copy-hint" />;

function classes(...names: Array<string | false | null | undefined>): string {
  return names.filter(Boolean).join(" ");
}

function columnsStyle(count: number) {
  return { gridTemplateColumns: `repeat(${count}, minmax(0, 1fr))` };
}

/// Two columns when every entry is short, otherwise one.
function autoColumns(texts: string[], limit = 28): 1 | 2 {
  return texts.length > 1 && texts.every((t) => t.length <= limit) ? 2 : 1;
}

// MARK: - Layout

export function Doc({ children }: { children: ComponentChildren }) {
  return <div class="k-doc">{children}</div>;
}

export function Stack({ direction = "column", gap = "sm", align, wrap, children }: {
  direction?: "row" | "column"; gap?: Gap; align?: "start" | "center" | "end" | "baseline"; wrap?: boolean; children: ComponentChildren;
}) {
  const alignItems = align === "start" ? "flex-start" : align === "end" ? "flex-end" : align;
  return (
    <div class={classes("k-stack", direction === "row" && "row", wrap && "wrap", `gap-${gap}`)} style={alignItems ? { alignItems } : undefined}>
      {children}
    </div>
  );
}

export function Grid({ columns = 2, gap = "sm", children }: { columns?: 1 | 2 | 3 | 4; gap?: Gap; children: ComponentChildren }) {
  return <div class={`k-grid gap-${gap}`} style={columnsStyle(columns)}>{children}</div>;
}

export function Section({ heading, description, count, children }: { heading: string; description?: Inline; count?: number; children?: ComponentChildren }) {
  return (
    <section class="k-section">
      <div>
        <div class="k-section-header">
          <span class="k-section-heading">{heading}</span>
          {count != null && <span class="k-section-count">{count}</span>}
        </div>
        {description != null && <div class="k-section-description">{inline(description)}</div>}
      </div>
      {children}
    </section>
  );
}

export function Divider({ label }: { label?: string } = {}) {
  return label ? <div class="k-divider-label">{label}</div> : <hr class="k-divider" />;
}

export function Card({ title, children }: { title?: string; children: ComponentChildren }) {
  return (
    <div class="k-surface k-card">
      {title && <div class="k-card-title">{title}</div>}
      {children}
    </div>
  );
}

// MARK: - Text

/// The answer itself. Sized by length: a word or two is large, a paragraph reads at body size.
export function Translation({ children, size }: { children: Inline; size?: "md" | "lg" | "xl" }) {
  const [copied, copy] = useCopy();
  const text = plainText(children);
  const resolved = size ?? (text.length <= 14 ? "xl" : text.length <= 70 ? "lg" : "md");
  return (
    <div class={classes("k-translation", resolved, copied && "k-copied")} onClick={() => copy(text)}>
      {inline(children)}
      <CopyHint />
    </div>
  );
}

export function Text({ children, muted, size = "md" }: { children: Inline; muted?: boolean; size?: "sm" | "md" | "lg" }) {
  return <p class={classes("k-text", size, muted && "muted")}>{inline(children)}</p>;
}

export function Heading({ children }: { children: Inline }) {
  return <div class="k-heading">{inline(children)}</div>;
}

export function Note({ children }: { children: Inline }) {
  return <div class="k-note">{inline(children)}</div>;
}

const TONE_PATHS: Record<Tone, string> = {
  neutral: "M8 4.8v3.6M8 11h.01",
  info: "M8 7.2v3.8M8 5h.01",
  success: "M5.2 8.2l1.9 1.9 3.7-4.1",
  warning: "M8 4.6v3.8M8 11h.01",
  danger: "M5.6 5.6l4.8 4.8M10.4 5.6l-4.8 4.8",
};

function ToneIcon({ tone }: { tone: Tone }) {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d={TONE_PATHS[tone] ?? TONE_PATHS.neutral} />
    </svg>
  );
}

export function Callout({ tone = "info", title, children }: { tone?: Tone; title?: string; children?: Inline }) {
  return (
    <div class={`k-surface k-callout ${tone}`}>
      <span class="k-callout-icon"><ToneIcon tone={tone} /></span>
      <div class="k-callout-body">
        {title && <div class="k-callout-title">{title}</div>}
        {children != null && <div class={title ? "k-callout-text" : undefined}>{inline(children)}</div>}
      </div>
    </div>
  );
}

export function Quote({ children, cite }: { children: Inline; cite?: string }) {
  return (
    <blockquote class="k-quote">
      {inline(children)}
      {cite && <cite>— {cite}</cite>}
    </blockquote>
  );
}

export function List({ items, ordered }: { items: Inline[]; ordered?: boolean }) {
  const Tag = ordered ? "ol" : "ul";
  return <Tag class="k-list">{items.map((item, i) => <li key={i}>{inline(item)}</li>)}</Tag>;
}

export function Code({ children, language }: { children: string; language?: string }) {
  return <pre class="k-surface k-pre" data-language={language}>{children}</pre>;
}

export function Badge({ children, tone = "neutral" }: { children: Inline; tone?: Tone }) {
  return <span class={`k-badge ${tone}`}>{inline(children)}</span>;
}

export function Tags({ items }: { items: Array<string | { label: string; tone?: Tone }> }) {
  return (
    <div class="k-tags">
      {items.map((item, i) => typeof item === "string" ? <Badge key={i}>{item}</Badge> : <Badge key={i} tone={item.tone}>{item.label}</Badge>)}
    </div>
  );
}

export function Properties({ items }: { items: Array<{ label: string; value: Inline }> }) {
  return (
    <dl class="k-props">
      {items.map((item, i) => (
        <Fragment key={i}>
          <dt>{item.label}</dt>
          <dd>{inline(item.value)}</dd>
        </Fragment>
      ))}
    </dl>
  );
}

/// Label–value tiles, like the quick facts panel of a search answer.
export function Facts({ items, columns }: { items: Array<{ label: string; value: Inline }>; columns?: 2 | 3 | 4 }) {
  const count = columns ?? (items.length >= 3 && items.length % 3 === 0 ? 3 : 2);
  return (
    <div class="k-surface k-facts" style={columnsStyle(count)}>
      {items.map((item, i) => (
        <div key={i} class="k-fact">
          <span class="k-fact-label">{item.label}</span>
          <span class="k-fact-value">{inline(item.value)}</span>
        </div>
      ))}
    </div>
  );
}

export function Steps({ items }: { items: Array<{ title: Inline; body?: Inline; status?: "todo" | "doing" | "done" }> }) {
  return (
    <ol class="k-steps">
      {items.map((item, i) => (
        <li key={i} class={`k-step ${item.status ?? "todo"}`}>
          <span class="k-step-dot">{item.status === "done" ? "✓" : i + 1}</span>
          <div class="k-step-body">
            <div class="k-step-title">{inline(item.title)}</div>
            {item.body != null && <div class="k-step-text">{inline(item.body)}</div>}
          </div>
        </li>
      ))}
    </ol>
  );
}

export function Timeline({ items }: { items: Array<{ date?: string; title: Inline; body?: Inline }> }) {
  return (
    <ol class="k-timeline">
      {items.map((item, i) => (
        <li key={i} class="k-event">
          <span class="k-event-dot" />
          <div class="k-event-body">
            {item.date && <span class="k-event-date">{item.date}</span>}
            <span class="k-event-title">{inline(item.title)}</span>
            {item.body != null && <span class="k-event-text">{inline(item.body)}</span>}
          </div>
        </li>
      ))}
    </ol>
  );
}

// MARK: - Data

type Row = Record<string, unknown>;
interface Column { key: string; label?: string; align?: "left" | "right" | "center"; render?: (row: Row) => ComponentChildren }

function cell(value: unknown): ComponentChildren {
  if (value == null) return "";
  if (typeof value === "number") return value.toLocaleString();
  if (typeof value === "string") return inline(value);
  return value as ComponentChildren;
}

export function Table({ columns, rows, dense }: { columns?: Column[]; rows: Row[]; dense?: boolean }) {
  const cols: Column[] = columns ?? Object.keys(rows[0] ?? {}).map((key) => ({ key }));
  return (
    <div class="k-surface k-table-wrap">
      <table class={classes("k-table", dense && "dense")}>
        <thead>
          <tr>{cols.map((c) => <th key={c.key} style={{ textAlign: c.align ?? "left" }}>{c.label ?? c.key}</th>)}</tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i}>
              {cols.map((c) => <td key={c.key} style={{ textAlign: c.align ?? "left" }}>{c.render ? c.render(row) : cell(row[c.key])}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function Metrics({ items, columns }: { items: Array<{ label: string; value: string | number; hint?: string }>; columns?: 2 | 3 | 4 }) {
  const count = columns ?? Math.min(Math.max(items.length, 1), 4);
  return (
    <div class="k-metrics" style={columnsStyle(count)}>
      {items.map((item, i) => (
        <div key={i} class="k-surface k-metric">
          <span class="k-metric-label">{item.label}</span>
          <span class="k-metric-value">{typeof item.value === "number" ? item.value.toLocaleString() : item.value}</span>
          {item.hint && <span class="k-metric-hint">{item.hint}</span>}
        </div>
      ))}
    </div>
  );
}

export function Bars({ data, suffix = "" }: { data: Array<{ label: string; value: number }>; suffix?: string }) {
  const max = Math.max(...data.map((d) => d.value), 0) || 1;
  return (
    <div class="k-bars">
      {data.map((d, i) => (
        <Fragment key={i}>
          <span>{d.label}</span>
          <div class="k-bar-track"><div class="k-bar-fill" style={{ width: `${Math.max(0, d.value / max) * 100}%`, opacity: 1 - i * 0.12 }} /></div>
          <span class="k-bar-value">{d.value.toLocaleString()}{suffix}</span>
        </Fragment>
      ))}
    </div>
  );
}

/// A five-step scale such as formality or difficulty.
export function Meter({ label, value, low, high, caption }: { label: string; value: number; low?: string; high?: string; caption?: string }) {
  const level = Math.max(0, Math.min(5, Math.round(value)));
  return (
    <div class="k-meter">
      <div class="k-meter-head">
        <span class="k-meter-label">{label}</span>
        {caption && <span class="k-meter-value">{caption}</span>}
      </div>
      <div class="k-meter-track">{[0, 1, 2, 3, 4].map((i) => <span key={i} class={classes("k-meter-seg", i < level && "on")} />)}</div>
      {(low || high) && <div class="k-meter-ends"><span>{low}</span><span>{high}</span></div>}
    </div>
  );
}

// MARK: - Language

function Dots({ value }: { value: number }) {
  const level = Math.max(0, Math.min(5, Math.round(value)));
  return <span class="k-dots">{[0, 1, 2, 3, 4].map((i) => <i key={i} class={i < level ? "on" : undefined} />)}</span>;
}

/// A dictionary entry: the headword with its reading, tags and translation; senses and examples go inside.
export function WordCard({ word, reading, pos, tags, frequency, translation, children }: {
  word: string; reading?: string; pos?: string | string[]; tags?: string[]; frequency?: number; translation?: string; children?: ComponentChildren;
}) {
  const [copied, copy] = useCopy();
  const parts = pos == null ? [] : Array.isArray(pos) ? pos : [pos];
  const extra = tags?.filter((t) => !parts.includes(t));
  return (
    <div class="k-surface k-word">
      <div class="k-word-head">
        <div class="k-word-title">
          <span class="k-word-word">{word}</span>
          {reading && <span class="k-word-reading">{reading}</span>}
        </div>
        {(parts.length > 0 || (extra?.length ?? 0) > 0 || frequency != null) && (
          <div class="k-word-meta">
            {parts.map((p) => <Badge key={p}>{p}</Badge>)}
            {extra?.map((t) => <Badge key={t} tone="info">{t}</Badge>)}
            {frequency != null && <span class="k-word-level"><Dots value={frequency} />常用度</span>}
          </div>
        )}
      </div>
      {children && <div class="k-word-body">{children}</div>}
      {translation && (
        <div class={classes("k-word-translation", copied && "k-copied")} onClick={() => copy(translation)}>
          {translation}
          <CopyHint />
        </div>
      )}
    </div>
  );
}

export function Term({ word, reading, pos, children }: { word: string; reading?: string; pos?: string | string[]; children?: ComponentChildren }) {
  const tags = pos == null ? [] : Array.isArray(pos) ? pos : [pos];
  return (
    <div>
      <div class="k-term">
        <span class="k-term-word">{word}</span>
        {reading && <span class="k-term-reading">{reading}</span>}
        {tags.map((tag) => <Badge key={tag}>{tag}</Badge>)}
      </div>
      {children}
    </div>
  );
}

interface Example { source: Inline; target?: Inline; note?: Inline }

export function Examples({ items }: { items: Example[] }) {
  return (
    <div class="k-examples">
      {items.map((item, i) => (
        <div key={i} class="k-example">
          <span>{inline(item.source)}</span>
          {item.target != null && <span class="k-example-target">{inline(item.target)}</span>}
          {item.note != null && <span class="k-example-note">{inline(item.note)}</span>}
        </div>
      ))}
    </div>
  );
}

export function Senses({ items }: { items: Array<{ pos?: string; meaning: Inline; note?: Inline; examples?: Example[] }> }) {
  return (
    <ol class="k-senses">
      {items.map((item, i) => (
        <li key={i} class="k-sense">
          <div class="k-sense-body">
            <div>
              {item.pos && <><Badge>{item.pos}</Badge>{" "}</>}
              <span class="k-sense-meaning">{inline(item.meaning)}</span>
            </div>
            {item.note != null && <div class="k-sense-note">{inline(item.note)}</div>}
            {item.examples && item.examples.length > 0 && <Examples items={item.examples} />}
          </div>
        </li>
      ))}
    </ol>
  );
}

function Option({ text, note }: { text: string; note?: Inline }) {
  const [copied, copy] = useCopy();
  return (
    <div class={classes("k-surface k-option", copied && "k-copied")} onClick={() => copy(text)}>
      <div class="k-option-head">
        <span class="k-option-text">{text}</span>
        <CopyHint />
      </div>
      {note != null && <span class="k-option-note">{inline(note)}</span>}
    </div>
  );
}

/// Other ways to say it, as tiles that copy on click.
export function Alternatives({ items, columns }: { items: Array<{ text: string; note?: Inline }>; columns?: 1 | 2 | 3 }) {
  const count = columns ?? autoColumns(items.map((i) => i.text + plainText(i.note ?? "")), 30);
  return (
    <div class="k-options" style={columnsStyle(count)}>
      {items.map((item, i) => <Option key={i} text={item.text} note={item.note} />)}
    </div>
  );
}

/// Key terms of a longer text, as tiles: the original, its translation and a note.
export function Glossary({ items, columns }: { items: Array<{ term: string; translation: string; note?: Inline }>; columns?: 1 | 2 | 3 }) {
  const count = columns ?? autoColumns(items.map((i) => [i.term, i.translation, plainText(i.note ?? "")].reduce((a, b) => (b.length > a.length ? b : a))), 24);
  return (
    <div class="k-glossary" style={columnsStyle(count)}>
      {items.map((item, i) => (
        <div key={i} class="k-surface k-gloss">
          <span class="k-gloss-term">{item.term}</span>
          <span class="k-gloss-translation">{item.translation}</span>
          {item.note != null && <span class="k-gloss-note">{inline(item.note)}</span>}
        </div>
      ))}
    </div>
  );
}

/// Sentence-by-sentence bilingual view.
export function Parallel({ items }: { items: Array<{ source: Inline; target: Inline }> }) {
  return (
    <div class="k-surface k-parallel">
      {items.map((item, i) => (
        <div key={i} class="k-pair">
          <span class="k-pair-source">{inline(item.source)}</span>
          <span>{inline(item.target)}</span>
        </div>
      ))}
    </div>
  );
}

/// Word-by-word gloss: each piece with its reading above and meaning below.
export function Breakdown({ items }: { items: Array<{ text: string; reading?: string; gloss?: string }> }) {
  return (
    <div class="k-breakdown">
      {items.map((item, i) => (
        <div key={i} class="k-token">
          <span class="k-token-reading">{item.reading ?? "\u00a0"}</span>
          <span class="k-token-text">{item.text}</span>
          {item.gloss && <span class="k-token-gloss">{item.gloss}</span>}
        </div>
      ))}
    </div>
  );
}

// MARK: - Cards

/// A person, place, work or organization: a glyph, the name, a short summary and facts.
export function EntityCard({ title, subtitle, glyph, summary, facts, children }: {
  title: string; subtitle?: string; glyph?: string; summary?: Inline; facts?: Array<{ label: string; value: Inline }>; children?: ComponentChildren;
}) {
  return (
    <div class="k-surface k-entity">
      <div class="k-entity-head">
        <span class="k-entity-glyph">{glyph ?? title.slice(0, 1)}</span>
        <div>
          <div class="k-entity-title">{title}</div>
          {subtitle && <div class="k-entity-subtitle">{subtitle}</div>}
        </div>
      </div>
      {summary != null && <div class="k-entity-summary">{inline(summary)}</div>}
      {children}
      {facts && facts.length > 0 && (
        <div class="k-entity-facts">
          {facts.map((fact, i) => (
            <div key={i} class="k-fact-inline">
              <div class="k-fact-label">{fact.label}</div>
              <div class="k-fact-value">{inline(fact.value)}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/// Side-by-side options with their points and a verdict; mark the best with `recommended`.
export function Compare({ items }: { items: Array<{ title: string; subtitle?: Inline; badge?: string; points?: Inline[]; verdict?: Inline; recommended?: boolean }> }) {
  return (
    <div class="k-compare" style={columnsStyle(Math.min(Math.max(items.length, 1), 3))}>
      {items.map((item, i) => (
        <div key={i} class={classes("k-surface k-choice", item.recommended && "recommended")}>
          <div class="k-choice-head">
            <span class="k-choice-title">{item.title}{item.badge && <Badge tone={item.recommended ? "danger" : "neutral"}>{item.badge}</Badge>}</span>
            {item.subtitle != null && <span class="k-choice-subtitle">{inline(item.subtitle)}</span>}
          </div>
          {item.points && item.points.length > 0 && <ul class="k-choice-points">{item.points.map((p, j) => <li key={j}><span>{inline(p)}</span></li>)}</ul>}
          {item.verdict != null && <div class="k-choice-verdict">{inline(item.verdict)}</div>}
        </div>
      ))}
    </div>
  );
}

export function ProsCons({ pros, cons, prosTitle = "优点", consTitle = "注意" }: { pros: Inline[]; cons: Inline[]; prosTitle?: string; consTitle?: string }) {
  return (
    <div class="k-proscons">
      <div class="k-surface k-card pro"><div class="k-card-title">{prosTitle}</div><ul>{pros.map((p, i) => <li key={i}><span>{inline(p)}</span></li>)}</ul></div>
      <div class="k-surface k-card con"><div class="k-card-title">{consTitle}</div><ul>{cons.map((p, i) => <li key={i}><span>{inline(p)}</span></li>)}</ul></div>
    </div>
  );
}

/// Click to flip between the two sides: the card narrows to an edge, swaps faces and opens again.
export function Flashcard({ front, back, frontHint, backHint }: { front: Inline; back: Inline; frontHint?: string; backHint?: string }) {
  const [flipped, setFlipped] = useState(false);
  const [turning, setTurning] = useState(false);
  const flip = () => {
    if (turning) return;
    setTurning(true);
    window.setTimeout(() => {
      setFlipped((value) => !value);
      setTurning(false);
    }, 140);
  };
  return (
    <div class={classes("k-surface k-flashcard", turning && "turning")} onClick={flip}>
      <span class="k-flashcard-main">{inline(flipped ? back : front)}</span>
      <span class="k-flashcard-hint">{flipped ? backHint ?? "点击翻回" : frontHint ?? "点击翻面"}</span>
    </div>
  );
}

/// A one-question check with the explanation revealed after answering.
export function Quiz({ question, options, answer, explanation }: { question: Inline; options: string[]; answer: number; explanation?: Inline }) {
  const [picked, setPicked] = useState<number | null>(null);
  return (
    <div class="k-surface k-quiz">
      <div class="k-quiz-question">{inline(question)}</div>
      <div class="k-quiz-options">
        {options.map((option, i) => {
          const state = picked == null ? undefined : i === answer ? "correct" : i === picked ? "wrong" : undefined;
          return (
            <button key={i} type="button" class={classes("k-quiz-option", state)} disabled={picked != null} onClick={() => setPicked(i)}>
              <span class="k-quiz-mark">{state === "correct" ? "✓" : state === "wrong" ? "✕" : String.fromCharCode(65 + i)}</span>
              <span>{option}</span>
            </button>
          );
        })}
      </div>
      {picked != null && explanation != null && <div class="k-quiz-explanation">{inline(explanation)}</div>}
    </div>
  );
}

export function Disclosure({ title, open, children }: { title: string; open?: boolean; children: ComponentChildren }) {
  return (
    <details class="k-surface k-disclosure" open={open}>
      <summary>
        <svg width="10" height="10" viewBox="0 0 10 10" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 2l3 3-3 3" /></svg>
        {title}
      </summary>
      <div class="k-disclosure-body">{typeof children === "string" ? inline(children) : children}</div>
    </details>
  );
}

// MARK: - Controls

type Option<T extends string> = T | { value: T; label: string };

export function Segmented<T extends string>({ value, onChange, options }: { value: T; onChange: (value: T) => void; options: ReadonlyArray<Option<T>> }) {
  return (
    <div class="k-segmented" role="radiogroup">
      {options.map((option) => {
        const v = typeof option === "string" ? option : option.value;
        const label = typeof option === "string" ? option : option.label;
        return (
          <button key={v} type="button" role="radio" aria-checked={v === value} onClick={() => onChange(v)}>
            {label}
          </button>
        );
      })}
    </div>
  );
}

export function Tabs({ items }: { items: Array<{ label: string; content: ComponentChildren }> }) {
  const [index, setIndex] = useState(0);
  const labels = items.map((item) => item.label);
  return (
    <div class="k-tabs">
      <Segmented value={labels[index] ?? ""} onChange={(label) => setIndex(Math.max(0, labels.indexOf(label)))} options={labels} />
      <div key={index} class="k-tab-panel">{items[index]?.content}</div>
    </div>
  );
}

// MARK: - Errors

export class Boundary extends Component<{ children: ComponentChildren }, { error?: string }> {
  state: { error?: string } = {};

  componentDidCatch(error: unknown) {
    const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
    this.setState({ error: message });
    post({ t: "error", stage: "render", message });
  }

  render() {
    return this.state.error ? <div class="k-error">渲染失败：{this.state.error}</div> : this.props.children;
  }
}

export const kit = {
  h, Fragment, createElement: h,
  useState, useMemo, useEffect, useRef, useCallback, useReducer, useId,
  Doc, Stack, Grid, Section, Divider, Card,
  Translation, Text, Heading, Note, Callout, Quote, List, Code, Badge, Tags, Properties, Facts, Steps, Timeline,
  Table, Metrics, Bars, Meter,
  WordCard, Term, Senses, Examples, Alternatives, Glossary, Parallel, Breakdown,
  EntityCard, Compare, ProsCons, Flashcard, Quiz, Disclosure,
  Segmented, Tabs,
};
