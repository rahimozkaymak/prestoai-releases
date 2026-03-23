# Phase 1: Streaming Markdown Rendering in WKWebView Overlay - Research

**Researched:** 2026-03-15
**Domain:** Real-time streaming markdown rendering, syntax highlighting, WKWebView inline HTML
**Confidence:** HIGH

## Summary

The current OverlayManager-3.swift uses a naive `innerHTML +=` approach for streaming text chunks from the Claude API via SSE. This is O(n^2) because each chunk triggers the browser to re-parse and re-render the entire accumulated HTML. The response is raw markdown text (headings, bold, code blocks, LaTeX) but is currently displayed as escaped plaintext with `<br>` tags.

The recommended approach uses a **two-strategy hybrid**: (1) `streaming-markdown` (smd) library for true incremental DOM rendering during active streaming (O(n) — only appends new DOM nodes, never re-renders existing content), then (2) a **finalization pass** with `marked.js` + `marked-highlight` + `highlight.js` after the stream completes to produce polished output with full syntax highlighting and correct rendering of edge cases. This avoids the complexity of trying to do syntax highlighting during streaming while still providing a responsive, flicker-free experience.

**Primary recommendation:** Use `streaming-markdown` (3kB gzipped) for live streaming with incremental DOM append, then re-render the complete markdown with `marked.js` + `highlight.js` on stream completion. All libraries available via CDN with no build step required.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| R1.1 | Markdown rendering (headings, bold, italic, lists, links) | marked.js handles all standard markdown; streaming-markdown supports headings, bold, italic, lists, links during streaming |
| R1.2 | Code syntax highlighting with language detection | highlight.js with auto-detection on finalization; streaming-markdown renders code blocks as `<code>` elements during streaming |
| R1.3 | Typographic hierarchy (heading/body/code sizes) | CSS styling on rendered HTML elements (h1-h6, p, pre/code) — standard approach |
| R1.5 | Streaming performance — replace O(n^2) innerHTML | streaming-markdown uses incremental DOM append — O(n), never modifies existing nodes |
| R1.6 | Clickable links in responses | marked.js renders `[text](url)` as `<a>` tags; add target="_blank" via renderer override |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| streaming-markdown (smd) | latest (CDN) | Incremental DOM rendering during streaming | Only 3kB gzipped, purpose-built for ChatGPT-like streaming, O(n) append-only DOM updates, recommended by Chrome DevRel |
| marked.js | 15.x (CDN UMD) | Full markdown parsing on stream completion | Most popular markdown parser (34k+ GitHub stars), fast, extensible, CDN/UMD build available |
| marked-highlight | latest (CDN UMD) | Bridge between marked and highlight.js | Official marked extension, CDN UMD build available |
| highlight.js | 11.11.x (CDN) | Code syntax highlighting | Auto language detection, 180+ languages, zero dependencies, CDN with theme CSS |
| MathJax | 3.x (CDN) | LaTeX rendering | Already in use — no change needed |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DOMPurify | 3.x (CDN) | HTML sanitization | Sanitize marked.js output before innerHTML assignment on finalization |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| streaming-markdown | marked.js re-parse on each chunk | O(n^2) re-parsing; simpler but slow for long responses |
| streaming-markdown | incremark | Newer, npm-only (no CDN UMD build found), React/Vue focused |
| highlight.js | Prism.js | Prism is lighter core but has NO auto language detection — requires explicit lang specification. highlight.js auto-detects, which matters since Claude sometimes omits language in fenced code |
| highlight.js | shiki | shiki requires WASM/npm — not suitable for inline CDN embedding |
| marked.js | markdown-it | markdown-it is slightly more extensible but marked has simpler CDN UMD setup and marked-highlight integration is more straightforward |

**CDN URLs:**
```html
<!-- streaming-markdown (3kB gzipped) -->
<script src="https://cdn.jsdelivr.net/npm/streaming-markdown/smd.min.js"></script>

<!-- marked.js UMD -->
<script src="https://cdn.jsdelivr.net/npm/marked/lib/marked.umd.js"></script>

<!-- marked-highlight UMD -->
<script src="https://cdn.jsdelivr.net/npm/marked-highlight/lib/index.umd.js"></script>

<!-- highlight.js core + common languages + theme -->
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github-dark.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js"></script>

<!-- MathJax (already present) -->
<script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js" async></script>

<!-- DOMPurify for sanitization -->
<script src="https://cdn.jsdelivr.net/npm/dompurify@3/dist/purify.min.js"></script>
```

