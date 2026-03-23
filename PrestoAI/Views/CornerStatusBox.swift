import AppKit
import WebKit

class CornerStatusBox: NSObject, WKScriptMessageHandler {

    static let shared = CornerStatusBox()

    private var panel: OverlayPanel?
    private var webView: WKWebView?
    private var container: NSView?

    private let suggestionWidth: CGFloat = 340
    private let suggestionHeight: CGFloat = 130
    private let expandedWidth: CGFloat = 380
    private let expandedHeight: CGFloat = 200
    private let margin: CGFloat = 16

    private let appearSound = NSSound(named: "Pop")

    var onAutoSolveAccept: (() -> Void)?
    var onAutoSolveDecline: (() -> Void)?
    var onDismissedAnswer: (() -> Void)?

    // Pasteboard monitoring
    private var pasteboardTimer: Timer?
    private var lastChangeCount: Int = 0
    private var currentAnswerText: String?
    private var dismissTimer: Timer?

    private var isDarkMode: Bool {
        Theme.isDark(NSApp.effectiveAppearance)
    }

    private var screenFrame: NSRect {
        NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    // MARK: - Suggestion (homework detected prompt)

    func showSuggestion(subject: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentAnswerText = nil
            self.teardown()
            self.createPanel(width: self.suggestionWidth, height: self.suggestionHeight, cornerRadius: 14)
            self.webView?.loadHTMLString(self.suggestionHTML(subject: subject), baseURL: nil)
            self.animateResolve()
        }
    }

    // MARK: - Answer (expanded with answer + copy)

