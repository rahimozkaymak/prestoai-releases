# Phase 1: Overlay Rich Text — Execution Plan

**Goal:** Transform the response overlay from single-font plain text to a rich reading experience with markdown rendering, typographic hierarchy, code highlighting, and smooth streaming.

**Key file:** `PrestoAI/Views/OverlayManager-3.swift`

---

## Architecture

**Two-phase rendering strategy:**
1. **Streaming phase:** `streaming-markdown` (smd) library incrementally appends DOM nodes as chunks arrive — O(n) performance
2. **Finalization phase:** On stream complete, re-render accumulated raw markdown with `marked.js` + `highlight.js` for full syntax highlighting and polished output

**Libraries:**
- `streaming-markdown` (smd) — 3kB, **inlined** in HTML template to avoid CDN race condition
- `marked.js` (CDN) — full markdown parsing on finalization
- `marked-highlight` (CDN) — bridge between marked and highlight.js
- `highlight.js` (CDN) — code syntax highlighting with auto language detection
- `DOMPurify` (CDN) — sanitize HTML output before DOM injection
- `MathJax` (CDN) — already present, no change

**CDN failure handling:** If marked.js or highlight.js fail to load from CDN, `finalize()` gracefully skips re-rendering — the smd-rendered streaming output is already usable with basic formatting. The user sees markdown with correct structure but without syntax highlighting.

---

## Tasks

### Task 1: Core rewrite — responseHTML + streaming markdown + finalization + auto-scroll

**What:** Replace the entire `responseHTML()` method and `appendChunkDirect()` to use the two-phase rendering architecture. Inline smd.min.js. Add auto-scroll. Add link click handling.

**Files:** `OverlayManager-3.swift`

**Note:** This renames the JS function from `appendContent` to `appendChunk`. The Swift method `appendChunkDirect()` keeps the same name but its JS call changes from `appendContent(...)` to `appendChunk(...)`.

**Sub-steps:**

**1a. Fetch and inline smd.min.js:**
- Download `https://cdn.jsdelivr.net/npm/streaming-markdown/smd.min.js`
- Add as a private string constant: `private let smdJS = "..."` (3kB minified)
- Embed in HTML template via `<script>\(smdJS)</script>` before CDN scripts

**1b. Replace `responseHTML()` template with:**

CDN script tags for marked.js, marked-highlight, highlight.js, DOMPurify, MathJax (keep existing). Inlined smd.min.js. highlight.js github-dark theme CSS.

Markdown typography CSS — full typographic hierarchy:
```css
.content h1 { font-size: 1.5em; font-weight: 700; margin: 0.8em 0 0.4em; }
.content h2 { font-size: 1.3em; font-weight: 600; margin: 0.7em 0 0.3em; }
.content h3 { font-size: 1.15em; font-weight: 600; margin: 0.6em 0 0.3em; }
.content p { margin: 0.4em 0; }
.content ul, .content ol { padding-left: 1.4em; margin: 0.4em 0; }
.content li { margin: 0.15em 0; }
.content pre { background: rgba(0,0,0,0.3); border-radius: 6px; padding: 10px 12px; margin: 0.5em 0; overflow-x: auto; font-size: 12px; line-height: 1.45; }
.content pre code { font-family: 'SF Mono', Menlo, Monaco, monospace; background: none; padding: 0; }
.content code { font-family: 'SF Mono', Menlo, Monaco, monospace; background: rgba(255,255,255,0.08); padding: 0.15em 0.35em; border-radius: 3px; font-size: 0.9em; }
.content blockquote { border-left: 3px solid rgba(255,255,255,0.2); padding-left: 12px; margin: 0.5em 0; color: rgba(240,240,242,0.7); }
.content a { color: #6cb4ff; text-decoration: none; }
.content a:hover { text-decoration: underline; }
.content table { border-collapse: collapse; margin: 0.5em 0; width: 100%; }
.content th, .content td { border: 1px solid rgba(255,255,255,0.15); padding: 4px 8px; text-align: left; }
.content th { background: rgba(255,255,255,0.06); font-weight: 600; }
.content hr { border: none; border-top: 1px solid rgba(255,255,255,0.15); margin: 0.8em 0; }
.content strong { font-weight: 600; }
```