## Architecture Patterns

### Two-Phase Rendering Strategy

**Phase A — Streaming (while chunks arrive):**
```
SSE chunk → Swift appendChunk() → JS parser_write(parser, chunk)
                                      ↓
                            streaming-markdown appends
                            new DOM nodes incrementally
                            (no re-render of existing content)
```

**Phase B — Finalization (on stream complete):**
```
Stream ends → Swift signalStreamEnd() → JS finalize()
                                            ↓
                                     1. Get accumulated raw markdown text
                                     2. Parse with marked.js + highlight.js
                                     3. Sanitize with DOMPurify
                                     4. Replace container innerHTML once
                                     5. Run MathJax.typesetPromise()
```

### Pattern 1: Accumulate Raw Text Alongside Streaming DOM
**What:** Keep a JavaScript string buffer of all raw markdown chunks even while streaming-markdown renders them live. On finalization, use this buffer for the marked.js pass.
**When to use:** Always — the raw text is needed for the finalization re-render.
**Example:**
```javascript
let rawMarkdown = '';
let smdParser = null;

function initStreaming(containerEl) {
    rawMarkdown = '';
    const renderer = smd.default_renderer(containerEl);
    smdParser = smd.parser(renderer);
}

function appendChunk(text) {
    rawMarkdown += text;
    smd.parser_write(smdParser, text);
}

function finalize() {
    smd.parser_end(smdParser);

    // Now re-render with full formatting
    const markedInstance = new marked.Marked(
        markedHighlight.markedHighlight({
            emptyLangClass: 'hljs',
            langPrefix: 'hljs language-',
            highlight(code, lang) {
                const language = hljs.getLanguage(lang) ? lang : 'plaintext';
                return hljs.highlight(code, { language }).value;
            }
        })
    );

    const html = DOMPurify.sanitize(markedInstance.parse(rawMarkdown));
    document.querySelector('.content').innerHTML = html;

    // Re-run MathJax on the finalized content
    if (window.MathJax && MathJax.typesetPromise) {
        MathJax.typesetPromise([document.querySelector('.content')]).catch(() => {});
    }
}
```

### Pattern 2: Swift-Side Integration
**What:** Three JS functions called from Swift: `initStreaming()`, `appendChunk(text)`, `finalize()`.
**Example (Swift side):**
```swift
func showStreaming() {
    // Load responseHTML with all CDN scripts, then:
    webView?.evaluateJavaScript("initStreaming(document.querySelector('.content'))")
}

func appendChunk(_ text: String) {
    let escaped = escapeForJS(text)
    webView?.evaluateJavaScript("appendChunk(`\(escaped)`)")
}

func signalStreamEnd() {
    webView?.evaluateJavaScript("finalize()")
}
```

### Pattern 3: Scroll-to-Bottom During Streaming
**What:** Auto-scroll the content area as new content appears, but stop if user has scrolled up.
**Example:**
```javascript
let userScrolledUp = false;
const contentArea = document.querySelector('.content-area');

contentArea.addEventListener('scroll', () => {
    const atBottom = contentArea.scrollHeight - contentArea.scrollTop - contentArea.clientHeight < 30;
    userScrolledUp = !atBottom;
});

// Call after each chunk append
function autoScroll() {
    if (!userScrolledUp) {
        contentArea.scrollTop = contentArea.scrollHeight;
    }
}
```