    func showAnswer(_ answer: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentAnswerText = answer
            self.teardown()

            let lineCount = max(1, answer.components(separatedBy: "\n").count)
            let charLines = max(1, answer.count / 40)
            let contentLines = max(lineCount, charLines)
            let height = min(self.expandedHeight, max(90, CGFloat(contentLines) * 20 + 60))

            self.createPanel(width: self.expandedWidth, height: height, cornerRadius: 14)
            self.webView?.loadHTMLString(self.answerHTML(answer: answer), baseURL: nil)
            self.animateResolve()

            self.appearSound?.stop()
            self.appearSound?.play()

            self.startPasteboardMonitoring()
        }
    }

    // MARK: - Hide

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.stopPasteboardMonitoring()
            self?.dismissTimer?.invalidate()
            self?.dismissTimer = nil
            self?.animateDissolve {
                self?.teardown()
            }
        }
    }

    // MARK: - Panel Lifecycle

    private func createPanel(width: CGFloat, height: CGFloat, cornerRadius: CGFloat) {
        let screen = screenFrame
        let x = screen.minX + margin
        let y = screen.minY + margin

        let frame = NSRect(x: x, y: y, width: width, height: height)
        let p = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "cornerbox")

        let wv = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")

        let cont = NSView(frame: NSRect(origin: .zero, size: frame.size))
        cont.wantsLayer = true
        cont.layer?.cornerRadius = cornerRadius
        cont.layer?.masksToBounds = true
        cont.layer?.backgroundColor = Theme.nsOverlayBg(NSApp.effectiveAppearance).cgColor
        cont.addSubview(wv)

        p.contentView = cont
        self.webView = wv
        self.container = cont
        self.panel = p
    }

    private func teardown() {
        stopPasteboardMonitoring()
        dismissTimer?.invalidate()
        dismissTimer = nil
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView = nil
        container = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Animations

    private func animateResolve() {
        guard let panel = panel, let container = container else { return }
        panel.alphaValue = 0
        container.layer?.transform = CATransform3DMakeScale(0.92, 0.92, 1.0)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
            container.layer?.transform = CATransform3DIdentity
        }
    }

    private func animateDissolve(completion: @escaping () -> Void) {
        guard let panel = panel else { completion(); return }
        NSAnimationContext.runAnimationGroup({ [weak self] ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            self?.container?.layer?.transform = CATransform3DMakeScale(0.95, 0.95, 1.0)
        }, completionHandler: completion)
    }

    // MARK: - Pasteboard Monitoring

    private func startPasteboardMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let answer = self.currentAnswerText else { return }
            let current = NSPasteboard.general.changeCount
            if current != self.lastChangeCount {
                self.lastChangeCount = current
                if let copied = NSPasteboard.general.string(forType: .string),
                   copied.trimmingCharacters(in: .whitespacesAndNewlines) == answer.trimmingCharacters(in: .whitespacesAndNewlines) {
                    self.scheduleDismissAfterCopy()
                }
            }
        }
    }

    private func stopPasteboardMonitoring() {
        pasteboardTimer?.invalidate()
        pasteboardTimer = nil
    }

    private func scheduleDismissAfterCopy() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.animateDissolve { [weak self] in
                    self?.teardown()
                    self?.onDismissedAnswer?()
                }
            }
        }
    }

    // MARK: - JS Bridge

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else { return }

        switch action {
        case "accept":
            animateDissolve { [weak self] in
                self?.teardown()
                self?.onAutoSolveAccept?()
            }
        case "decline":
            animateDissolve { [weak self] in
                self?.teardown()
                self?.onAutoSolveDecline?()
            }
        case "copy":
            if let text = dict["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                webView?.evaluateJavaScript("showCopied()", completionHandler: nil)
                scheduleDismissAfterCopy()
            }
        default: break
        }
    }

    // MARK: - HTML Templates

    private func suggestionHTML(subject: String) -> String {
        let escaped = subject
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html><html>
        <head><meta charset="UTF-8">
        <style>
        \(sharedCSS())
        body { display:flex; flex-direction:column; height:100vh; }
        .body { flex:1; padding:14px 16px; display:flex; flex-direction:column; gap:10px; }
        .header { font-size:13px; font-weight:600; color:var(--text); }
        .text { font-size:13px; color:var(--text-dim); line-height:1.4; }
        .actions { display:flex; gap:8px; align-items:center; }
        .btn-yes {
            background:var(--subtle-bg); border:1px solid var(--subtle-border);
            border-radius:6px; color:var(--text); font-size:12px; font-weight:500;
            padding:5px 14px; cursor:pointer; font-family:-apple-system,sans-serif;
            transition:background 0.15s;
        }
        .btn-yes:hover { background:var(--subtle-border); }
        .btn-no {
            background:none; border:none; color:var(--text-dim); font-size:12px;
            cursor:pointer; font-family:-apple-system,sans-serif; padding:5px 8px;
        }
        .btn-no:hover { color:var(--text); }
        </style></head>
        <body>
        <div class="body">
            <div class="header">Presto</div>
            <div class="text">I see we started \(escaped) homework. Would you like me to start auto-solve?</div>
            <div class="actions">
                <button class="btn-yes" onclick="accept()">Yes, start solving</button>
                <button class="btn-no" onclick="decline()">Not now</button>
            </div>
        </div>
        <script>
        function accept(){window.webkit.messageHandlers.cornerbox.postMessage({action:'accept'});}
        function decline(){window.webkit.messageHandlers.cornerbox.postMessage({action:'decline'});}
        function setTheme(d){document.documentElement.className=d?'':'light';}
        setTheme(\(isDarkMode));
        </script></body></html>
        """
    }

    private func answerHTML(answer: String) -> String {
        let htmlEscaped = answer
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")

        let jsEscaped = answer
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        return """
        <!DOCTYPE html><html>
        <head><meta charset="UTF-8">
        <style>
        \(sharedCSS())
        body { display:flex; flex-direction:column; height:100vh; padding:12px 14px; }
        .header { display:flex; align-items:center; justify-content:space-between; margin-bottom:8px; }
        .title { font-size:11px; font-weight:600; color:var(--text-dim); text-transform:uppercase; letter-spacing:0.5px; }
        .answer-area {
            flex:1; display:flex; align-items:flex-start; gap:10px;
        }
        .answer-text {
            flex:1; font-size:13px; color:var(--text); line-height:1.5;
            word-break:break-word; overflow-y:auto;
        }
        .copy-btn {
            flex-shrink:0; width:32px; height:32px; border:none;
            background:var(--subtle-bg); border-radius:8px;
            cursor:pointer; display:flex; align-items:center; justify-content:center;
            transition: background 0.15s, transform 0.1s;
        }
        .copy-btn:hover { background:var(--subtle-border); transform:scale(1.08); }
        .copy-btn:active { transform:scale(0.95); }
        .copy-btn svg { width:16px; height:16px; fill:var(--text-dim); transition:fill 0.2s; }
        .copy-btn.copied svg { fill:#34c759; }
        </style></head>
        <body>
        <div class="header">
            <span class="title">Answer</span>
        </div>
        <div class="answer-area">
            <div class="answer-text">\(htmlEscaped)</div>
            <button class="copy-btn" id="copyBtn" onclick="copyAnswer()">
                <svg id="copyIcon" viewBox="0 0 24 24"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>
            </button>
        </div>
        <script>
        function copyAnswer(){
            window.webkit.messageHandlers.cornerbox.postMessage({action:'copy',text:'\(jsEscaped)'});
        }
        function showCopied(){
            var b=document.getElementById('copyBtn');
            b.classList.add('copied');
            document.getElementById('copyIcon').innerHTML='<path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>';
        }
        function setTheme(d){document.documentElement.className=d?'':'light';}
        setTheme(\(isDarkMode));
        </script></body></html>
        """
    }

    private func sharedCSS() -> String {
        """
        :root {
            --bg: rgba(18,18,20,0.50);
            --text: #f0f0f2;
            --text-dim: rgba(255,255,255,0.28);
            --subtle-bg: rgba(255,255,255,0.08);
            --subtle-border: rgba(255,255,255,0.15);
        }
        :root.light {
            --bg: rgba(255,255,255,0.50);
            --text: #1a1a1a;
            --text-dim: rgba(0,0,0,0.25);
            --subtle-bg: rgba(0,0,0,0.05);
            --subtle-border: rgba(0,0,0,0.10);
        }
        * { margin:0; padding:0; box-sizing:border-box; }
        html, body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            background: var(--bg);
            color: var(--text);
            font-size: 13px;
            line-height: 1.6;
            overflow: hidden;
            -webkit-user-select: none;
        }
        """
    }
}
