import AppKit
import WebKit

class AnswerBubbleWindow: NSPanel, WKScriptMessageHandler {

    private var webView: WKWebView!
    private let answerLatex: String
    private let answerCopyable: String

    // Drag support via NSEvent monitor (WKWebView ignores CSS drag regions)
    private var dragMonitor: Any?
    private var dragStartLocation: NSPoint?
    private var frameAtDragStart: NSRect?

    init(answerLatex: String, answerCopyable: String, initialFrame: NSRect) {
        self.answerLatex = answerLatex
        self.answerCopyable = answerCopyable
        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setupContent()
        setupDragMonitor()
    }

    // MARK: - Setup

    private func setupContent() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "bubble")

        let wv = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        self.webView = wv

        // Use .hudWindow material which is dark and works well on all appearances
        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 12
        fx.layer?.masksToBounds = true
        fx.autoresizingMask = [.width, .height]
        fx.addSubview(wv)

        contentView = fx
        wv.loadHTMLString(buildHTML(), baseURL: nil)
    }

    private func setupDragMonitor() {
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] event in
            guard let self = self, event.window === self else { return event }
            switch event.type {
            case .leftMouseDown:
                self.dragStartLocation = NSEvent.mouseLocation
                self.frameAtDragStart = self.frame
            case .leftMouseDragged:
                if let start = self.dragStartLocation, let startFrame = self.frameAtDragStart {
                    let cur = NSEvent.mouseLocation
                    var f = startFrame
                    f.origin.x += cur.x - start.x
                    f.origin.y += cur.y - start.y
                    self.setFrameOrigin(f.origin)
                }
            default: break
            }
            return event
        }
    }

    deinit {
        if let m = dragMonitor { NSEvent.removeMonitor(m) }
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    // MARK: - HTML

    private func buildHTML() -> String {
        let htmlLatex = answerLatex
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let jsCopyable = answerCopyable
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        // #"..."# raw string: \( and \) are literal backslash-paren (MathJax inline delimiters).
        // \#(var) is Swift interpolation inside raw strings.
        // In the JS config, \\( in the raw string = \\( in HTML = \( after JS string parsing.
        return #"""
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <script>
        window.MathJax = {
            tex: { inlineMath: [['\\(', '\\)']] },
            startup: {
                ready() {
                    MathJax.startup.defaultReady();
                    MathJax.startup.promise.then(function() {
                        var h = document.body.scrollHeight;
                        window.webkit.messageHandlers.bubble.postMessage({action:'resize',height:h});
                    });
                }
            }
        };
        </script>
        <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js" async></script>
        <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 15px;
            color: #fff;
            background: transparent;
            -webkit-user-select: none;
            padding: 8px 36px 8px 12px;
            min-height: 40px;
        }
        .copy-btn {
            position: absolute;
            top: 6px; right: 6px;
            width: 24px; height: 24px;
            background: rgba(255,255,255,0.12);
            border: none; border-radius: 6px;
            cursor: pointer;
            display: flex; align-items: center; justify-content: center;
            transition: background 0.15s;
        }
        .copy-btn:hover { background: rgba(255,255,255,0.22); }
        .icon { width:14px; height:14px; fill:rgba(255,255,255,0.75); transition:fill 0.2s; }
        .icon-check { display:none; fill:#34c759; }
        .copy-btn.copied .icon-copy { display:none; }
        .copy-btn.copied .icon-check { display:block; }
        </style>
        </head>
        <body>
        <div id="math">\(\#(htmlLatex)\)</div>
        <button class="copy-btn" id="cb" onclick="doCopy()">
          <svg class="icon icon-copy" viewBox="0 0 24 24">
            <path d="M16 1H4C2.9 1 2 1.9 2 3v14h2V3h12V1zm3 4H8C6.9 5 6 5.9 6 7v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/>
          </svg>
          <svg class="icon icon-check" viewBox="0 0 24 24">
            <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>
          </svg>
        </button>
        <script>
        function doCopy(){
          window.webkit.messageHandlers.bubble.postMessage({action:'copy',text:'\#(jsCopyable)'});
        }
        function showCheck(){
          var b=document.getElementById('cb');
          b.classList.add('copied');
          setTimeout(function(){ b.classList.remove('copied'); }, 1500);
        }
        </script>
        </body>
        </html>
        """#
    }

    // MARK: - JS Bridge

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else { return }
        switch action {
        case "resize":
            if let h = dict["height"] as? CGFloat {
                let newH = max(44, h + 4)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    var f = self.frame
                    f.size.height = newH
                    self.setFrame(f, display: true, animate: false)
                }
            }
        case "copy":
            if let text = dict["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                webView.evaluateJavaScript("showCheck()", completionHandler: nil)
            }
        default: break
        }
    }

    // MARK: - Animation

    func show() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1.0
        }
    }

    func fadeOut() {
        NSAnimationContext.runAnimationGroup({ [weak self] ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}