### Anti-Patterns to Avoid
- **innerHTML += on each chunk:** O(n^2) — the exact current bug. Browser re-parses entire HTML string on each assignment.
- **Running marked.parse() on every chunk:** Still O(n^2) in parsing cost, even though output is better formatted. Save full parse for finalization only.
- **Running MathJax.typesetPromise() on every chunk:** MathJax is expensive. Only run on finalization, not during streaming.
- **Running highlight.js on every chunk:** Same issue — syntax highlighting is expensive. Defer to finalization.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Streaming markdown to DOM | Custom token parser that appends DOM nodes | streaming-markdown (smd) | Handles partial tokens, nested structures, edge cases around incomplete bold/code/list markers mid-stream |
| Markdown to HTML | Regex-based markdown converter | marked.js | Markdown spec is deceptively complex — tables, nested lists, link references, autolinks, escapes |
| Code syntax highlighting | Regex-based highlighter | highlight.js | 180+ languages, handles edge cases like template literals, regex in JS, multiline strings |
| HTML sanitization | Allowlist-based string replace | DOMPurify | XSS prevention is critical — LLM output could contain injected HTML/JS |
| LaTeX rendering | Custom math renderer | MathJax (already in use) | TeX is enormously complex |

**Key insight:** Every one of these problems has deceptive depth. A regex markdown parser handles 80% of cases but fails catastrophically on nested structures, escaped characters, and edge cases. Use proven libraries.

## Common Pitfalls

### Pitfall 1: MathJax and Marked.js Dollar Sign Conflict
**What goes wrong:** marked.js may consume `$...$` as text before MathJax can process it as inline math. Or marked.js may convert `_subscript_` into `<em>subscript</em>`.
**Why it happens:** Both markdown and LaTeX use `$` and `_` as special characters.
**How to avoid:** Process order matters. Let marked.js render first, then run MathJax on the output HTML. Configure marked.js to NOT escape content inside `$...$` delimiters by adding a custom tokenizer extension that preserves math delimiters as raw HTML. Alternatively, use a pre-processing step to replace `$...$` with placeholder tokens before marked.js, then restore them after.
**Warning signs:** Math expressions showing as literal text, or subscripts turning into italics.

### Pitfall 2: CDN Loading Race Conditions
**What goes wrong:** JS calls streaming-markdown or marked before the CDN scripts have loaded.
**Why it happens:** WKWebView loads the HTML, Swift sends chunks immediately, but async CDN scripts may not be ready.
**How to avoid:** Use a script load callback or `onload` event to set a `ready` flag. Queue chunks in Swift until `isPageReady` (already implemented) AND JS signals libraries are loaded. Alternatively, inline the critical libraries (smd is only 3kB).
**Warning signs:** "smd is not defined" or "marked is not defined" errors in JS console.

### Pitfall 3: Finalization Flash/Flicker
**What goes wrong:** When replacing streaming content with finalized marked.js output, there's a visible flash as the DOM is replaced.
**Why it happens:** innerHTML replacement destroys and recreates all DOM nodes.
**How to avoid:** Use a crossfade: render finalized content into a hidden sibling element, then swap with a CSS transition. Or accept the brief re-layout since it happens once at stream end (usually acceptable).
**Warning signs:** User sees content disappear and reappear when stream ends.

### Pitfall 4: highlight.js CDN Bundle Size
**What goes wrong:** The default highlight.js CDN bundle includes only ~40 common languages. If Claude outputs an uncommon language, it falls back to plaintext.
**Why it happens:** CDN "common" bundle vs "all languages" bundle.
**How to avoid:** Use the common bundle (covers Python, JS, TS, Java, C/C++, Swift, Go, Rust, SQL, HTML, CSS, Bash, JSON, etc.). This covers 95%+ of likely Claude output. If needed, load additional languages on demand.
**Warning signs:** Code blocks for uncommon languages not highlighted.

### Pitfall 5: WKWebView evaluateJavaScript Escaping
**What goes wrong:** Raw markdown text containing backticks, dollar signs, or backslashes breaks the JS template literal in `evaluateJavaScript`.
**Why it happens:** Swift string interpolation into JS template literals without proper escaping.
**How to avoid:** The current escaping in `appendChunkDirect` handles `\`, backtick, `$`, `\n`, `\r`. This is correct and should be preserved.
**Warning signs:** JS errors on chunks containing code blocks or LaTeX.

## Code Examples

### Complete responseHTML Template (Verified Pattern)
```javascript
// CDN script loading with ready callback
let libsReady = false;
let pendingChunks = [];

