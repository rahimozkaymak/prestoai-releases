import AppKit
import WebKit

class FeedbackController: NSObject, WKScriptMessageHandler {
    private var panel: OverlayPanel?
    private var webView: WKWebView?

    func show() {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let width: CGFloat = 400
        let height: CGFloat = 340
        let frame = NSRect(
            x: 0, y: 0, width: width, height: height
        )

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
        config.userContentController.add(self, name: "feedback")

        let wv = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0).cgColor
        container.addSubview(wv)

        p.contentView = container
        self.webView = wv
        self.panel = p

        wv.loadHTMLString(feedbackHTML(), baseURL: nil)

        p.center()
        p.orderFrontRegardless()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Drag support (WKWebView ignores CSS drag regions)
        setupDrag()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        webView = nil
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: String] else { return }

        if let action = body["action"] {
            if action == "close" {
                dismiss()
                return
            }
            if action == "submit", let text = body["message"] {
                submitFeedback(text)
                return
            }
        }
    }

    // MARK: - Submit

    private func submitFeedback(_ text: String) {
        let deviceID = AppStateManager.shared.deviceID
        let body: [String: Any] = ["device_id": deviceID, "message": text]

        Task {
            do {
                _ = try await APIService.shared.postFeedback(body: body)
                await MainActor.run {
                    webView?.evaluateJavaScript("showSuccess()", completionHandler: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    let escaped = error.localizedDescription
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                    webView?.evaluateJavaScript("showError('\(escaped)')", completionHandler: nil)
                }
            }
        }
    }

    // MARK: - Drag

    private var dragLocalMonitor: Any?
    private var dragGlobalMonitor: Any?
    private var dragStartOrigin: NSPoint = .zero
    private var dragStartMouse: NSPoint = .zero

    private func setupDrag() {
        dragLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] event in
            self?.handleDragEvent(event)
            return event
        }
        dragGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDragEvent(event)
        }
    }

    private func handleDragEvent(_ event: NSEvent) {
        guard let window = panel else { return }
        if event.type == .leftMouseDown && event.window === window {
            dragStartOrigin = window.frame.origin
            dragStartMouse = NSEvent.mouseLocation
        } else if event.type == .leftMouseDragged {
            let current = NSEvent.mouseLocation
            let dx = current.x - dragStartMouse.x
            let dy = current.y - dragStartMouse.y
            window.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
        }
    }

    deinit {
        if let m = dragLocalMonitor { NSEvent.removeMonitor(m) }
        if let m = dragGlobalMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - HTML

    private func feedbackHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                background: rgba(10,10,10,0.50);
                color: #f0f0f2;
                padding: 24px;
                -webkit-user-select: none;
                height: 100vh;
                display: flex;
                flex-direction: column;
            }
            h2 {
                font-size: 18px;
                font-weight: 600;
                margin-bottom: 4px;
            }
            .subtitle {
                font-size: 12px;
                color: rgba(255,255,255,0.45);
                margin-bottom: 16px;
            }
            textarea {
                width: 100%;
                flex: 1;
                min-height: 140px;
                background: rgba(255,255,255,0.06);
                border: 1px solid rgba(255,255,255,0.12);
                border-radius: 8px;
                color: #f0f0f2;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 13px;
                padding: 10px 12px;
                resize: none;
                outline: none;
                -webkit-user-select: text;
            }
            textarea:focus {
                border-color: rgba(255,255,255,0.25);
            }
            textarea::placeholder {
                color: rgba(255,255,255,0.25);
            }
            .buttons {
                display: flex;
                justify-content: flex-end;
                gap: 8px;
                margin-top: 12px;
            }
            button {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 13px;
                font-weight: 500;
                padding: 7px 18px;
                border-radius: 6px;
                border: none;
                cursor: pointer;
                transition: opacity 0.15s;
            }
            button:hover { opacity: 0.85; }
            .btn-cancel {
                background: rgba(255,255,255,0.08);
                color: rgba(255,255,255,0.6);
            }
            .btn-submit {
                background: #fff;
                color: #0A0A0A;
            }
            .btn-submit:disabled {
                opacity: 0.3;
                cursor: default;
            }
            .close-btn {
                position: absolute;
                top: 12px;
                right: 14px;
                background: none;
                border: none;
                color: rgba(255,255,255,0.35);
                font-size: 18px;
                cursor: pointer;
                padding: 2px 6px;
                line-height: 1;
            }
            .close-btn:hover { color: rgba(255,255,255,0.7); }
            .success-msg {
                display: none;
                text-align: center;
                padding: 40px 20px;
                flex: 1;
                justify-content: center;
                align-items: center;
                flex-direction: column;
            }
            .success-msg h3 {
                font-size: 18px;
                font-weight: 600;
                margin-bottom: 6px;
            }
            .success-msg p {
                font-size: 13px;
                color: rgba(255,255,255,0.5);
            }
            .error-msg {
                color: #ff6b6b;
                font-size: 11px;
                margin-top: 6px;
                display: none;
            }
        </style>
        </head>
        <body>
            <button class="close-btn" onclick="window.webkit.messageHandlers.feedback.postMessage({action:'close'})">&times;</button>
            <div id="form-view">
                <h2>Send Feedback</h2>
                <p class="subtitle">Tell us what you think, report a bug, or suggest a feature.</p>
                <textarea id="msg" placeholder="Your feedback..." autofocus></textarea>
                <div class="error-msg" id="error"></div>
                <div class="buttons">
                    <button class="btn-cancel" onclick="window.webkit.messageHandlers.feedback.postMessage({action:'close'})">Cancel</button>
                    <button class="btn-submit" id="submitBtn" disabled onclick="submitFeedback()">Submit</button>
                </div>
            </div>
            <div class="success-msg" id="success-view">
                <h3>Thanks for your feedback!</h3>
                <p>We appreciate you taking the time.</p>
            </div>
            <script>
                const ta = document.getElementById('msg');
                const btn = document.getElementById('submitBtn');
                ta.addEventListener('input', () => {
                    btn.disabled = ta.value.trim().length === 0;
                });
                function submitFeedback() {
                    const text = ta.value.trim();
                    if (!text) return;
                    btn.disabled = true;
                    btn.textContent = 'Sending...';
                    window.webkit.messageHandlers.feedback.postMessage({action:'submit', message: text});
                }
                function showSuccess() {
                    document.getElementById('form-view').style.display = 'none';
                    const sv = document.getElementById('success-view');
                    sv.style.display = 'flex';
                }
                function showError(msg) {
                    const el = document.getElementById('error');
                    el.textContent = msg;
                    el.style.display = 'block';
                    btn.disabled = false;
                    btn.textContent = 'Submit';
                }
            </script>
        </body>
        </html>
        """
    }
}