JavaScript with core functions:
```javascript
// CDN load coordination
let libsReady = false;
let pendingFinalize = false;

function checkLibs() {
    if (window.marked && window.markedHighlight && window.hljs && window.DOMPurify) {
        libsReady = true;
        if (pendingFinalize) { pendingFinalize = false; finalize(); }
    }
}

// streaming-markdown setup
let rawMarkdown = '';
let smdParser = null;

function appendChunk(text) {
    if (!smdParser) {
        const el = document.querySelector('.content');
        el.innerHTML = '';
        const renderer = smd.default_renderer(el);
        smdParser = smd.parser(renderer);
    }
    rawMarkdown += text;
    smd.parser_write(smdParser, text);
    autoScroll();
}

function finalize() {
    if (smdParser) { smd.parser_end(smdParser); }

    // Guard: if CDN libs didn't load, keep smd output (still usable)
    if (!window.marked || !window.hljs) {
        console.warn('CDN libs not loaded, skipping finalization');
        // Still run MathJax on smd output
        if (window.MathJax && MathJax.typesetPromise) {
            MathJax.typesetPromise([document.querySelector('.content')]).catch(() => {});
        }
        return;
    }

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

    // Links open in default browser
    const renderer = new marked.Renderer();
    renderer.link = function({ href, title, text }) {
        const titleAttr = title ? ' title="' + title + '"' : '';
        return '<a href="' + href + '"' + titleAttr +
               ' target="_blank" rel="noopener noreferrer">' + text + '</a>';
    };
    markedInstance.use({ renderer });

    const rawHTML = markedInstance.parse(rawMarkdown);
    const safeHTML = DOMPurify.sanitize(rawHTML, { ADD_ATTR: ['target'] });
    document.querySelector('.content').innerHTML = safeHTML;

    // Re-typeset MathJax
    if (window.MathJax && MathJax.typesetPromise) {
        MathJax.typesetPromise([document.querySelector('.content')]).catch(() => {});
    }
}

// Auto-scroll: follow new content, stop if user scrolls up
let userScrolledUp = false;
const contentArea = document.querySelector('.content-area');
if (contentArea) {
    contentArea.addEventListener('scroll', () => {
        const atBottom = contentArea.scrollHeight - contentArea.scrollTop - contentArea.clientHeight < 30;
        userScrolledUp = !atBottom;
    });
}
function autoScroll() {
    if (!userScrolledUp && contentArea) {
        contentArea.scrollTop = contentArea.scrollHeight;
    }
}
```

Each CDN `<script>` tag gets `onload="checkLibs()"` to detect when all libs are ready.

**1c. Update `appendChunkDirect()`** — same escaping, rename JS call:
```swift
private func appendChunkDirect(_ text: String) {
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`", with: "\\`")
        .replacingOccurrences(of: "$", with: "\\$")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
    webView?.evaluateJavaScript("appendChunk(`\(escaped)`)", completionHandler: nil)
}
```

**1d. Add link interception** — `WKNavigationDelegate` method (navigationDelegate already wired at line 260):
```swift
func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if navigationAction.navigationType == .linkActivated,
       let url = navigationAction.request.url {
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    } else {
        decisionHandler(.allow)
    }
}
```