function onLibsReady() {
    libsReady = true;
    if (pendingChunks.length > 0) {
        initStreaming(document.querySelector('.content'));
        pendingChunks.forEach(c => appendChunk(c));
        pendingChunks = [];
    }
}

// streaming-markdown setup
let rawMarkdown = '';
let smdParser = null;

function initStreaming(el) {
    rawMarkdown = '';
    el.innerHTML = '';
    const renderer = smd.default_renderer(el);
    smdParser = smd.parser(renderer);
}

function appendChunk(text) {
    if (!libsReady) { pendingChunks.push(text); return; }
    if (!smdParser) { initStreaming(document.querySelector('.content')); }
    rawMarkdown += text;
    smd.parser_write(smdParser, text);
    autoScroll();
}

function finalize() {
    if (smdParser) { smd.parser_end(smdParser); }

    // Full re-render with syntax highlighting
    const markedInstance = new marked.Marked(
        markedHighlight.markedHighlight({
            emptyLangClass: 'hljs',
            langPrefix: 'hljs language-',
            highlight(code, lang) {
                if (lang && hljs.getLanguage(lang)) {
                    return hljs.highlight(code, { language: lang }).value;
                }
                return hljs.highlightAuto(code).value;
            }
        })
    );

    // Configure marked for links opening in new tab
    const renderer = new marked.Renderer();
    renderer.link = function({ href, title, text }) {
        const titleAttr = title ? ' title="' + title + '"' : '';
        return '<a href="' + href + '"' + titleAttr +
               ' target="_blank" rel="noopener noreferrer">' + text + '</a>';
    };
    markedInstance.use({ renderer });

    const rawHTML = markedInstance.parse(rawMarkdown);
    const safeHTML = DOMPurify.sanitize(rawHTML, {
        ADD_ATTR: ['target'],  // Allow target="_blank"
    });

    document.querySelector('.content').innerHTML = safeHTML;

    // Re-typeset MathJax
    if (window.MathJax && MathJax.typesetPromise) {
        MathJax.typesetPromise([document.querySelector('.content')]).catch(() => {});
    }
}
```

### CSS for Rendered Markdown (Dark Theme)
```css
/* Typographic hierarchy */
.content h1 { font-size: 1.5em; font-weight: 700; margin: 0.8em 0 0.4em; }
.content h2 { font-size: 1.3em; font-weight: 600; margin: 0.7em 0 0.3em; }
.content h3 { font-size: 1.15em; font-weight: 600; margin: 0.6em 0 0.3em; }
.content p { margin: 0.4em 0; }
.content ul, .content ol { padding-left: 1.4em; margin: 0.4em 0; }
.content li { margin: 0.15em 0; }

/* Code blocks */
.content pre {
    background: rgba(0,0,0,0.3);
    border-radius: 6px;
    padding: 10px 12px;
    margin: 0.5em 0;
    overflow-x: auto;
    font-size: 12px;
    line-height: 1.45;
}
.content pre code {
    font-family: 'SF Mono', 'Menlo', 'Monaco', monospace;
    background: none;
    padding: 0;
}

/* Inline code */
.content code {
    font-family: 'SF Mono', 'Menlo', 'Monaco', monospace;
    background: rgba(255,255,255,0.08);
    padding: 0.15em 0.35em;
    border-radius: 3px;
    font-size: 0.9em;
}

/* Blockquotes */
.content blockquote {
    border-left: 3px solid rgba(255,255,255,0.2);
    padding-left: 12px;
    margin: 0.5em 0;
    color: rgba(240,240,242,0.7);
}

/* Links */
.content a {
    color: #6cb4ff;
    text-decoration: none;
}
.content a:hover { text-decoration: underline; }

/* Tables */
.content table {
    border-collapse: collapse;
    margin: 0.5em 0;
    width: 100%;
}
.content th, .content td {
    border: 1px solid rgba(255,255,255,0.15);
    padding: 4px 8px;
    text-align: left;
}
.content th {
    background: rgba(255,255,255,0.06);
    font-weight: 600;
}

/* Horizontal rule */
.content hr {
    border: none;
    border-top: 1px solid rgba(255,255,255,0.15);
    margin: 0.8em 0;
}

