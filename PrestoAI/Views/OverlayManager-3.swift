import AppKit
import WebKit

class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class OverlayManager: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var overlayWindow: OverlayPanel?
    private var webView: WKWebView?
    private var resizeMonitor: Any?
    private var resizeStartFrame: NSRect = .zero
    private var resizeStartMouse: NSPoint = .zero
    private var isPageReady = false
    private var chunkQueue: [String] = []

    private let defaultWidth:  CGFloat = 420
    private let defaultHeight: CGFloat = 340
    private let minWidth:      CGFloat = 260
    private let minHeight:     CGFloat = 180

    // Template icon (black + alpha). CSS filter: invert(1) makes it white on dark bg.
    private let iconB64 = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAADDElEQVR4nO2YX2jNYRjHP+dsNmwYMskWJeVqKVwQtyhXytxgI5IkIbVLS0vLny32J4mZsWb+XOxSKBnzJ4lbJSklWW6UC6bj4v2+/R6vsz+/82+Up06/8z7v732ez/u8f57nHPgvhZWEPmP1/zVSpGeSHIMlZNSKb9cAKwIAG7WSwE7exDtvAbqJoBOmrxEYBm4CM6ULJxZL/IwWA8sNSAJYIJAfQEpOFwWgKeClnk+AisBubJhSoBhoAPpxsytVXwlQCfQCA8B8YKrGtgqiR+29at/X+KyiBHAH+BzovNE1wHqjPyPnXWr7PdQt/bJg/ITEL8kGoBn4JmNXgFpgCb+fHP88q/cuBTB1wAgwBEwj5qnzJ+QI8EEOUsBPPb8C7bjlSeKWFKBN/ZcDmG3SvwLmBROILVOA1cBHGd0KlBmjfgO3q/+W2n4vbZf+BTBXuoz3j717rgJvTV+RgTkvpyPAe2CV9PXSPwfmmHFZSbGM1AOnBFhiDHfKaSuwDncFDAPH8gFjpVyG7TL5yHSa92qALwZmdi4h0olfwgty2qF2qZ6bge/AoIGpxKWWdOknKxAfmYuCaQtgdkj/DHcjJ3GHohZ3IfrLNOt8ZmfWJafnAhh/mp4SpQcvHbio5SQ6FqabaANbmDrpHwOzpKsAVgKHgU/q7wU2AdWZwlmYHhltCWB2GhibzeuBd/x5qaaAPtz+Gq+wSwuTAK7J0OkAZpf0j4giY4/2dGAt8EbvNQALJwpgJWk+vTJ2MoDZLf0Q6escO/smXLqxfbFgfHT65LRZfT4d7CGKzFhFl7/NN+JKlwTu1GUE0y+nJwIYX9fYDTzeBi0DqvR9wtGxpaeHaQpg9kk/GAMmI/HrXYzL1ingeACzX/qHwIyYMLFPk79BB+S0MYA5IP0DXE6LAxNbfIF1YxSYg0S1cJkZkzcYgKVyej2AOVRIGIiWqxx4jaubt6jvqGDu4S64vMN48U6qcRWhzzkp4G6hYUKoKlzpkAJu434dFBwmhErifn16mdR/LkbLRZMqOS0z/1n5BUqXpG40It4WAAAAAElFTkSuQmCC"

    // MARK: - Persistence

    private let frameKey = "overlayWindowFrame"

    private var savedFrame: NSRect? {
        get {
            guard let s = UserDefaults.standard.string(forKey: frameKey) else { return nil }
            let r = NSRectFromString(s)
            return (r.width > 0 && r.height > 0) ? r : nil
        }
        set {
            UserDefaults.standard.set(newValue.map { NSStringFromRect($0) }, forKey: frameKey)
        }
    }

    // MARK: - Public API

    func showLoading() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.ensureWindow()
            self.webView?.loadHTMLString(self.loadingHTML(), baseURL: nil)
            self.present()
        }
    }

    func showResponse(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPageReady = false
            self.chunkQueue.removeAll()
            self.ensureWindow()
            self.webView?.loadHTMLString(self.responseHTML(text), baseURL: nil)
            self.present()
        }
    }

    func appendChunk(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isPageReady {
                self.appendChunkDirect(text)
            } else {
                self.chunkQueue.append(text)
            }
        }
    }

    // FIX #3: Escape newlines and carriage returns to prevent JS breakage
    private func appendChunkDirect(_ text: String) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        webView?.evaluateJavaScript("appendContent(`\(escaped)`)", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageReady = true
        for chunk in chunkQueue { appendChunkDirect(chunk) }
        chunkQueue.removeAll()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isPageReady = true
        for chunk in chunkQueue { appendChunkDirect(chunk) }
        chunkQueue.removeAll()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isPageReady = true
        for chunk in chunkQueue { appendChunkDirect(chunk) }
        chunkQueue.removeAll()
    }

    func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.ensureWindow()
            self.webView?.loadHTMLString(self.errorHTML(message), baseURL: nil)
            self.present()
        }
    }

    // FIX #6: Properly tear down webview to prevent retain cycle
    func dismiss() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let f = self.overlayWindow?.frame { self.savedFrame = f }
            self.overlayWindow?.orderOut(nil)
            self.stopResize()
            HotkeyService.shared.unregisterEsc()

            // Break the retain cycle: WKUserContentController -> self
            self.webView?.configuration.userContentController.removeAllScriptMessageHandlers()
            self.webView?.navigationDelegate = nil
            self.webView?.removeFromSuperview()
            self.webView = nil
            self.overlayWindow = nil
            self.isPageReady = false
            self.chunkQueue.removeAll()

            print("[Overlay] Dismissed and cleaned up")
        }
    }

    // MARK: - WKScriptMessageHandler (resize grip events from JS)

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else { return }
        switch action {
        case "resizeStart": startResize()
        case "resizeEnd":
            stopResize()
            if let f = overlayWindow?.frame { savedFrame = f }
        default: break
        }
    }

    // MARK: - Resize via global NSEvent monitor

    private func startResize() {
        guard let window = overlayWindow else { return }
        resizeStartFrame = window.frame
        resizeStartMouse = NSEvent.mouseLocation

        resizeMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self = self, let window = self.overlayWindow else { return }

            if event.type == .leftMouseUp {
                self.stopResize()
                self.savedFrame = window.frame
                return
            }

            let cur = NSEvent.mouseLocation
            let dx  = cur.x - self.resizeStartMouse.x
            let dy  = cur.y - self.resizeStartMouse.y

            var f = self.resizeStartFrame
            let newW = max(self.minWidth,  f.size.width  - dx)
            let newH = max(self.minHeight, f.size.height - dy)
            f.origin.x = f.origin.x + f.size.width  - newW
            f.origin.y = f.origin.y + f.size.height - newH
            f.size = NSSize(width: newW, height: newH)

            DispatchQueue.main.async { window.setFrame(f, display: true, animate: false) }
        }
    }

    private func stopResize() {
        if let m = resizeMonitor { NSEvent.removeMonitor(m); resizeMonitor = nil }
    }

    // MARK: - Window lifecycle

    private func ensureWindow() {
        // FIX #6: Always recreate since dismiss() now tears down the window
        if overlayWindow != nil { return }

        let frame: NSRect
        if let saved = savedFrame, screenContains(saved) {
            frame = saved
        } else {
            frame = defaultFrame()
        }
        createWindow(frame: frame)
    }

    // FIX #1: Activate the app so the overlay is reliably visible
    private func present() {
        guard let window = overlayWindow else { return }
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        // Without this, accessory apps may not bring floating panels to front
        NSApp.activate(ignoringOtherApps: true)
        HotkeyService.shared.registerEsc()
    }

    private func screenContains(_ rect: NSRect) -> Bool {
        NSScreen.screens.contains { NSContainsRect($0.frame, rect) }
    }

    private func defaultFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                           ?? NSScreen.main ?? NSScreen.screens.first else {
            // #6 — Fallback if no screen is available
            return NSRect(x: 100, y: 100, width: defaultWidth, height: defaultHeight)
        }
        let sf = screen.visibleFrame
        let pad: CGFloat = 20
        return NSRect(
            x: sf.maxX - defaultWidth - pad,
            y: sf.maxY - defaultHeight - pad,
            width: defaultWidth,
            height: defaultHeight
        )
    }

    // MARK: - Window Creation
    // FIX #1: Add a semi-opaque backing layer so the window is visible even before HTML loads

    private func createWindow(frame: NSRect) {
        let panel = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: minWidth, height: minHeight)

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "overlay")

        let wv = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = self
        if let sv = wv.enclosingScrollView {
            sv.verticalScrollElasticity = .none
        }

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        // FIX #1: Opaque backing so window is visible immediately, even before HTML renders
        container.layer?.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.078, alpha: 0.92).cgColor
        container.addSubview(wv)

        panel.contentView = container
        self.webView = wv
        self.overlayWindow = panel
        print("[Overlay] Window created at \(frame)")
    }

    // MARK: - HTML

    private func sharedHead(extraStyle: String = "") -> String {
        """
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width">
        <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        html, body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            background: rgba(18,18,20,0.60);
            color: #f0f0f2;
            font-size: 13px;
            line-height: 1.6;
            height: 100vh;
            overflow: hidden;
            -webkit-app-region: no-drag;
        }
        .drag-bar {
            position: fixed; top: 0; left: 0; right: 0; height: 36px;
            display: flex; align-items: center; padding: 0 10px;
            gap: 8px;
            -webkit-app-region: drag;
            cursor: default;
        }
        .drag-bar * { -webkit-app-region: no-drag; }
        .logo {
            width: 15px; height: 15px;
            filter: invert(1);
            opacity: 0.75;
            flex-shrink: 0;
        }
        .drag-spacer { flex: 1; }
        .content-area {
            position: absolute; top: 36px; left: 0; right: 0; bottom: 28px;
            overflow-y: auto; overflow-x: hidden;
            padding: 0 16px 8px 16px;
            -webkit-overflow-scrolling: auto;
        }
        .bottom-bar {
            position: fixed; bottom: 0; left: 0; right: 0; height: 28px;
            display: flex; align-items: center; justify-content: space-between;
            padding: 0 10px;
        }
        .resize-grip {
            width: 28px; height: 28px;
            cursor: nwse-resize;
            user-select: none;
            -webkit-app-region: no-drag;
        }
        .esc-hint {
            font-size: 10px; color: rgba(255,255,255,0.28);
            letter-spacing: 0.03em;
        }
        \(extraStyle)
        </style>
        </head>
        """
    }

    private func gripSVG() -> String { "" }

    private func gripJS() -> String {
        """
        <script>
        document.getElementById('grip').addEventListener('mousedown', function(e) {
            e.preventDefault();
            window.webkit.messageHandlers.overlay.postMessage({action:'resizeStart'});
            function onUp() {
                window.webkit.messageHandlers.overlay.postMessage({action:'resizeEnd'});
                document.removeEventListener('mouseup', onUp);
            }
            document.addEventListener('mouseup', onUp);
        });
        </script>
        """
    }

    private func headerHTML() -> String {
        """
        <div class="drag-bar">
            <img class="logo" src="data:image/png;base64,\(iconB64)">
            <span class="drag-spacer"></span>
        </div>
        """
    }

    private func bottomBarHTML() -> String {
        """
        <div class="bottom-bar">
            <div class="resize-grip" id="grip">\(gripSVG())</div>
            <span class="esc-hint">Press ESC to close</span>
        </div>
        """
    }

    // FIX #2: Corrected MathJax displayMath from '15' to '$$'
    // FIX #3: Updated appendContent JS to handle escaped newlines
    private func responseHTML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")

        return """
        <!DOCTYPE html>
        <html>
        \(sharedHead(extraStyle: """
        .content { white-space: pre-wrap; word-wrap: break-word; padding-top: 4px; }
        .MathJax { font-size: 1.05em !important; }
        mjx-container { margin: 0.4em 0; }
        """))
        <script>
        MathJax = {
            tex: { inlineMath: [['$','$'],['\\\\(','\\\\)']], displayMath: [['$$','$$'],['\\\\[','\\\\]']], processEscapes: true },
            options: { skipHtmlTags: ['script','noscript','style','textarea','pre'] }
        };
        </script>
        <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js" async></script>
        <script>
        function appendContent(text) {
            var el = document.querySelector('.content');
            if (!el) return;

            // Convert escaped newlines back to <br> tags
            var s = text.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
                        .replace(/\\r\\n|\\r|\\n/g,'<br>');
            el.innerHTML += s;

            if (window.MathJax && MathJax.typesetPromise) {
                MathJax.typesetPromise([el]).catch(function(){});
            }
        }
        </script>
        <body>
        \(headerHTML())
        <div class="content-area"><div class="content">\(escaped)</div></div>
        \(bottomBarHTML())
        \(gripJS())
        </body></html>
        """
    }

    private func loadingHTML() -> String {
        """
        <!DOCTYPE html><html>
        \(sharedHead(extraStyle: """
        .center { display:flex; align-items:center; justify-content:center;
                  height:100%; flex-direction:column; gap:12px; }
        .spinner { width:28px; height:28px; border:2.5px solid rgba(255,255,255,0.1);
                   border-top-color:rgba(255,255,255,0.5); border-radius:50%;
                   animation:spin 0.8s linear infinite; }
        @keyframes spin { to { transform:rotate(360deg); } }
        p { color:rgba(255,255,255,0.4); font-size:12px; }
        """))
        <body>
        \(headerHTML())
        <div class="content-area"><div class="center">
            <div class="spinner"></div><p>Analyzing…</p>
        </div></div>
        \(bottomBarHTML())
        \(gripJS())
        </body></html>
        """
    }

    private func errorHTML(_ message: String) -> String {
        let escaped = message
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html><html>
        \(sharedHead(extraStyle: ".err { color:#ff6b6b; padding-top:4px; }"))
        <body>
        \(headerHTML())
        <div class="content-area"><div class="err">\(escaped)</div></div>
        \(bottomBarHTML())
        \(gripJS())
        </body></html>
        """
    }
}