**Verify:** Build succeeds. Load overlay, send a response containing `# Heading`, `**bold**`, a fenced ` ```python ` code block, and a `[link](https://example.com)`. During streaming: headings render larger, bold renders bold, code appears in monospace. After stream ends (finalization): code block gets syntax highlighting colors. Link is clickable and opens in browser. Long response streams without lag.

---

### Task 2: Copy response button

**What:** Add a copy button in the overlay drag bar that copies the full response markdown to clipboard.

**Files:** `OverlayManager-3.swift`

**Changes:**

In `headerHTML()`, add a copy button after the drag spacer:
```html
<button class="copy-btn" id="copyBtn" onclick="copyResponse()" title="Copy response">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
        <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
    </svg>
</button>
```

Add CSS for copy button in `sharedHead()`:
```css
.copy-btn {
    background: none; border: none; cursor: pointer;
    opacity: 0.4; padding: 4px; border-radius: 4px;
    -webkit-app-region: no-drag;
    display: flex; align-items: center;
    color: #f0f0f2;
}
.copy-btn:hover { opacity: 0.7; background: rgba(255,255,255,0.08); }
.copy-btn.copied { opacity: 0.7; }
```

Add JS `copyResponse()` function (in responseHTML JS block):
```javascript
const copySVG = document.getElementById('copyBtn')?.innerHTML || '';
function copyResponse() {
    const text = rawMarkdown || document.querySelector('.content')?.innerText || '';
    navigator.clipboard.writeText(text).then(() => {
        const btn = document.getElementById('copyBtn');
        btn.innerHTML = '✓';
        btn.classList.add('copied');
        setTimeout(() => { btn.innerHTML = copySVG; btn.classList.remove('copied'); }, 1500);
    });
}
```

**Verify:** Click copy button → paste into TextEdit → full markdown text appears. Button shows checkmark briefly, then reverts to clipboard icon.

---

### Task 3: Wire `signalStreamEnd()` into SSE completion

**What:** Add `signalStreamEnd()` public method to OverlayManager. Wire it into `PrestoAIApp.swift`'s `onComplete` callback so finalization runs when the stream ends.

**Files:** `OverlayManager-3.swift`, `PrestoAIApp.swift`

**Changes in `OverlayManager-3.swift`:**
```swift
func signalStreamEnd() {
    DispatchQueue.main.async { [weak self] in
        self?.webView?.evaluateJavaScript("if(typeof finalize==='function')finalize()", completionHandler: nil)
    }
}
```

**Changes in `PrestoAIApp.swift`** (~line 292):
```swift
onComplete: { [weak self] queriesRemaining, state in
    Task { @MainActor in
        self?.overlayManager?.signalStreamEnd()
        stateManager.updateAfterQuery(queriesRemaining: queriesRemaining, state: state)
        self?.refreshMenuState()
    }
},
```

**Verify:** Trigger a screenshot analysis. During streaming, content renders incrementally via smd. When stream ends, finalization fires: code blocks gain syntax highlighting colors, links become clickable `<a>` tags. No visible flash/flicker on finalization (content structure stays the same, only styling improves).

---

## Execution Order

1. **Task 1** — Core rewrite (responseHTML, smd inline, appendChunkDirect rename, auto-scroll, link interception, CDN fallback)
2. **Task 2** — Copy button (adds to HTML template from Task 1)
3. **Task 3** — signalStreamEnd wiring (depends on Task 1's `finalize()` JS being in place)

---

## Testing Checklist

- [ ] Short response with no markdown renders correctly
- [ ] `# Heading`, `## Heading`, `### Heading` show distinct sizes/weights
- [ ] `**bold**` and `*italic*` render correctly during streaming
- [ ] Fenced code block with language (` ```python `) gets syntax highlighting after stream ends
- [ ] Fenced code block without language gets auto-detected highlighting
- [ ] Inline `code` renders with monospace background
- [ ] `- list items` render as proper bullet list
- [ ] `1. numbered items` render as ordered list
- [ ] Links `[text](url)` are clickable and open in Safari
- [ ] Tables render with borders and alignment
- [ ] LaTeX `$x^2$` and `$$\int_0^1$$` still render via MathJax
- [ ] Copy button copies full response markdown to clipboard
- [ ] Long response streams smoothly without lag (no O(n²) slowdown)
- [ ] Auto-scroll follows new content during streaming
- [ ] Scrolling up during streaming stops auto-scroll
- [ ] Stream finalization re-renders without jarring flash
- [ ] If CDN libs fail to load, streaming output still displays (graceful degradation)
- [ ] ESC still dismisses overlay
- [ ] Resize grip still works
- [ ] Drag bar still moves window