/* Bold and italic */
.content strong { font-weight: 600; }
.content em { font-style: italic; }
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| innerHTML += per chunk | streaming-markdown incremental DOM | 2024+ | O(n) vs O(n^2) — critical for long AI responses |
| marked.parse() per chunk | Parse once on completion | 2024+ | Eliminates redundant parsing of stable blocks |
| No sanitization | DOMPurify before innerHTML | Always recommended | Prevents XSS from LLM-generated content |
| Manual regex highlighting | highlight.js with auto-detection | Mature (2013+) | Reliable multi-language support |

**Deprecated/outdated:**
- Prism.js `data-manual` attribute pattern — still works but Prism requires explicit language classes, less suitable when language may be unspecified
- marked.js `highlight` option (removed in v5+) — use `marked-highlight` extension instead

## Open Questions

1. **streaming-markdown code highlighting callback**
   - What we know: smd renders `<code>` elements during streaming. The `default_renderer` creates DOM nodes. There may be a `code_to_html` hook but documentation is sparse.
   - What's unclear: Whether we can hook highlight.js into smd's code block rendering during streaming.
   - Recommendation: Do NOT attempt streaming syntax highlighting. Defer all highlighting to finalization. During streaming, code blocks will have monospace styling but no syntax colors — this is acceptable and matches ChatGPT's behavior.

2. **MathJax and marked.js dollar sign conflict**
   - What we know: Both use `$` as a delimiter. Processing order matters.
   - What's unclear: Whether a simple marked.js extension to preserve `$...$` blocks is sufficient, or if a more complex pre-processing step is needed.
   - Recommendation: Test empirically. Start with running MathJax after marked.js. If conflicts arise, add a pre-processor that replaces `$...$` and `$$...$$` with unique placeholder tokens before marked.js, then restores them after.

3. **Inline vs CDN for streaming-markdown**
   - What we know: smd is only 3kB. CDN adds a network dependency and potential race condition.
   - What's unclear: Whether inlining the minified JS is better than CDN loading.
   - Recommendation: Inline smd.min.js directly in the HTML template string to eliminate the CDN race condition for this critical library. Keep larger libraries (marked, highlight.js, MathJax) on CDN.

## Sources

### Primary (HIGH confidence)
- [Chrome DevRel - Best Practices for Rendering Streamed LLM Responses](https://developer.chrome.com/docs/ai/render-llm-responses) — recommends streaming-markdown + DOMPurify
- [highlight.js Official Docs](https://highlightjs.readthedocs.io/en/latest/) — API, CDN setup, auto-detection
- [marked.js Official Docs](https://marked.js.org/) — UMD/CDN setup, renderer customization
- [marked-highlight GitHub](https://github.com/markedjs/marked-highlight) — UMD CDN build, highlight.js integration API
- [streaming-markdown GitHub](https://github.com/thetarnav/streaming-markdown) — API: parser(), parser_write(), parser_end(), default_renderer()
- [DeepWiki streaming-markdown](https://deepwiki.com/thetarnav/streaming-markdown/3.1-basic-usage) — Renderer interface, supported features

### Secondary (MEDIUM confidence)
- [Incremark DEV article](https://dev.to/kingshuaishuai/eliminate-redundant-markdown-parsing-typically-2-10x-faster-ai-streaming-4k94) — O(n^2) problem analysis, incremental parsing concept
- [MathJax 4.0 Docs - TeX Delimiters](https://docs.mathjax.org/en/latest/input/tex/delimiters.html) — dollar sign configuration
- [highlight.js vs Prism discussion](https://github.com/highlightjs/highlight.js/issues/3625) — auto-detection comparison

### Tertiary (LOW confidence)
- streaming-markdown code highlighting hooks — documentation is sparse, could not verify code_to_html callback existence

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries verified via official docs and CDN availability confirmed
- Architecture (two-phase rendering): HIGH — pattern recommended by Chrome DevRel, used by major AI chat apps
- Pitfalls: MEDIUM — MathJax/marked conflict needs empirical validation
- Code examples: MEDIUM — patterns assembled from official docs but not tested in WKWebView specifically

**Research date:** 2026-03-15
**Valid until:** 2026-04-15 (stable libraries, unlikely to change significantly)
