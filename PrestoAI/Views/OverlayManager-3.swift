import AppKit
import WebKit

class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class OverlayManager: NSObject, WKScriptMessageHandler, WKNavigationDelegate, NSTextFieldDelegate {
    private var overlayWindow: OverlayPanel?
    private var webView: WKWebView?
    private var resizeMonitor: Any?
    private var resizeStartFrame: NSRect = .zero
    private var resizeStartMouse: NSPoint = .zero
    private var dragLocalMonitor: Any?
    private var dragGlobalMonitor: Any?
    private var dragStartOrigin: NSPoint = .zero
    private var dragStartMouse: NSPoint = .zero
    private var isPageReady = false
    private var chunkQueue: [String] = []
    private var pendingJSCalls: [String] = []
    private var isPromptMode = false
    private var studyTextField: NSTextField?
    private var studyPromptBg: NSView?      // styled background behind the text field
    private var studyPromptContainer: NSView? // outer container matching body bg opacity
    private let nativePromptHeight: CGFloat = 56

    // Follow-up conversation state
    private var conversationHistory: [(question: String, answer: String)] = []
    private var currentScreenshot: String?

    // Secondary popup (suggestion notification / session summary)
    private var popupPanel: OverlayPanel?
    private var popupWebView: WKWebView?
    private var popupDismissTimer: Timer?
    var onFollowUpSubmit: ((String) -> Void)?

    // Minimize/restore state
    private var preMinimizeFrame: NSRect?
    private var restorePill: NSPanel?

    // Delayed dismiss cancellation token
    private var pendingDismissWorkItem: DispatchWorkItem?

    private let defaultWidth:  CGFloat = 580
    private let defaultHeight: CGFloat = 340
    private let minWidth:      CGFloat = 260
    private let minHeight:     CGFloat = 180
    private let promptInputHeight: CGFloat = 100

    /// Callback fired when user submits a quick prompt
    var onPromptSubmit: ((String) -> Void)?

    // Template icon (black + alpha). CSS filter: invert(1) makes it white on dark bg.
    private let iconB64 = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAADDElEQVR4nO2YX2jNYRjHP+dsNmwYMskWJeVqKVwQtyhXytxgI5IkIbVLS0vLny32J4mZsWb+XOxSKBnzJ4lbJSklWW6UC6bj4v2+/R6vsz+/82+Up06/8z7v732ez/u8f57nHPgvhZWEPmP1/zVSpGeSHIMlZNSKb9cAKwIAG7WSwE7exDtvAbqJoBOmrxEYBm4CM6ULJxZL/IwWA8sNSAJYIJAfQEpOFwWgKeClnk+AisBubJhSoBhoAPpxsytVXwlQCfQCA8B8YKrGtgqiR+29at/X+KyiBHAH+BzovNE1wHqjPyPnXWr7PdQt/bJg/ITEL8kGoBn4JmNXgFpgCb+fHP88q/cuBTB1wAgwBEwj5qnzJ+QI8EEOUsBPPb8C7bjlSeKWFKBN/ZcDmG3SvwLmBROILVOA1cBHGd0KlBmjfgO3q/+W2n4vbZf+BTBXuoz3j717rgJvTV+RgTkvpyPAe2CV9PXSPwfmmHFZSbGM1AOnBFhiDHfKaSuwDncFDAPH8gFjpVyG7TL5yHSa92qALwZmdi4h0olfwgty2qF2qZ6bge/AoIGpxKWWdOknKxAfmYuCaQtgdkj/DHcjJ3GHohZ3IfrLNOt8ZmfWJafnAhh/mp4SpQcvHbio5SQ6FqabaANbmDrpHwOzpKsAVgKHgU/q7wU2AdWZwlmYHhltCWB2GhibzeuBd/x5qaaAPtz+Gq+wSwuTAK7J0OkAZpf0j4giY4/2dGAt8EbvNQALJwpgJWk+vTJ2MoDZLf0Q6escO/smXLqxfbFgfHT65LRZfT4d7CGKzFhFl7/NN+JKlwTu1GUE0y+nJwIYX9fYDTzeBi0DqvR9wtGxpaeHaQpg9kk/GAMmI/HrXYzL1ingeACzX/qHwIyYMLFPk79BB+S0MYA5IP0DXE6LAxNbfIF1YxSYg0S1cJkZkzcYgKVyej2AOVRIGIiWqxx4jaubt6jvqGDu4S64vMN48U6qcRWhzzkp4G6hYUKoKlzpkAJu434dFBwmhErifn16mdR/LkbLRZMqOS0z/1n5BUqXpG40It4WAAAAAElFTkSuQmCC"

    // MARK: - Inlined streaming-markdown (smd) library — 3kB minified
    // Source: https://cdn.jsdelivr.net/npm/streaming-markdown/smd.min.js
    private let smdJS = """
    var D=2,C=3,h=4,b=5,B=6,U=7,G=8,S=9,x=10,m=11,H=12,K=13,M=14,Q=15,w=16,q=17,W=18,P=19,Y=20,y=21,F=22,$=23,v=24,X=25,j=26,z=27,J=28,V=29,Z=30,p=31;var I=1,k=2,L=4,T=8,f=16;function ee(e){switch(e){case I:return"href";case k:return"src";case L:return"class";case T:return"checked";case f:return"start"}}var ne=e=>{switch(e){case 1:return 3;case 2:return 4;case 3:return 5;case 4:return 6;case 5:return 7;default:return 8}},te=ne;var O=24;function ae(e){let c=new Uint32Array(O);return c[0]=1,{renderer:e,text:"",pending:"",tokens:c,len:0,token:1,fence_end:0,blockquote_idx:0,hr_char:"",hr_chars:0,fence_start:0,spaces:new Uint8Array(O),indent:"",indent_len:0,table_state:0}}function ce(e){e.pending.length>0&&o(e,"\\n")}function a(e){e.text.length!==0&&(e.renderer.add_text(e.renderer.data,e.text),e.text="")}function _(e){e.len-=1,e.token=e.tokens[e.len],e.renderer.end_token(e.renderer.data)}function i(e,c){(e.tokens[e.len]===24||e.tokens[e.len]===23)&&c!==25&&_(e),e.len+=1,e.tokens[e.len]=c,e.token=c,e.renderer.add_token(e.renderer.data,c)}function re(e,c,n){for(;n<=e.len;){if(e.tokens[n]===c)return n;n+=1}return-1}function l(e,c){for(e.fence_start=0;e.len>c;)_(e)}function u(e,c){let n=0;for(let t=0;t<=e.len&&(c-=e.spaces[t],!(c<0));t+=1)switch(e.tokens[t]){case 9:case 10:case 20:case 25:n=t;break}for(;e.len>n;)_(e);return c}function A(e,c){let n=-1,t=-1;for(let s=e.blockquote_idx+1;s<=e.len;s+=1)if(e.tokens[s]===25){if(e.indent_len<e.spaces[s]){t=-1;break}t=s}else e.tokens[s]===c&&(n=s);return t===-1?n===-1?(l(e,e.blockquote_idx),i(e,c),!0):(l(e,n),!1):(l(e,t),i(e,c),!0)}function g(e,c){i(e,25),e.spaces[e.len]=e.indent_len+c,E(e),e.token=103}function E(e){e.indent="",e.indent_len=0,e.pending=""}function N(e){switch(e){case 48:case 49:case 50:case 51:case 52:case 53:case 54:case 55:case 56:case 57:return!0;default:return!1}}function ie(e){switch(e){case 32:case 58:case 59:case 41:case 44:case 33:case 46:case 63:case 93:case 10:return!0;default:return!1}}function se(e){return N(e)||ie(e)}function o(e,c){for(let n of c){if(e.token===101){switch(n){case" ":e.indent_len+=1;continue;case"\\t":e.indent_len+=4;continue}let s=u(e,e.indent_len);e.indent_len=0,e.token=e.tokens[e.len],s>0&&o(e," ".repeat(s))}let t=e.pending+n;switch(e.token){case 21:case 1:case 20:case 24:case 23:switch(e.pending[0]){case void 0:e.pending=n;continue;case" ":e.pending=n,e.indent+=" ",e.indent_len+=1;continue;case"\\t":e.pending=n,e.indent+="\\t",e.indent_len+=4;continue;case"\\n":if(e.tokens[e.len]===25&&e.token===21){_(e),E(e),e.pending=n;continue}l(e,e.blockquote_idx),E(e),e.blockquote_idx=0,e.fence_start=0,e.pending=n;continue;case"#":switch(n){case"#":if(e.pending.length<6){e.pending=t;continue}break;case" ":u(e,e.indent_len),i(e,te(e.pending.length)),E(e);continue}break;case">":{let r=re(e,20,e.blockquote_idx+1);r===-1?(l(e,e.blockquote_idx),e.blockquote_idx+=1,e.fence_start=0,i(e,20)):e.blockquote_idx=r,E(e),e.pending=n;continue}case"-":case"*":case"_":if(e.hr_chars===0&&(e.hr_chars=1,e.hr_char=e.pending),e.hr_chars>0){switch(n){case e.hr_char:e.hr_chars+=1,e.pending=t;continue;case" ":e.pending=t;continue;case"\\n":if(e.hr_chars<3)break;u(e,e.indent_len),e.renderer.add_token(e.renderer.data,22),e.renderer.end_token(e.renderer.data),E(e),e.hr_chars=0;continue}e.hr_chars=0}if(e.pending[0]!=="_"&&e.pending[1]===" "){A(e,23),g(e,2),o(e,t.slice(2));continue}break;case"`":if(e.pending.length<3){if(n==="`"){e.pending=t,e.fence_start=t.length;continue}e.fence_start=0;break}switch(n){case"`":e.pending.length===e.fence_start?(e.pending=t,e.fence_start=t.length):(i(e,2),E(e),e.fence_start=0,o(e,t));continue;case"\\n":{u(e,e.indent_len),i(e,10),e.pending.length>e.fence_start&&e.renderer.set_attr(e.renderer.data,L,e.pending.slice(e.fence_start)),E(e),e.token=101;continue}default:e.pending=t;continue}case"+":if(n!==" ")break;A(e,23),g(e,2);continue;case"0":case"1":case"2":case"3":case"4":case"5":case"6":case"7":case"8":case"9":if(e.pending[e.pending.length-1]==="."){if(n!==" ")break;A(e,24)&&e.pending!=="1."&&e.renderer.set_attr(e.renderer.data,f,e.pending.slice(0,-1)),g(e,e.pending.length+1);continue}else{let r=n.charCodeAt(0);if(r===46||N(r)){e.pending=t;continue}}break;case"|":l(e,e.blockquote_idx),i(e,27),i(e,28),e.pending="",o(e,n);continue}let s=t;if(e.token===21)e.token=e.tokens[e.len],e.renderer.add_token(e.renderer.data,21),e.renderer.end_token(e.renderer.data);else if(e.indent_len>=4){let r=0;for(;r<4;r+=1)if(e.indent[r]==="\\t"){r=r+1;break}s=e.indent.slice(r)+t,i(e,9)}else i(e,2);E(e),o(e,s);continue;case 27:if(e.table_state===1)switch(n){case"-":case" ":case"|":case":":e.pending=t;continue;case"\\n":e.table_state=2,e.pending="";continue;default:_(e),e.table_state=0;break}else switch(e.pending){case"|":i(e,28),e.pending="",o(e,n);continue;case"\\n":_(e),e.pending="",e.table_state=0,o(e,n);continue}break;case 28:switch(e.pending){case"":break;case"|":i(e,29),_(e),e.pending="",o(e,n);continue;case"\\n":_(e),e.table_state=Math.min(e.table_state+1,2),e.pending="",o(e,n);continue;default:i(e,29),o(e,n);continue}break;case 29:if(e.pending==="|"){a(e),_(e),e.pending="",o(e,n);continue}break;case 9:switch(t){case"\\n    ":case"\\n   \\t":case"\\n  \\t":case"\\n \\t":case"\\n\\t":e.text+="\\n",e.pending="";continue;case"\\n":case"\\n ":case"\\n  ":case"\\n   ":e.pending=t;continue;default:e.pending.length!==0?(a(e),_(e),e.pending=n):e.text+=n;continue}case 10:switch(n){case"`":e.pending=t;continue;case"\\n":if(t.length===e.fence_start+e.fence_end+1){a(e),_(e),e.pending="",e.fence_start=0,e.fence_end=0,e.token=101;continue}e.token=101;break;case" ":if(e.pending[0]==="\\n"){e.pending=t,e.fence_end+=1;continue}break}e.text+=e.pending,e.pending=n,e.fence_end=1;continue;case 11:switch(n){case"`":t.length===e.fence_start+ +(e.pending[0]===" ")?(a(e),_(e),e.pending="",e.fence_start=0):e.pending=t;continue;case"\\n":e.text+=e.pending,e.pending="",e.token=21,e.blockquote_idx=0,a(e);continue;case" ":e.text+=e.pending,e.pending=n;continue;default:e.text+=t,e.pending="";continue}case 103:switch(e.pending.length){case 0:if(n!=="[")break;e.pending=t;continue;case 1:if(n!==" "&&n!=="x")break;e.pending=t;continue;case 2:if(n!=="]")break;e.pending=t;continue;case 3:if(n!==" ")break;e.renderer.add_token(e.renderer.data,26),e.pending[1]==="x"&&e.renderer.set_attr(e.renderer.data,T,""),e.renderer.end_token(e.renderer.data),e.pending=" ";continue}e.token=e.tokens[e.len],e.pending="",o(e,t);continue;case 14:case 15:{let r="*",d=12;if(e.token===15&&(r="_",d=13),r===e.pending){if(a(e),r===n){_(e),e.pending="";continue}i(e,d),e.pending=n;continue}break}case 12:case 13:{let r="*",d=14;switch(e.token===13&&(r="_",d=15),e.pending){case r:r===n?e.tokens[e.len-1]===d?e.pending=t:(a(e),i(e,d),e.pending=""):(a(e),_(e),e.pending=n);continue;case r+r:let R=e.token;a(e),_(e),_(e),r!==n?(i(e,R),e.pending=n):e.pending="";continue}break}case 16:if(t==="~~"){a(e),_(e),e.pending="";continue}break;case 105:n==="\\n"?(a(e),i(e,30),e.pending=""):(e.token=e.tokens[e.len],e.pending[0]==="\\\\"?e.text+="[":e.text+="$$",e.pending="",o(e,n));continue;case 30:if(t==="\\\\]"||t==="$$"){a(e),_(e),e.pending="";continue}break;case 31:if(t==="\\\\)"||e.pending[0]==="$"){a(e),_(e),n===")"?e.pending="":e.pending=n;continue}break;case 102:t==="http://"||t==="https://"?(a(e),i(e,18),e.pending=t,e.text=t):"http:/"[e.pending.length]===n||"https:/"[e.pending.length]===n?e.pending=t:(e.token=e.tokens[e.len],o(e,n));continue;case 17:case 19:if(e.pending==="]"){a(e),n==="("?e.pending=t:(_(e),e.pending=n);continue}if(e.pending[0]==="]"&&e.pending[1]==="("){if(n===")"){let r=e.token===17?I:k,d=e.pending.slice(2);e.renderer.set_attr(e.renderer.data,r,d),_(e),e.pending=""}else e.pending+=n;continue}break;case 18:n===" "||n==="\\n"||n==="\\\\"?(e.renderer.set_attr(e.renderer.data,I,e.pending),a(e),_(e),e.pending=n):(e.text+=n,e.pending=t);continue;case 104:if(t.startsWith("<br")){if(t.length===3||n===" "||n==="/"&&(t.length===4||e.pending[e.pending.length-1]===" ")){e.pending=t;continue}if(n===">"){a(e),e.token=e.tokens[e.len],e.renderer.add_token(e.renderer.data,21),e.renderer.end_token(e.renderer.data),e.pending="";continue}}e.token=e.tokens[e.len],e.text+="<",e.pending=e.pending.slice(1),o(e,n);continue}switch(e.pending[0]){case"\\\\":if(e.token===19||e.token===30||e.token===31)break;switch(n){case"(":a(e),i(e,31),e.pending="";continue;case"[":e.token=105,e.pending=t;continue;case"\\n":e.pending=n;continue;default:let s=n.charCodeAt(0);e.pending="",e.text+=N(s)||s>=65&&s<=90||s>=97&&s<=122?t:n;continue}case"\\n":switch(e.token){case 19:case 30:case 31:break;case 3:case 4:case 5:case 6:case 7:case 8:a(e),l(e,e.blockquote_idx),e.blockquote_idx=0,e.pending=n;continue;default:a(e),e.pending=n,e.token=21,e.blockquote_idx=0;continue}break;case"<":if(e.token!==19&&e.token!==30&&e.token!==31){a(e),e.pending=t,e.token=104;continue}break;case"`":if(e.token===19)break;n==="`"?(e.fence_start+=1,e.pending=t):(e.fence_start+=1,a(e),i(e,11),e.text=n===" "||n==="\\n"?"":n,e.pending="");continue;case"_":case"*":{if(e.token===19||e.token===30||e.token===31||e.token===14)break;let s=12,r=14,d=e.pending[0];if(d==="_"&&(s=13,r=15),e.pending.length===1){if(d===n){e.pending=t;continue}if(n!==" "&&n!=="\\n"){a(e),i(e,s),e.pending=n;continue}}else{if(d===n){a(e),i(e,r),i(e,s),e.pending="";continue}if(n!==" "&&n!=="\\n"){a(e),i(e,r),e.pending=n;continue}}break}case"~":if(e.token!==19&&e.token!==16){if(e.pending==="~"){if(n==="~"){e.pending=t;continue}}else if(n!==" "&&n!=="\\n"){a(e),i(e,16),e.pending=n;continue}}break;case"$":if(e.token!==19&&e.token!==16&&e.pending==="$")if(n==="$"){e.token=105,e.pending=t;continue}else{if(se(n.charCodeAt(0)))break;a(e),i(e,31),e.pending=n;continue}break;case"[":if(e.token!==19&&e.token!==17&&e.token!==30&&e.token!==31&&n!=="]"){a(e),i(e,17),e.pending=n;continue}break;case"!":if(e.token!==19&&n==="["){a(e),i(e,19),e.pending="";continue}break;case" ":if(e.pending.length===1&&n===" ")continue;break}if(e.token!==19&&e.token!==17&&e.token!==30&&e.token!==31&&n==="h"&&(e.pending===" "||e.pending==="")){e.text+=e.pending,e.pending=n,e.token=102;continue}e.text+=e.pending,e.pending=n}a(e)}function _e(e){return{add_token:oe,end_token:de,add_text:Ee,set_attr:le,data:{nodes:[e,,,,,],index:0}}}function oe(e,c){let n=e.nodes[e.index],t;switch(c){case 1:return;case 20:t=document.createElement("blockquote");break;case 2:t=document.createElement("p");break;case 21:t=document.createElement("br");break;case 22:t=document.createElement("hr");break;case 3:t=document.createElement("h1");break;case 4:t=document.createElement("h2");break;case 5:t=document.createElement("h3");break;case 6:t=document.createElement("h4");break;case 7:t=document.createElement("h5");break;case 8:t=document.createElement("h6");break;case 12:case 13:t=document.createElement("em");break;case 14:case 15:t=document.createElement("strong");break;case 16:t=document.createElement("s");break;case 11:t=document.createElement("code");break;case 18:case 17:t=document.createElement("a");break;case 19:t=document.createElement("img");break;case 23:t=document.createElement("ul");break;case 24:t=document.createElement("ol");break;case 25:t=document.createElement("li");break;case 26:let s=t=document.createElement("input");s.type="checkbox",s.disabled=!0;break;case 9:case 10:n=n.appendChild(document.createElement("pre")),t=document.createElement("code");break;case 27:t=document.createElement("table");break;case 28:switch(n.children.length){case 0:n=n.appendChild(document.createElement("thead"));break;case 1:n=n.appendChild(document.createElement("tbody"));break;default:n=n.children[1]}t=document.createElement("tr");break;case 29:t=document.createElement(n.parentElement?.tagName==="THEAD"?"th":"td");break;case 30:t=document.createElement("equation-block");break;case 31:t=document.createElement("equation-inline");break}e.nodes[++e.index]=n.appendChild(t)}function de(e){e.index-=1}function Ee(e,c){e.nodes[e.index].appendChild(document.createTextNode(c))}function le(e,c,n){e.nodes[e.index].setAttribute(ee(c),n)}window.smd={default_renderer:_e,parser:ae,parser_write:o,parser_end:ce};
    """

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
            self.pendingDismissWorkItem?.cancel()
            self.pendingDismissWorkItem = nil
            self.ensureWindow()
            self.webView?.loadHTMLString(self.loadingHTML(), baseURL: nil)
            self.present()
        }
    }

    func showResponse(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pendingDismissWorkItem?.cancel()
            self.pendingDismissWorkItem = nil
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

    func signalStreamEnd() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.webView?.evaluateJavaScript("if(typeof finalize==='function')finalize()", completionHandler: nil)
            if self.isStudyMode {
                self.studyTextField?.stringValue = ""
                self.studyTextField?.isEnabled = true
                self.overlayWindow?.makeFirstResponder(self.studyTextField)
            }
        }
    }

    // MARK: - Follow-Up Conversation

    func storeConversationContext(screenshot: String, initialPrompt: String?) {
        currentScreenshot = screenshot
        conversationHistory.removeAll()
    }

    func addTurnToHistory(question: String, completion: @escaping () -> Void) {
        // Read rawMarkdown from JS to capture the answer
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("rawMarkdown") { result, _ in
                let answer = (result as? String) ?? ""
                self?.conversationHistory.append((question: question, answer: answer))
                completion()
            }
        }
    }

    func buildContextPrompt(newQuestion: String) -> String {
        // Cap at last 5 turns
        let recentHistory = conversationHistory.suffix(5)
        if recentHistory.isEmpty {
            return newQuestion
        }
        var parts = ["Previous conversation about this screenshot:\n"]
        for turn in recentHistory {
            parts.append("Q: \(turn.question)")
            parts.append("A: \(turn.answer)\n")
        }
        parts.append("New follow-up question: \(newQuestion)")
        parts.append("Please continue analyzing the same screenshot to answer this follow-up.")
        return parts.joined(separator: "\n")
    }

    func prepareFollowUp(question: String) {
        let escaped = question
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("startFollowUp(`\(escaped)`)", completionHandler: nil)
        }
    }

    var storedScreenshot: String? { currentScreenshot }

    func showUsageWarning(remaining: Int) {
        DispatchQueue.main.async { [weak self] in
            let text = "\(remaining) free remaining"
            let js = "if(document.querySelector('.usage-warn')){}else{var w=document.createElement('div');w.className='usage-warn';w.style.cssText='position:fixed;bottom:28px;left:0;right:0;text-align:center;padding:4px;font-size:11px;color:var(--loading-text);opacity:0.7;';w.textContent='\(text)';document.body.appendChild(w);}"
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
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
        webView?.evaluateJavaScript("appendChunk(`\(escaped)`)", completionHandler: nil)
    }

    /// Safe JS evaluation — queues calls until HTML has finished loading
    private func evaluateJSSafe(_ js: String) {
        if isPageReady {
            webView?.evaluateJavaScript(js, completionHandler: nil)
        } else {
            pendingJSCalls.append(js)
        }
    }

    private func flushPendingJSCalls() {
        for js in pendingJSCalls {
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        pendingJSCalls.removeAll()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageReady = true
        for chunk in chunkQueue { appendChunkDirect(chunk) }
        chunkQueue.removeAll()
        flushPendingJSCalls()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isPageReady = true
        for chunk in chunkQueue { appendChunkDirect(chunk) }
        chunkQueue.removeAll()
        flushPendingJSCalls()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isPageReady = true
        for chunk in chunkQueue { appendChunkDirect(chunk) }
        chunkQueue.removeAll()
        flushPendingJSCalls()
    }

    // Intercept link clicks and open in default browser
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

    func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.ensureWindow()
            self.webView?.loadHTMLString(self.errorHTML(message), baseURL: nil)
            self.present()
        }
    }

    /// Callback for Study Mode pause/resume toggle
    var onStudyPauseToggle: (() -> Void)?
    /// Callback for Study Mode stop
    var onStudyStop: (() -> Void)?
    /// Callback for Auto Solve toggle
    var onAutoSolveToggle: (() -> Void)?
    /// Callback for suggestion accept / dismiss
    var onSuggestionAccept: (() -> Void)?
    var onSuggestionDismiss: (() -> Void)?
    func injectPromptAndSubmit(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isStudyMode, let field = self.studyTextField {
                field.stringValue = "Thinking\u{2026}"
                field.isEnabled = false
                self.onPromptSubmit?(text)
            } else {
                let escaped = text
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                    .replacingOccurrences(of: "\n", with: "\\n")
                self.webView?.evaluateJavaScript("""
                    var input = document.getElementById('promptInput');
                    if (input) {
                        input.disabled = true;
                        input.value = 'Thinking\\u2026';
                        window.webkit.messageHandlers.overlay.postMessage({action:'promptSubmit', prompt:'\(escaped)'});
                    }
                """, completionHandler: nil)
            }
        }
    }
    /// Whether currently showing Study Mode prompt
    private var isStudyMode = false

    // MARK: - Study Suggestion Popup

    func showStudySuggestion(text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.dismissPopup()
            self.createPopup(width: 340, height: 130, position: .topRight)
            self.popupWebView?.loadHTMLString(self.suggestionHTML(text: text), baseURL: nil)
            self.popupPanel?.alphaValue = 0
            self.popupPanel?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                self.popupPanel?.animator().alphaValue = 1.0
            }
            // Auto-dismiss after 10s
            self.popupDismissTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                self?.onSuggestionDismiss?()
                self?.dismissPopup()
            }
        }
    }

    func showStudySummary(text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.dismissPopup()
            self.createPopup(width: 300, height: 70, position: .topCenter)
            self.popupWebView?.loadHTMLString(self.summaryHTML(text: text), baseURL: nil)
            self.popupPanel?.alphaValue = 0
            self.popupPanel?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self.popupPanel?.animator().alphaValue = 1.0
            }
            // Auto-dismiss after 2s
            self.popupDismissTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                self?.dismissPopup()
            }
        }
    }

    // MARK: - Auto Solve Results (Legacy compat — old coordinator still calls these)

    func showAutoSolveResults(count: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.expandStudyBar()
            self.webView?.evaluateJavaScript("showAutosolvePanel(\(count))", completionHandler: nil)
        }
    }

    func showAllAutoSolveAnswers(answers: [AutoSolveAnswer], currentPage: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.resizeForStudyContent(questionCount: answers.count)
            let done = answers.filter { !$0.solving }.count
            let total = answers.count
            let headerText = total == 0
                ? "Auto Solve — all solved"
                : "Auto Solve — \(done)/\(total) answers • Page \(currentPage)"

            let jsonEntries = answers.map { a -> String in
                let esc = { (s: String) -> String in
                    s.replacingOccurrences(of: "\\", with: "\\\\")
                     .replacingOccurrences(of: "\"", with: "\\\"")
                     .replacingOccurrences(of: "\n", with: "\\n")
                     .replacingOccurrences(of: "\r", with: "\\r")
                }
                return """
                {"id":"\(esc(a.id))","latex":"\(esc(a.latex))","copyable":"\(esc(a.copyable))","isMC":\(a.isMC),"failed":\(a.failed),"solving":\(a.solving),"page":\(a.page)}
                """
            }
            let jsonStr = "[" + jsonEntries.joined(separator: ",") + "]"
            let hdrEsc = headerText.replacingOccurrences(of: "\\", with: "\\\\")
                                   .replacingOccurrences(of: "\"", with: "\\\"")

            self.webView?.evaluateJavaScript("refreshAutoSolveUI(\"\(hdrEsc)\", \(jsonStr))") { _, error in
                if let error = error { print("[AutoSolve] refreshAutoSolveUI error: \(error)") }
            }
        }
    }

    func replaceAutoSolveAnswer(id: String, latex: String, copyable: String, isMC: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let esc = { (s: String) -> String in
                s.replacingOccurrences(of: "\\", with: "\\\\")
                 .replacingOccurrences(of: "\"", with: "\\\"")
                 .replacingOccurrences(of: "\n", with: "\\n")
                 .replacingOccurrences(of: "\r", with: "\\r")
            }
            let jsonStr = """
            {"id":"\(esc(id))","latex":"\(esc(latex))","copyable":"\(esc(copyable))","isMC":\(isMC),"failed":false}
            """
            self.webView?.evaluateJavaScript("replaceAutosolveAnswer && replaceAutosolveAnswer(\(jsonStr))") { _, error in
                if let error = error { print("[AutoSolve] replaceAutosolveAnswer error: \(error)") }
            }
        }
    }

    func clearAutoSolveResults() {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("clearAutosolvePanel && clearAutosolvePanel()", completionHandler: nil)
        }
    }

    // MARK: - Study Mode V2 API

    /// Refresh the full study UI with question data from SessionMemory
    func refreshStudyUI(statusText: String, dotState: String, questions: [QuestionRecord]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Only resize in Solve mode — Learn mode controls its own height
            if StudyCoordinator.shared.currentMode == .solve {
                self.resizeForStudyContent(questionCount: questions.count)
            }

            let esc = { (s: String) -> String in
                s.replacingOccurrences(of: "\\", with: "\\\\")
                 .replacingOccurrences(of: "\"", with: "\\\"")
                 .replacingOccurrences(of: "\n", with: "\\n")
                 .replacingOccurrences(of: "\r", with: "\\r")
            }

            let jsonEntries = questions.map { q -> String in
                let stepsJson: String
                if let steps = q.steps {
                    let stepsArr = steps.map { s in
                        "{\"stepNumber\":\(s.stepNumber),\"latex\":\"\(esc(s.latex))\",\"explanation\":\"\(esc(s.explanation))\",\"isKeyStep\":\(s.isKeyStep)}"
                    }
                    stepsJson = "[" + stepsArr.joined(separator: ",") + "]"
                } else {
                    stepsJson = "null"
                }
                return "{\"id\":\"\(esc(q.id))\",\"state\":\"\(q.state.rawValue)\",\"latex\":\"\(esc(q.answer?.latex ?? ""))\",\"copyable\":\"\(esc(q.answer?.copyable ?? ""))\",\"page\":\(q.detectedPage),\"steps\":\(stepsJson)}"
            }
            let jsonStr = "[" + jsonEntries.joined(separator: ",") + "]"
            let statusEsc = esc(statusText)

            self.evaluateJSSafe("refreshStudyUI(\"\(statusEsc)\", \"\(dotState)\", \(jsonStr))")
        }
    }

    /// Update a single question row
    func updateQuestionRow(_ question: QuestionRecord) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let esc = { (s: String) -> String in
                s.replacingOccurrences(of: "\\", with: "\\\\")
                 .replacingOccurrences(of: "\"", with: "\\\"")
                 .replacingOccurrences(of: "\n", with: "\\n")
                 .replacingOccurrences(of: "\r", with: "\\r")
            }
            let jsonStr = "{\"id\":\"\(esc(question.id))\",\"state\":\"\(question.state.rawValue)\",\"latex\":\"\(esc(question.answer?.latex ?? ""))\",\"copyable\":\"\(esc(question.answer?.copyable ?? ""))\",\"page\":\(question.detectedPage),\"steps\":null}"
            self.evaluateJSSafe("updateQuestionRow(\(jsonStr))")
        }
    }

    /// Update steps for a question after lazy load
    func updateQuestionSteps(questionId: String, steps: [SolutionStep]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let esc = { (s: String) -> String in
                s.replacingOccurrences(of: "\\", with: "\\\\")
                 .replacingOccurrences(of: "\"", with: "\\\"")
                 .replacingOccurrences(of: "\n", with: "\\n")
                 .replacingOccurrences(of: "\r", with: "\\r")
            }
            let stepsArr = steps.map { s in
                "{\"stepNumber\":\(s.stepNumber),\"latex\":\"\(esc(s.latex))\",\"explanation\":\"\(esc(s.explanation))\",\"isKeyStep\":\(s.isKeyStep)}"
            }
            let jsonStr = "[" + stepsArr.joined(separator: ",") + "]"
            let idEsc = esc(questionId)
            self.evaluateJSSafe("updateSteps(\"\(idEsc)\", \(jsonStr))")
        }
    }

    /// Update just the status bar text and dot
    func updateStudyStatus(text: String, dotState: String) {
        DispatchQueue.main.async { [weak self] in
            let esc = text.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "\"", with: "\\\"")
            self?.evaluateJSSafe("updateStatus(\"\(esc)\", \"\(dotState)\")")
        }
    }

    /// Show session summary card
    func showStudySessionSummary(duration: String, solved: Int, pages: Int, topics: [String]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let esc = { (s: String) -> String in
                s.replacingOccurrences(of: "\\", with: "\\\\")
                 .replacingOccurrences(of: "\"", with: "\\\"")
            }
            let topicsJson = "[" + topics.map { "\"\(esc($0))\"" }.joined(separator: ",") + "]"
            let json = "{\"duration\":\"\(esc(duration))\",\"solved\":\(solved),\"pages\":\(pages),\"topics\":\(topicsJson)}"
            self.expandStudyBar()
            self.evaluateJSSafe("showSessionSummary(\(json))")
        }
    }

    /// Show explain card in learn mode
    func showExplainCard(_ explanation: ConceptExplanation) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let esc = { (s: String) -> String in
                s.replacingOccurrences(of: "\\", with: "\\\\")
                 .replacingOccurrences(of: "\"", with: "\\\"")
                 .replacingOccurrences(of: "\n", with: "\\n")
            }
            var json = "{\"conceptName\":\"\(esc(explanation.conceptName))\",\"conceptExplanation\":\"\(esc(explanation.conceptExplanation))\""
            if let formula = explanation.formulaLatex {
                json += ",\"formulaLatex\":\"\(esc(formula))\""
            }
            if let strategy = explanation.strategy {
                json += ",\"strategy\":\"\(esc(strategy))\""
            }
            json += "}"
            self.expandStudyBar()
            self.evaluateJSSafe("showExplainCard(\(json))")
        }
    }

    /// Show work check feedback in learn mode
    func showCheckFeedback(_ feedback: WorkCheckFeedback) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let esc = { (s: String) -> String in
                s.replacingOccurrences(of: "\\", with: "\\\\")
                 .replacingOccurrences(of: "\"", with: "\\\"")
                 .replacingOccurrences(of: "\n", with: "\\n")
            }
            var json = "{\"isCorrect\":\(feedback.isCorrect),\"correctnessPercentage\":\(feedback.correctnessPercentage),\"feedback\":\"\(esc(feedback.feedback))\""
            if let enc = feedback.encouragement {
                json += ",\"encouragement\":\"\(esc(enc))\""
            }
            json += "}"
            self.expandStudyBar()
            self.evaluateJSSafe("showCheckFeedback(\(json))")
        }
    }

    /// Show user input echo bubble above the response area
    func showUserInputEcho(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            let esc = text.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "\"", with: "\\\"")
                          .replacingOccurrences(of: "\n", with: "\\n")
            self?.evaluateJSSafe("showUserInput(\"\(esc)\")")
        }
    }

    /// Resize overlay to fit current content without rebuilding rows
    func resizeForCurrentContent() {
        guard StudyCoordinator.shared.currentMode == .solve else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.webView?.evaluateJavaScript("document.getElementById('questionsContainer').children.length") { [weak self] result, _ in
                if let count = result as? Int {
                    self?.resizeForStudyContent(questionCount: count)
                }
            }
        }
    }

    /// Resize overlay to Learn mode height — compact with input field
    func resizeToLearnMode() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isStudyMode, let window = self.overlayWindow else { return }

            self.webView?.evaluateJavaScript("""
                (function() {
                    var el = document.getElementById('learnContent');
                    if (!el || el.innerHTML.trim() === '') return 0;
                    return el.scrollHeight;
                })()
            """) { [weak self] result, _ in
                guard let self = self, let window = self.overlayWindow else { return }

                let contentHeight = (result as? Int).map { CGFloat($0) } ?? 0
                let statusBarHeight: CGFloat = 28
                let inputHeight: CGFloat = 48
                let padding: CGFloat = 16

                let targetHeight: CGFloat
                if contentHeight > 0 {
                    let total = statusBarHeight + contentHeight + inputHeight + padding
                    let maxHeight = (NSScreen.main?.frame.height ?? 900) * 0.65
                    targetHeight = min(total, maxHeight)
                } else {
                    targetHeight = self.studyBarCompactHeight
                }

                guard abs(window.frame.height - targetHeight) > 4 else { return }

                let frame = window.frame
                window.setFrame(
                    NSRect(x: frame.origin.x, y: frame.origin.y,
                           width: frame.width, height: targetHeight),
                    display: true, animate: true
                )
            }
        }
    }

    /// Show loading state in learn content area
    func showLearnLoading() {
        DispatchQueue.main.async { [weak self] in
            self?.evaluateJSSafe("""
                document.getElementById('learnContent').innerHTML = '<div class="steps-loading">Thinking...</div>';
                document.getElementById('learnContent').style.display = '';
                document.getElementById('questionsContainer').style.display = 'none';
                showContentArea();
            """)
        }
    }

    /// Show error message in learn content
    func showLearnError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            let esc = message.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
            self?.evaluateJSSafe("""
                document.getElementById('learnContent').innerHTML = '<div style="padding:12px 14px;color:var(--text-secondary);font:400 12px/1.5 -apple-system,sans-serif;">\(esc)</div>';
                showContentArea();
            """)
        }
    }

    /// Prepare learn content for streaming (freeform questions)
    func showLearnStreamingStart() {
        DispatchQueue.main.async { [weak self] in
            self?.evaluateJSSafe("""
                document.getElementById('learnContent').innerHTML = '';
                document.getElementById('learnContent').style.display = '';
                document.getElementById('questionsContainer').style.display = 'none';
                showContentArea();
            """)
        }
    }

    /// Finalize after streaming completes
    func finalizeStream() {
        DispatchQueue.main.async { [weak self] in
            self?.evaluateJSSafe("finalize()")
            if self?.isStudyMode == true {
                self?.studyTextField?.stringValue = ""
                self?.studyTextField?.isEnabled = true
                self?.overlayWindow?.makeFirstResponder(self?.studyTextField)
            }
        }
    }

    /// Show quiz card with practice questions
    func showQuizCard(_ questions: [APIService.StudyQuizQuestion]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let esc = { (s: String) -> String in
                s.replacingOccurrences(of: "\\", with: "\\\\")
                 .replacingOccurrences(of: "\"", with: "\\\"")
                 .replacingOccurrences(of: "\n", with: "\\n")
            }
            let jsonEntries = questions.map { q in
                var entry = "{\"quizId\":\"\(esc(q.quizId))\",\"questionLatex\":\"\(esc(q.questionLatex))\",\"correctAnswerLatex\":\"\(esc(q.correctAnswerLatex))\",\"correctAnswerCopyable\":\"\(esc(q.correctAnswerCopyable))\""
                if let hint = q.hint { entry += ",\"hint\":\"\(esc(hint))\"" }
                entry += "}"
                return entry
            }
            let json = "[" + jsonEntries.joined(separator: ",") + "]"
            self.expandStudyBar()
            self.evaluateJSSafe("showQuizCard(\(json))")
        }
    }

    /// Hide the native text field (Solve mode — no input needed)
    func hideStudyTextField() {
        DispatchQueue.main.async { [weak self] in
            self?.studyPromptContainer?.isHidden = true
        }
    }

    /// Show the native text field (Learn mode — input visible)
    func showStudyTextField() {
        DispatchQueue.main.async { [weak self] in
            self?.studyPromptContainer?.isHidden = false
            self?.overlayWindow?.makeFirstResponder(self?.studyTextField)
        }
    }

    /// Show placeholder shimmer rows while identify is in progress
    func showIdentifyingPlaceholders(count: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var js = "document.getElementById('questionsContainer').innerHTML = '';"
            for i in 0..<count {
                js += """
                (function() {
                    var row = document.createElement('div');
                    row.className = 'question-row solving';
                    row.setAttribute('data-id', 'placeholder-\(i)');
                    var header = document.createElement('div');
                    header.className = 'row-header';
                    var num = document.createElement('span');
                    num.className = 'q-number';
                    num.innerHTML = '&nbsp;';
                    header.appendChild(num);
                    var answer = document.createElement('span');
                    answer.className = 'q-answer';
                    answer.textContent = '\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0\\u00A0';
                    header.appendChild(answer);
                    row.appendChild(header);
                    row.style.opacity = '0';
                    row.style.transform = 'translateX(12px)';
                    row.style.transition = 'opacity 0.25s ease, transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)';
                    document.getElementById('questionsContainer').appendChild(row);
                    setTimeout(function() { row.style.opacity = '1'; row.style.transform = 'translateX(0)'; }, \(i) * 60);
                })();
                """
            }
            js += "document.getElementById('contentArea').classList.add('visible');"
            self.evaluateJSSafe(js)
        }
    }

    // MARK: - Resize for study content

    private func resizeForStudyContent(questionCount: Int) {
        guard isStudyMode, let window = overlayWindow else { return }
        let rowHeight: CGFloat = 44
        let headerHeight: CGFloat = 28
        let paddingHeight: CGFloat = 16
        // In solve mode, no input field — content extends to bottom
        let inputHeight: CGFloat = StudyCoordinator.shared.currentMode == .solve ? 0 : 48
        let contentHeight = headerHeight + (CGFloat(questionCount) * rowHeight) + inputHeight + paddingHeight
        let maxHeight = (NSScreen.main?.frame.height ?? 900) * 0.65
        let newHeight = max(CGFloat(76), min(contentHeight, maxHeight))
        guard abs(window.frame.height - newHeight) > 4 else { return }
        let frame = window.frame
        window.setFrame(NSRect(x: frame.origin.x, y: frame.origin.y,
                               width: frame.width, height: newHeight),
                        display: true, animate: true)
    }

    func dismissPopup() {
        popupDismissTimer?.invalidate()
        popupDismissTimer = nil
        guard let panel = popupPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.popupWebView?.configuration.userContentController.removeAllScriptMessageHandlers()
            self?.popupWebView = nil
            panel.orderOut(nil)
            self?.popupPanel = nil
        })
    }

    private enum PopupPosition { case topRight, topCenter }

    private func createPopup(width: CGFloat, height: CGFloat, position: PopupPosition) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin: NSPoint
        switch position {
        case .topRight:
            origin = NSPoint(x: screen.maxX - width - 16, y: screen.maxY - height - 16)
        case .topCenter:
            origin = NSPoint(x: screen.midX - width / 2, y: screen.maxY - height - 16)
        }

        let frame = NSRect(origin: origin, size: NSSize(width: width, height: height))
        let panel = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
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

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "overlay")

        let wv = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = Theme.nsOverlayBg(NSApp.effectiveAppearance).cgColor
        container.addSubview(wv)

        panel.contentView = container
        self.popupWebView = wv
        self.popupPanel = panel
    }

    private let studyBarCompactHeight: CGFloat = 76
    private let studyBarExpandedHeight: CGFloat = 420
    private let studyBarWidth: CGFloat = 520

    // Study Mode V2 callbacks
    var onStudyModeSwitch: ((String) -> Void)?  // "solve" or "learn"
    var onStudyExpandSteps: ((String) -> Void)?  // question ID
    var onStudyCollapseSteps: ((String) -> Void)?  // question ID

    func showPromptInput(studyMode: Bool = false, placeholder: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Cancel any pending delayed dismiss to prevent it from killing this new overlay
            self.pendingDismissWorkItem?.cancel()
            self.pendingDismissWorkItem = nil
            print("[Overlay] showPromptInput called (studyMode=\(studyMode)). overlayWindow is \(self.overlayWindow == nil ? "nil" : "non-nil")")
            self.isPromptMode = true
            self.isStudyMode = studyMode
            if studyMode {
                self.ensureStudyBarWindow()
                self.webView?.loadHTMLString(self.studyModeBarHTML(), baseURL: nil)
            } else {
                self.ensurePromptWindow()
                self.webView?.loadHTMLString(self.promptInputHTML(placeholder: placeholder), baseURL: nil)
            }
            self.presentPrompt()
        }
    }

    /// Expand the study bar to show a streamed answer
    /// Expand upward: keep bottom edge fixed, grow height upward
    func expandStudyBar() {
        guard isStudyMode, let window = overlayWindow else { return }
        let frame = window.frame
        let newHeight = studyBarExpandedHeight
        // Keep bottom edge (origin.y) fixed — window grows upward in macOS coords
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: newHeight
        )
        window.minSize = NSSize(width: minWidth, height: studyBarCompactHeight)
        window.maxSize = NSSize(width: 9999, height: 9999)
        window.setFrame(newFrame, display: true, animate: true)
        evaluateJSSafe("showResponseArea()")
    }

    /// Collapse downward: keep bottom edge fixed, shrink height
    func collapseStudyBar() {
        guard isStudyMode, let window = overlayWindow else { return }
        let frame = window.frame
        let newHeight = studyBarCompactHeight
        // Keep bottom edge (origin.y) fixed — window shrinks downward
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: newHeight
        )
        window.setFrame(newFrame, display: true, animate: true)
        window.minSize = NSSize(width: minWidth, height: studyBarCompactHeight)
        window.maxSize = NSSize(width: 9999, height: studyBarCompactHeight)
        evaluateJSSafe("hideResponseArea()")
        // Re-enable native prompt field
        studyTextField?.stringValue = ""
        studyTextField?.isEnabled = true
        overlayWindow?.makeFirstResponder(studyTextField)
    }

    // FIX #6: Properly tear down webview to prevent retain cycle
    func dismiss() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("[Overlay] dismiss() called. overlayWindow is \(self.overlayWindow == nil ? "nil" : "non-nil")")
            // Cancel any pending delayed dismiss
            self.pendingDismissWorkItem?.cancel()
            self.pendingDismissWorkItem = nil
            // Don't overwrite saved position with the compact prompt frame
            if !self.isPromptMode {
                if let f = self.overlayWindow?.frame { self.savedFrame = f }
            }
            self.isPromptMode = false
            self.isStudyMode = false
            self.conversationHistory.removeAll()
            self.currentScreenshot = nil
            self.onFollowUpSubmit = nil
            self.overlayWindow?.orderOut(nil)
            self.stopResize()
            self.stopDrag()

            HotkeyService.shared.unregisterEsc()

            // Remove theme observer
            DistributedNotificationCenter.default().removeObserver(self)

            // Break the retain cycle: WKUserContentController -> self
            self.webView?.configuration.userContentController.removeAllScriptMessageHandlers()
            self.webView?.navigationDelegate = nil
            self.webView?.removeFromSuperview()
            self.webView = nil
            self.studyTextField = nil
            self.studyPromptBg = nil
            self.studyPromptContainer = nil
            self.overlayWindow = nil
            self.isPageReady = false
            self.chunkQueue.removeAll()
            self.pendingJSCalls.removeAll()
            self.preMinimizeFrame = nil
            self.restorePill?.orderOut(nil)
            self.restorePill = nil

            print("[Overlay] Dismissed and cleaned up")
        }
    }

    /// Schedule a delayed dismiss that can be cancelled if a new overlay is shown
    func dismissAfterDelay(_ seconds: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        pendingDismissWorkItem?.cancel()
        pendingDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    // MARK: - Minimize / Restore

    private func minimizeOverlay() {
        guard let window = overlayWindow else { return }
        preMinimizeFrame = window.frame
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Animate window down to a tiny rect at bottom-center
        let pillWidth: CGFloat = 140
        let pillHeight: CGFloat = 4
        let targetFrame = NSRect(
            x: screen.midX - pillWidth / 2,
            y: screen.minY,
            width: pillWidth,
            height: pillHeight
        )
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(targetFrame, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            window.alphaValue = 1
            self?.showRestorePill()
        })
    }

    private func showRestorePill() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let pillWidth: CGFloat = 140
        let pillHeight: CGFloat = 32
        let pillFrame = NSRect(
            x: screen.midX - pillWidth / 2,
            y: screen.minY + 8,
            width: pillWidth,
            height: pillHeight
        )

        let pill = NSPanel(
            contentRect: pillFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        pill.level = .floating
        pill.isOpaque = false
        pill.backgroundColor = .clear
        pill.hasShadow = true
        pill.isMovableByWindowBackground = false
        pill.hidesOnDeactivate = false
        pill.isFloatingPanel = true
        pill.isReleasedWhenClosed = false
        pill.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let btn = NSButton(frame: NSRect(origin: .zero, size: pillFrame.size))
        btn.title = "Presto AI"
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = pillHeight / 2
        btn.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.92).cgColor
        btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        btn.contentTintColor = NSColor(white: 0.85, alpha: 1)
        btn.target = self
        btn.action = #selector(restoreFromPill)

        // Hover tracking
        let area = NSTrackingArea(rect: btn.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: btn, userInfo: nil)
        btn.addTrackingArea(area)

        pill.contentView = btn
        pill.alphaValue = 0
        pill.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            pill.animator().alphaValue = 1
        }

        self.restorePill = pill
    }

    @objc private func restoreFromPill() {
        // Fade out pill
        guard let pill = restorePill else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            pill.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            pill.orderOut(nil)
            self?.restorePill = nil
        })

        // Restore overlay window
        guard let window = overlayWindow, let frame = preMinimizeFrame else { return }
        window.setFrame(frame, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        preMinimizeFrame = nil
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
        case "dragStart": startDrag()
        case "dragEnd":
            stopDrag()
            if let f = overlayWindow?.frame { savedFrame = f }
        case "promptSubmit":
            if let prompt = dict["prompt"] as? String, !prompt.isEmpty {
                onPromptSubmit?(prompt)
            }
        case "followUpSubmit":
            if let prompt = dict["prompt"] as? String, !prompt.isEmpty {
                onFollowUpSubmit?(prompt)
            }
        case "studyPause":
            onStudyPauseToggle?()
        case "studyStop":
            onStudyStop?()
        case "studyAutoSolve":
            onAutoSolveToggle?()
        case "studyCollapse":
            collapseStudyBar()
        case "studyModeSwitch":
            if let mode = dict["mode"] as? String {
                onStudyModeSwitch?(mode)
            }
        case "studyExpandSteps":
            if let id = dict["id"] as? String {
                onStudyExpandSteps?(id)
            }
        case "studyCollapseSteps":
            if let id = dict["id"] as? String {
                onStudyCollapseSteps?(id)
            }
        case "suggestionAccept":
            dismissPopup()
            onSuggestionAccept?()
        case "suggestionDismiss":
            dismissPopup()
            onSuggestionDismiss?()
        case "nudgeAccepted":
            if let id = dict["id"] as? String {
                StudyCoordinator.shared.recordUserActivity()
                StudyCoordinator.shared.handleExplainIntent(questionId: id)
            }
        case "quizAnswer":
            break // tracked client-side only
        case "autoSolveResolve":
            if let id = dict["id"] as? String {
                StudyCoordinator.shared.resolveQuestion(id: id)
            }
        case "copy":
            if let text = dict["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        case "minimize":
            minimizeOverlay()
        default: break
        }
    }

    // MARK: - Drag via global NSEvent monitor

    private func startDrag() {
        guard let window = overlayWindow else { return }
        dragStartOrigin = window.frame.origin
        dragStartMouse = NSEvent.mouseLocation

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self = self, let window = self.overlayWindow else { return }

            if event.type == .leftMouseUp {
                self.stopDrag()
                self.savedFrame = window.frame
                return
            }

            let cur = NSEvent.mouseLocation
            let dx = cur.x - self.dragStartMouse.x
            let dy = cur.y - self.dragStartMouse.y

            let newOrigin = NSPoint(
                x: self.dragStartOrigin.x + dx,
                y: self.dragStartOrigin.y + dy
            )
            window.setFrameOrigin(newOrigin)
        }

        // Local monitor catches events on our own window
        dragLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { event in
            handler(event)
            return event
        }
        // Global monitor catches events if mouse leaves our window
        dragGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            handler: handler
        )
    }

    private func stopDrag() {
        if let m = dragLocalMonitor { NSEvent.removeMonitor(m); dragLocalMonitor = nil }
        if let m = dragGlobalMonitor { NSEvent.removeMonitor(m); dragGlobalMonitor = nil }
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
        if let saved = savedFrame, let clamped = clampToScreen(saved) {
            frame = clamped
        } else {
            frame = defaultFrame()
        }
        createWindow(frame: frame)
    }

    private func ensureStudyBarWindow() {
        print("[Overlay] ensureStudyBarWindow called. overlayWindow is \(overlayWindow == nil ? "nil" : "non-nil")")
        if overlayWindow != nil { return }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = min(studyBarWidth, screen.width - 32)
        let height = studyBarCompactHeight
        let frame = NSRect(
            x: screen.maxX - width - 16,
            y: screen.minY + 16,
            width: width,
            height: height
        )
        createWindow(frame: frame)
        overlayWindow?.minSize = NSSize(width: minWidth, height: studyBarCompactHeight)
        overlayWindow?.maxSize = NSSize(width: 9999, height: studyBarCompactHeight)

        // Add native NSTextField for the prompt input — stays pinned during animation
        guard let container = overlayWindow?.contentView else { return }

        // WKWebView stays full-size (fills entire window) — its HTML body background
        // provides uniform transparency. The native text field floats on top at the bottom.
        // WKWebView already has autoresizingMask = [.width, .height] from createWindow().

        // Prompt container pinned to bottom — .maxYMargin means top margin stretches
        // No background — the WKWebView beneath provides the frosted glass look
        let promptContainer = NSView(frame: NSRect(x: 0, y: 0, width: width, height: nativePromptHeight))
        promptContainer.autoresizingMask = [.width, .maxYMargin]

        // Styled background (matches CSS .prompt-field styling)
        let bgHeight: CGFloat = 36
        let bgY: CGFloat = (nativePromptHeight - bgHeight) / 2
        let bgView = NSView(frame: NSRect(x: 12, y: bgY, width: width - 24, height: bgHeight))
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 8
        bgView.layer?.borderWidth = 1
        bgView.autoresizingMask = [.width]

        // Borderless text field inside the background, vertically centered
        let fieldHeight: CGFloat = 20
        let fieldY: CGFloat = (bgHeight - fieldHeight) / 2
        let field = NSTextField(frame: NSRect(x: 12, y: fieldY, width: bgView.bounds.width - 24, height: fieldHeight))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 13)
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byTruncatingTail
        field.autoresizingMask = [.width]
        field.delegate = self

        bgView.addSubview(field)
        promptContainer.addSubview(bgView)
        container.addSubview(promptContainer)

        self.studyTextField = field
        self.studyPromptBg = bgView
        self.studyPromptContainer = promptContainer
        updatePromptFieldTheme()

        // Focus the field after a brief delay (window needs to be key first)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.overlayWindow?.makeFirstResponder(self?.studyTextField)
        }
    }

    private func updatePromptFieldTheme() {
        guard let field = studyTextField, let bgView = studyPromptBg else { return }
        let isDark = Theme.isDark(NSApp.effectiveAppearance)

        field.textColor = isDark
            ? NSColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1.0)
            : NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)

        let placeholderColor = isDark
            ? NSColor(white: 1.0, alpha: 0.4)
            : NSColor(white: 0.0, alpha: 0.4)
        field.placeholderAttributedString = NSAttributedString(
            string: "Ask Presto anything\u{2026}",
            attributes: [.foregroundColor: placeholderColor, .font: NSFont.systemFont(ofSize: 13)]
        )

        bgView.layer?.backgroundColor = isDark
            ? NSColor(white: 1.0, alpha: 0.08).cgColor
            : NSColor(white: 0.0, alpha: 0.05).cgColor
        bgView.layer?.borderColor = isDark
            ? NSColor(white: 1.0, alpha: 0.15).cgColor
            : NSColor(white: 0.0, alpha: 0.10).cgColor
    }

    // MARK: - NSTextFieldDelegate (native study mode prompt)
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            guard let field = control as? NSTextField else { return false }
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                field.stringValue = "Thinking\u{2026}"
                field.isEnabled = false
                onPromptSubmit?(text)
            }
            return true
        }
        return false
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        let isDark = Theme.isDark(NSApp.effectiveAppearance)
        studyPromptBg?.layer?.borderColor = isDark
            ? NSColor(red: 0.42, green: 0.71, blue: 1.0, alpha: 1.0).cgColor   // #6cb4ff
            : NSColor(red: 0.0, green: 0.40, blue: 0.80, alpha: 1.0).cgColor    // #0066cc
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let isDark = Theme.isDark(NSApp.effectiveAppearance)
        studyPromptBg?.layer?.borderColor = isDark
            ? NSColor(white: 1.0, alpha: 0.15).cgColor
            : NSColor(white: 0.0, alpha: 0.10).cgColor
    }

    private func ensurePromptWindow() {
        if overlayWindow != nil { return }
        // Use saved position (top-left corner), falling back to default upper-right
        let base: NSRect
        if let saved = savedFrame, let clamped = clampToScreen(saved) {
            base = clamped
        } else {
            base = defaultFrame()
        }
        // Same x and width, but compact height anchored to the top of the saved frame
        let frame = NSRect(
            x: base.origin.x,
            y: base.origin.y + base.height - promptInputHeight,
            width: base.width,
            height: promptInputHeight
        )
        createWindow(frame: frame)
        overlayWindow?.minSize = NSSize(width: minWidth, height: promptInputHeight)
        overlayWindow?.maxSize = NSSize(width: 9999, height: promptInputHeight)
    }

    private func presentPrompt() {
        guard let window = overlayWindow else { return }
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        HotkeyService.shared.registerEsc()
        if isStudyMode {
            window.makeFirstResponder(studyTextField)
        }
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

    private func clampToScreen(_ rect: NSRect) -> NSRect? {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        guard let screen = NSScreen.screens.min(by: { a, b in
            let dA = hypot(a.visibleFrame.midX - center.x, a.visibleFrame.midY - center.y)
            let dB = hypot(b.visibleFrame.midX - center.x, b.visibleFrame.midY - center.y)
            return dA < dB
        }) else { return nil }

        let sf = screen.visibleFrame
        var clamped = rect
        clamped.origin.x = min(max(clamped.origin.x, sf.minX), sf.maxX - clamped.width)
        clamped.origin.y = min(max(clamped.origin.y, sf.minY), sf.maxY - clamped.height)
        return clamped
    }

    private func defaultFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                           ?? NSScreen.main ?? NSScreen.screens.first else {
            // #6 — Fallback if no screen is available
            return NSRect(x: 100, y: 100, width: defaultWidth, height: defaultHeight)
        }
        let sf = screen.visibleFrame
        let pad: CGFloat = 10
        let width = min(defaultWidth, sf.width - pad * 2)
        return NSRect(
            x: sf.maxX - width - pad,
            y: sf.maxY - defaultHeight - pad,
            width: width,
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
        container.layer?.backgroundColor = Theme.nsOverlayBg(NSApp.effectiveAppearance).cgColor
        container.addSubview(wv)

        panel.contentView = container
        self.webView = wv
        self.overlayWindow = panel

        // Observe system theme changes to update overlay appearance in real-time
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(systemThemeChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil
        )

        print("[Overlay] Window created at \(frame)")
    }

    @objc private func systemThemeChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let container = self.overlayWindow?.contentView else { return }
            container.layer?.backgroundColor = Theme.nsOverlayBg(NSApp.effectiveAppearance).cgColor
            let isDark = Theme.isDark(NSApp.effectiveAppearance)
            self.webView?.evaluateJavaScript("if(typeof setTheme==='function')setTheme(\(isDark))", completionHandler: nil)
            self.updatePromptFieldTheme()
        }
    }

    // MARK: - HTML

    private var isDarkMode: Bool {
        Theme.isDark(NSApp.effectiveAppearance)
    }

    private func sharedHead(extraStyle: String = "") -> String {
        """
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width">
        <style>
        :root {
            --bg: rgba(18,18,20,0.50);
            --text: #f0f0f2;
            --text-dim: rgba(255,255,255,0.28);
            --subtle-bg: rgba(255,255,255,0.08);
            --subtle-border: rgba(255,255,255,0.15);
            --code-bg: rgba(0,0,0,0.3);
            --code-inline-bg: rgba(255,255,255,0.08);
            --blockquote-border: rgba(255,255,255,0.2);
            --blockquote-text: rgba(240,240,242,0.7);
            --link-color: #6cb4ff;
            --table-header-bg: rgba(255,255,255,0.06);
            --spinner-border: rgba(255,255,255,0.1);
            --spinner-accent: rgba(255,255,255,0.5);
            --loading-text: rgba(255,255,255,0.4);
            --error-color: #ff6b6b;
            --logo-filter: invert(1);
        }
        :root.light {
            --bg: rgba(255,255,255,0.50);
            --text: #1a1a1a;
            --text-dim: rgba(0,0,0,0.25);
            --subtle-bg: rgba(0,0,0,0.05);
            --subtle-border: rgba(0,0,0,0.10);
            --code-bg: rgba(0,0,0,0.05);
            --code-inline-bg: rgba(0,0,0,0.06);
            --blockquote-border: rgba(0,0,0,0.15);
            --blockquote-text: rgba(0,0,0,0.6);
            --link-color: #0066cc;
            --table-header-bg: rgba(0,0,0,0.04);
            --spinner-border: rgba(0,0,0,0.1);
            --spinner-accent: rgba(0,0,0,0.4);
            --loading-text: rgba(0,0,0,0.4);
            --error-color: #cc0000;
            --logo-filter: invert(0);
        }
        * { margin:0; padding:0; box-sizing:border-box; }
        html, body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            background: var(--bg);
            color: var(--text);
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
            cursor: grab;
            user-select: none;
        }
        .drag-bar:active { cursor: grabbing; }
        .logo {
            width: 15px; height: 15px;
            filter: var(--logo-filter);
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
            font-size: 10px; color: var(--text-dim);
            letter-spacing: 0.03em;
        }
        .minimize-btn {
            width: 14px; height: 14px; border-radius: 50%;
            background: #666; border: none; cursor: pointer;
            position: relative;
            padding: 0; flex-shrink: 0;
            transition: background 0.15s;
            -webkit-app-region: no-drag;
        }
        .minimize-btn::after {
            content: ''; position: absolute;
            top: 50%; left: 3px; right: 3px;
            height: 1.5px; background: #fff; border-radius: 1px;
            transform: translateY(-50%);
        }
        .minimize-btn:hover { background: #999; }
        \(extraStyle)
        </style>
        <script>
        function setTheme(isDark) {
            document.documentElement.className = isDark ? '' : 'light';
            var dark = document.getElementById('hljs-dark');
            var light = document.getElementById('hljs-light');
            if (dark) dark.disabled = !isDark;
            if (light) light.disabled = isDark;
        }
        </script>
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
        document.querySelector('.drag-bar').addEventListener('mousedown', function(e) {
            if (e.target.closest('.logo')) return;
            e.preventDefault();
            window.webkit.messageHandlers.overlay.postMessage({action:'dragStart', x: e.screenX, y: e.screenY});
            function onUp() {
                window.webkit.messageHandlers.overlay.postMessage({action:'dragEnd'});
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
            <button class="minimize-btn" onclick="window.webkit.messageHandlers.overlay.postMessage({action:'minimize'})" title="Minimize"></button>
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

    // MARK: - Response HTML with streaming markdown + finalization
    private func responseHTML(_ text: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        \(sharedHead(extraStyle: """
        /* Typographic hierarchy for rendered markdown */
        .content { padding-top: 4px; word-wrap: break-word; }
        .content h1 { font-size: 1.5em; font-weight: 700; margin: 0.8em 0 0.4em; }
        .content h2 { font-size: 1.3em; font-weight: 600; margin: 0.7em 0 0.3em; }
        .content h3 { font-size: 1.15em; font-weight: 600; margin: 0.6em 0 0.3em; }
        .content h4 { font-size: 1.05em; font-weight: 600; margin: 0.5em 0 0.2em; }
        .content h5, .content h6 { font-size: 1em; font-weight: 600; margin: 0.5em 0 0.2em; }
        .content p { margin: 0.4em 0; }
        .content ul, .content ol { padding-left: 1.4em; margin: 0.4em 0; }
        .content li { margin: 0.15em 0; }
        .content li > ul, .content li > ol { margin: 0.1em 0; }

        /* Code blocks */
        .content pre {
            background: var(--code-bg);
            border-radius: 6px;
            padding: 10px 12px;
            margin: 0.5em 0;
            overflow-x: auto;
            font-size: 12px;
            line-height: 1.45;
        }
        .content pre code {
            font-family: 'SF Mono', Menlo, Monaco, 'Courier New', monospace;
            background: none;
            padding: 0;
            font-size: inherit;
            border-radius: 0;
        }

        /* Inline code */
        .content code {
            font-family: 'SF Mono', Menlo, Monaco, 'Courier New', monospace;
            background: var(--code-inline-bg);
            padding: 0.15em 0.35em;
            border-radius: 3px;
            font-size: 0.9em;
        }

        /* Blockquotes */
        .content blockquote {
            border-left: 3px solid var(--blockquote-border);
            padding-left: 12px;
            margin: 0.5em 0;
            color: var(--blockquote-text);
        }

        /* Links */
        .content a { color: var(--link-color); text-decoration: none; }
        .content a:hover { text-decoration: underline; }

        /* Tables */
        .content table { border-collapse: collapse; margin: 0.5em 0; width: 100%; font-size: 12px; }
        .content th, .content td { border: 1px solid var(--subtle-border); padding: 4px 8px; text-align: left; }
        .content th { background: var(--table-header-bg); font-weight: 600; }

        /* Horizontal rule */
        .content hr { border: none; border-top: 1px solid var(--subtle-border); margin: 0.8em 0; }

        /* Bold and italic */
        .content strong { font-weight: 600; }
        .content em { font-style: italic; }
        .content s { text-decoration: line-through; opacity: 0.6; }

        /* Checkbox */
        .content input[type="checkbox"] { margin-right: 6px; }

        /* Images */
        .content img { max-width: 100%; border-radius: 4px; margin: 0.4em 0; }

        /* MathJax */
        .MathJax { font-size: 1.05em !important; }
        mjx-container { margin: 0.4em 0; }
        equation-block { display: block; margin: 0.5em 0; text-align: center; }
        equation-inline { display: inline; }

        /* Follow-up reply field */
        .reply-wrapper { margin-top: 12px; }
        .reply-separator {
            border-top: 1px solid var(--subtle-border);
            margin-bottom: 10px;
        }
        .reply-field {
            width: 100%;
            background: var(--subtle-bg);
            border: 1px solid var(--subtle-border);
            border-radius: 8px;
            color: var(--text);
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 13px;
            padding: 8px 12px;
            outline: none;
        }
        .reply-field::placeholder { color: var(--loading-text); }
        .reply-field:focus { border-color: var(--link-color); }
        .reply-field:disabled { opacity: 0.5; }

        /* Follow-up question separator */
        .followup-question {
            margin: 16px 0 8px 0;
            padding: 8px 10px;
            font-size: 12px;
            color: var(--loading-text);
            border-top: 1px solid var(--subtle-border);
            font-style: italic;
        }
        .followup-question::before { content: 'You: '; font-weight: 600; }
        """))

        <!-- Inlined streaming-markdown (no CDN dependency) -->
        <script>\(smdJS)</script>

        <!-- CDN libraries for finalization -->
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github-dark.min.css" id="hljs-dark">
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github.min.css" id="hljs-light" disabled>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js" onload="checkLibs()"></script>
        <script src="https://cdn.jsdelivr.net/npm/marked/lib/marked.umd.js" onload="checkLibs()"></script>
        <script src="https://cdn.jsdelivr.net/npm/marked-highlight/lib/index.umd.js" onload="checkLibs()"></script>
        <script src="https://cdn.jsdelivr.net/npm/dompurify@3/dist/purify.min.js" onload="checkLibs()"></script>

        <!-- MathJax config (must be before MathJax script) -->
        <script>
        MathJax = {
            tex: { inlineMath: [['$','$'],['\\\\(','\\\\)']], displayMath: [['$$','$$'],['\\\\[','\\\\]']], processEscapes: true },
            chtml: { displayAlign: 'left', displayIndent: '0' },
            options: { skipHtmlTags: ['script','noscript','style','textarea','pre','code'] }
        };
        </script>
        <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js" async></script>

        <script>
        // CDN load coordination
        let libsReady = false;
        let pendingFinalize = false;

        function checkLibs() {
            if (window.marked && window.markedHighlight && window.hljs && window.DOMPurify) {
                libsReady = true;
                if (pendingFinalize) { pendingFinalize = false; doFinalize(); }
            }
        }

        // Streaming state
        let rawMarkdown = '';
        let smdParser = null;

        function getLastContent() {
            var els = document.querySelectorAll('.content');
            return els[els.length - 1];
        }

        function appendChunk(text) {
            if (!smdParser) {
                var el = getLastContent();
                el.innerHTML = '';
                var renderer = smd.default_renderer(el);
                smdParser = smd.parser(renderer);
            }
            rawMarkdown += text;
            smd.parser_write(smdParser, text);
        }

        function finalize() {
            if (smdParser) { smd.parser_end(smdParser); }
            if (!libsReady) { checkLibs(); }
            if (libsReady) {
                doFinalize();
            } else {
                pendingFinalize = true;
                // Timeout: if CDN libs don't load in 5s, keep smd output
                setTimeout(function() {
                    if (pendingFinalize) {
                        pendingFinalize = false;
                        runMathJax();
                    }
                }, 5000);
            }
        }

        function doFinalize() {
            if (!window.marked || !window.hljs) {
                runMathJax();
                return;
            }

            var markedInstance = new marked.Marked(
                markedHighlight.markedHighlight({
                    emptyLangClass: 'hljs',
                    langPrefix: 'hljs language-',
                    highlight: function(code, lang) {
                        if (lang && hljs.getLanguage(lang)) {
                            return hljs.highlight(code, { language: lang }).value;
                        }
                        return hljs.highlightAuto(code).value;
                    }
                })
            );

            // Links open in default browser via target="_blank"
            var renderer = new marked.Renderer();
            renderer.link = function(linkData) {
                var href = linkData.href || '';
                var title = linkData.title ? ' title="' + linkData.title + '"' : '';
                var text = linkData.text || '';
                return '<a href="' + href + '"' + title + ' target="_blank" rel="noopener noreferrer">' + text + '</a>';
            };
            markedInstance.use({ renderer: renderer });

            // Protect math expressions from marked.js parsing
            var mathStore = [];
            var processed = rawMarkdown;

            function extractMath(text, open, close, store) {
                var s = 0;
                while (s < text.length) {
                    var a = text.indexOf(open, s);
                    if (a === -1) break;
                    var b = text.indexOf(close, a + open.length);
                    if (b === -1) break;
                    var math = text.substring(a, b + close.length);
                    var ph = '%%MATH_' + store.length + '%%';
                    store.push(math);
                    text = text.substring(0, a) + ph + text.substring(b + close.length);
                    s = a + ph.length;
                }
                return text;
            }

            processed = extractMath(processed, '$$', '$$', mathStore);
            var pos = 0;
            while (pos < processed.length) {
                var a = processed.indexOf('$', pos);
                if (a === -1) break;
                var nl = processed.indexOf('\\n', a + 1);
                var limit = (nl === -1) ? processed.length : nl;
                var b = processed.indexOf('$', a + 1);
                if (b === -1 || b >= limit) { pos = a + 1; continue; }
                var math = processed.substring(a, b + 1);
                var ph = '%%MATH_' + mathStore.length + '%%';
                mathStore.push(math);
                processed = processed.substring(0, a) + ph + processed.substring(b + 1);
                pos = a + ph.length;
            }
            processed = extractMath(processed, '\\\\[', '\\\\]', mathStore);
            processed = extractMath(processed, '\\\\(', '\\\\)', mathStore);

            var rawHTML = markedInstance.parse(processed);
            var safeHTML = DOMPurify.sanitize(rawHTML, { ADD_ATTR: ['target'] });

            for (var i = 0; i < mathStore.length; i++) {
                safeHTML = safeHTML.split('%%MATH_' + i + '%%').join(mathStore[i]);
            }

            getLastContent().innerHTML = safeHTML;

            runMathJax();
        }

        function runMathJax() {
            var el = getLastContent();
            if (window.MathJax && MathJax.typesetPromise) {
                MathJax.typesetClear([el]);
                MathJax.typesetPromise([el]).catch(function(){});
            } else if (window.MathJax && MathJax.startup && MathJax.startup.promise) {
                MathJax.startup.promise.then(function() {
                    MathJax.typesetClear([el]);
                    MathJax.typesetPromise([el]).catch(function(){});
                });
            }
        }

        function showReplyField() {
            if (document.getElementById('replyField')) return;
            var area = document.querySelector('.content-area');
            var wrapper = document.createElement('div');
            wrapper.className = 'reply-wrapper';
            wrapper.innerHTML = '<div class="reply-separator"></div>' +
                '<input class="reply-field" id="replyField" type="text" ' +
                'placeholder="Ask a follow-up…" autocomplete="off">';
            area.appendChild(wrapper);
            var input = document.getElementById('replyField');
            input.addEventListener('keydown', function(e) {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    var text = input.value.trim();
                    if (text) {
                        input.disabled = true;
                        input.value = 'Thinking…';
                        window.webkit.messageHandlers.overlay.postMessage({action:'followUpSubmit', prompt: text});
                    }
                }
            });
            // No auto-focus — let the user click when ready
        }

        function startFollowUp(question) {
            // Remove reply field
            var existing = document.querySelector('.reply-wrapper');
            if (existing) existing.remove();
            // Remove usage warning if present
            var warn = document.querySelector('.usage-warn');
            if (warn) warn.remove();
            // Add separator with user question
            var area = document.querySelector('.content-area');
            var sep = document.createElement('div');
            sep.className = 'followup-question';
            sep.textContent = question;
            area.appendChild(sep);
            // Add new content div — give it min-height so there's enough scroll room
            // to bring the question separator to the top of the visible area
            var newContent = document.createElement('div');
            newContent.className = 'content';
            newContent.style.minHeight = area.clientHeight + 'px';
            area.appendChild(newContent);
            // Reset streaming state
            rawMarkdown = '';
            smdParser = null;
            pendingFinalize = false;
            // Scroll so the question is at the top of the visible area
            area.scrollTop = sep.offsetTop - 4;
        }

        // Override finalize to also show reply field
        var _origFinalize = finalize;
        finalize = function() {
            _origFinalize();
            showReplyField();
        };

        </script>

        <body>
        \(headerHTML())
        <div class="content-area"><div class="content"></div></div>
        \(bottomBarHTML())
        \(gripJS())
        <script>setTheme(\(isDarkMode))</script>
        </body></html>
        """
    }

    private func loadingHTML() -> String {
        """
        <!DOCTYPE html><html>
        \(sharedHead(extraStyle: """
        .center { display:flex; align-items:center; justify-content:center;
                  height:100%; flex-direction:column; gap:12px; }
        .spinner { width:28px; height:28px; border:2.5px solid var(--spinner-border);
                   border-top-color:var(--spinner-accent); border-radius:50%;
                   animation:spin 0.8s linear infinite; }
        @keyframes spin { to { transform:rotate(360deg); } }
        p { color:var(--loading-text); font-size:12px; }
        """))
        <body>
        \(headerHTML())
        <div class="content-area"><div class="center">
            <div class="spinner"></div><p>Analyzing…</p>
        </div></div>
        \(bottomBarHTML())
        \(gripJS())
        <script>setTheme(\(isDarkMode))</script>
        </body></html>
        """
    }

    private func errorHTML(_ message: String) -> String {
        let escaped = message
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html><html>
        \(sharedHead(extraStyle: ".err { color:var(--error-color); padding-top:4px; }"))
        <body>
        \(headerHTML())
        <div class="content-area"><div class="err">\(escaped)</div></div>
        \(bottomBarHTML())
        \(gripJS())
        <script>setTheme(\(isDarkMode))</script>
        </body></html>
        """
    }

    private func promptInputHTML(placeholder: String? = nil) -> String {
        let placeholderText = placeholder ?? "Ask anything about this screenshot…"
        return """
        <!DOCTYPE html><html>
        \(sharedHead(extraStyle: """
        .prompt-area {
            position: absolute; top: 36px; left: 0; right: 0; bottom: 0;
            display: flex; align-items: center;
            padding: 0 12px 10px 12px;
        }
        .prompt-field {
            width: 100%;
            background: var(--subtle-bg);
            border: 1px solid var(--subtle-border);
            border-radius: 8px;
            color: var(--text);
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 13px;
            padding: 8px 12px;
            outline: none;
            resize: none;
        }
        .prompt-field::placeholder { color: var(--loading-text); }
        .prompt-field:focus { border-color: var(--link-color); }
        """))
        <body>
        <div class="drag-bar">
            <img class="logo" src="data:image/png;base64,\(iconB64)">
            <span style="font-size:11px;color:var(--text-dim);margin-left:2px;">Quick Prompt</span>
            <span class="drag-spacer"></span>
        </div>
        <div class="prompt-area">
            <input class="prompt-field" id="promptInput"
                   type="text" placeholder="\(placeholderText)"
                   autocomplete="off" autofocus>
        </div>
        <script>
        document.querySelector('.drag-bar').addEventListener('mousedown', function(e) {
            if (e.target.closest('.logo')) return;
            e.preventDefault();
            window.webkit.messageHandlers.overlay.postMessage({action:'dragStart', x: e.screenX, y: e.screenY});
            function onUp() {
                window.webkit.messageHandlers.overlay.postMessage({action:'dragEnd'});
                document.removeEventListener('mouseup', onUp);
            }
            document.addEventListener('mouseup', onUp);
        });
        var input = document.getElementById('promptInput');
        input.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                var text = input.value.trim();
                if (text) {
                    window.webkit.messageHandlers.overlay.postMessage({action:'promptSubmit', prompt: text});
                }
            }
        });
        // Auto-focus after page load
        setTimeout(function() { input.focus(); }, 50);
        setTheme(\(isDarkMode));
        </script>
        </body></html>
        """
    }

    private func studyModeBarHTML() -> String {
        """
        <!DOCTYPE html><html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width">
        <style>
        :root {
            --text-primary: rgba(255, 255, 255, 0.92);
            --text-secondary: rgba(255, 255, 255, 0.55);
            --text-tertiary: rgba(255, 255, 255, 0.28);
            --separator: rgba(255, 255, 255, 0.08);
            --row-hover: rgba(255, 255, 255, 0.04);
            --control-bg: rgba(255, 255, 255, 0.07);
            --control-active-bg: rgba(255, 255, 255, 0.12);
            --accent-green: #34C759;
            --accent-amber: #FF9F0A;
            --code-bg: rgba(0, 0, 0, 0.25);
        }
        :root.light {
            --text-primary: rgba(0, 0, 0, 0.88);
            --text-secondary: rgba(0, 0, 0, 0.50);
            --text-tertiary: rgba(0, 0, 0, 0.25);
            --separator: rgba(0, 0, 0, 0.06);
            --row-hover: rgba(0, 0, 0, 0.03);
            --control-bg: rgba(0, 0, 0, 0.05);
            --control-active-bg: rgba(0, 0, 0, 0.08);
            --accent-green: #34C759;
            --accent-amber: #FF9F0A;
            --code-bg: rgba(0, 0, 0, 0.04);
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            background: transparent;
            color: var(--text-primary);
            font-size: 13px;
            line-height: 1.5;
            height: 100vh;
            overflow: hidden;
        }

        /* Status Bar — 28px, always visible */
        .status-bar {
            height: 28px;
            display: flex;
            align-items: center;
            padding: 0 12px;
            gap: 8px;
            -webkit-app-region: drag;
            user-select: none;
            cursor: grab;
            position: sticky;
            top: 0;
            z-index: 10;
        }
        .status-bar:active { cursor: grabbing; }

        .activity-dot {
            width: 6px; height: 6px; border-radius: 50%;
            background: var(--accent-green);
            flex-shrink: 0;
            animation: pulse 2.5s ease-in-out infinite;
        }
        .activity-dot.paused {
            background: var(--accent-amber);
            animation: none;
        }
        .activity-dot.solving {
            animation: pulse 1.2s ease-in-out infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.4; }
        }

        .status-label {
            font: 500 11px/1 -apple-system, sans-serif;
            color: var(--text-secondary);
            letter-spacing: 0.01em;
            transition: opacity 0.15s ease;
            white-space: nowrap;
        }

        .status-spacer { flex: 1; }

        /* Mode Toggle */
        .mode-toggle {
            display: flex;
            background: var(--control-bg);
            border-radius: 6px;
            padding: 1px;
            gap: 1px;
            -webkit-app-region: no-drag;
        }
        .mode-toggle button {
            font: 500 10px/1 -apple-system, sans-serif;
            padding: 3px 10px;
            border: none;
            border-radius: 5px;
            background: transparent;
            color: var(--text-tertiary);
            cursor: pointer;
            transition: all 0.2s ease;
        }
        .mode-toggle button.active {
            background: var(--control-active-bg);
            color: var(--text-primary);
            box-shadow: 0 0.5px 1px rgba(0,0,0,0.12);
        }
        .mode-toggle button:hover:not(.active) {
            color: var(--text-secondary);
        }

        /* Stop Button */
        .stop-btn {
            width: 18px; height: 18px;
            border: none; background: none;
            color: var(--text-tertiary);
            cursor: pointer;
            display: flex; align-items: center; justify-content: center;
            border-radius: 4px;
            transition: background 0.15s, color 0.15s;
            -webkit-app-region: no-drag;
        }
        .stop-btn:hover {
            background: var(--control-bg);
            color: var(--text-secondary);
        }

        /* Content Area */
        .content-area {
            position: absolute;
            top: 28px;
            left: 0;
            right: 0;
            bottom: 48px;
            overflow-y: auto;
            overflow-x: hidden;
            padding: 4px 0;
            opacity: 0;
            transition: opacity 0.2s ease;
        }
        .content-area.visible { opacity: 1; }

        .content-area::-webkit-scrollbar { width: 4px; }
        .content-area::-webkit-scrollbar-track { background: transparent; }
        .content-area::-webkit-scrollbar-thumb {
            background: var(--text-tertiary);
            border-radius: 2px;
        }

        /* Question Row */
        .question-row {
            padding: 8px 14px;
            display: flex;
            flex-direction: column;
            gap: 4px;
            border-bottom: 0.5px solid var(--separator);
            transition: background 0.15s ease;
            cursor: default;
        }
        .question-row:last-child { border-bottom: none; }
        .question-row:hover { background: var(--row-hover); }

        .row-header {
            display: flex;
            align-items: baseline;
            gap: 8px;
            min-width: 0;
        }

        .q-number {
            font: 600 11px/1 -apple-system, sans-serif;
            color: var(--text-tertiary);
            min-width: 20px;
            flex-shrink: 0;
        }

        .q-answer {
            flex: 1;
            font: 400 13px/1.5 -apple-system, sans-serif;
            color: var(--text-primary);
            min-width: 0;
            overflow-x: auto;
            overflow-y: hidden;
            white-space: nowrap;
            scrollbar-width: none;
            -ms-overflow-style: none;
        }
        .q-answer::-webkit-scrollbar {
            display: none;
        }

        .row-actions {
            display: flex;
            align-items: center;
            gap: 2px;
            flex-shrink: 0;
            opacity: 0;
            transition: opacity 0.15s ease;
        }
        .question-row:hover .row-actions { opacity: 1; }

        /* Action Buttons */
        .action-btn {
            width: 22px; height: 22px;
            border: none; background: none;
            color: var(--text-tertiary);
            cursor: pointer;
            display: flex; align-items: center; justify-content: center;
            border-radius: 4px;
            transition: background 0.1s, color 0.1s;
        }
        .action-btn:hover {
            background: var(--control-bg);
            color: var(--text-secondary);
        }
        .action-btn:active { background: var(--control-active-bg); }
        .action-btn.copied { color: var(--accent-green); }

        /* Solving State */
        .question-row.solving .q-answer {
            background: linear-gradient(90deg, var(--text-tertiary) 25%, var(--text-secondary) 50%, var(--text-tertiary) 75%);
            background-size: 400px 100%;
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            animation: shimmer 1.8s ease-in-out infinite;
            font-style: italic;
        }
        @keyframes shimmer {
            0% { background-position: -200px 0; }
            100% { background-position: 200px 0; }
        }

        /* Placeholder shimmer for identifying state */
        .question-row.solving .q-answer:empty,
        .question-row.solving .q-number:empty {
            display: inline-block;
            min-width: 60px;
            height: 14px;
            border-radius: 4px;
            background: linear-gradient(90deg, var(--control-bg) 25%, var(--control-active-bg) 50%, var(--control-bg) 75%);
            background-size: 400px 100%;
            animation: shimmer 1.8s ease-in-out infinite;
            -webkit-text-fill-color: transparent;
        }

        /* Failed State */
        .question-row.failed .q-answer { color: var(--text-tertiary); }
        .retry-link {
            font: 400 12px/1 -apple-system, sans-serif;
            color: var(--text-secondary);
            cursor: pointer;
            margin-left: 4px;
            text-decoration: none;
            transition: color 0.15s;
        }
        .retry-link:hover { color: var(--text-primary); }

        /* Expanded Steps */
        .steps-container {
            overflow: hidden;
            max-height: 0;
            opacity: 0;
            transition: max-height 0.35s cubic-bezier(0.34, 1.56, 0.64, 1), opacity 0.2s ease;
            padding-left: 28px;
        }
        .steps-container.expanded {
            max-height: 600px;
            opacity: 1;
        }
        .step {
            padding: 6px 0;
            display: flex;
            gap: 8px;
            align-items: flex-start;
        }
        .step-number {
            font: 600 10px/1.6 -apple-system, sans-serif;
            color: var(--text-tertiary);
            min-width: 16px;
            flex-shrink: 0;
        }
        .step-content { flex: 1; }
        .step-math {
            font: 400 13px/1.5 -apple-system, sans-serif;
            color: var(--text-primary);
            margin-bottom: 2px;
        }
        .step-explanation {
            font: 400 11px/1.4 -apple-system, sans-serif;
            color: var(--text-secondary);
        }
        .step.key-step {
            border-left: 1.5px solid rgba(52, 199, 89, 0.35);
            padding-left: 8px;
            margin-left: -10px;
        }
        .steps-loading {
            padding: 12px 0;
            color: var(--text-tertiary);
            font: 400 12px/1 -apple-system, sans-serif;
            font-style: italic;
            background: linear-gradient(90deg, var(--text-tertiary) 25%, var(--text-secondary) 50%, var(--text-tertiary) 75%);
            background-size: 400px 100%;
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            animation: shimmer 1.8s ease-in-out infinite;
        }

        /* Page Divider */
        .page-divider {
            padding: 8px 14px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .page-divider::before, .page-divider::after {
            content: '';
            flex: 1;
            height: 0.5px;
            background: var(--separator);
        }
        .page-divider span {
            font: 500 10px/1 -apple-system, sans-serif;
            color: var(--text-tertiary);
            letter-spacing: 0.03em;
            text-transform: uppercase;
        }

        /* Learn Mode Cards */
        .concept-card {
            padding: 12px 14px;
            display: flex;
            flex-direction: column;
            gap: 8px;
        }
        .concept-title {
            font: 600 13px/1.3 -apple-system, sans-serif;
            color: var(--text-primary);
        }
        .concept-body {
            font: 400 12px/1.5 -apple-system, sans-serif;
            color: var(--text-secondary);
        }
        .concept-formula {
            padding: 8px 12px;
            background: var(--control-bg);
            border-radius: 6px;
            text-align: center;
        }
        .similar-example {
            padding: 8px 0;
            border-top: 0.5px solid var(--separator);
            margin-top: 8px;
        }
        .similar-example-label {
            font: 500 10px/1 -apple-system, sans-serif;
            color: var(--text-tertiary);
            letter-spacing: 0.03em;
            text-transform: uppercase;
            margin-bottom: 6px;
        }
        .feedback-card { padding: 12px 14px; }
        .feedback-score {
            display: flex;
            align-items: center;
            gap: 6px;
            margin-bottom: 8px;
        }
        .score-bar {
            height: 3px;
            border-radius: 1.5px;
            background: var(--control-bg);
            flex: 1;
        }
        .score-fill {
            height: 100%;
            border-radius: 1.5px;
            background: var(--accent-green);
            transition: width 0.5s cubic-bezier(0.34, 1.56, 0.64, 1);
        }
        .feedback-text {
            font: 400 12px/1.5 -apple-system, sans-serif;
            color: var(--text-secondary);
        }
        .error-highlight { color: var(--accent-amber); font-weight: 500; }

        /* Session Summary */
        .summary-card {
            padding: 16px 14px;
            display: flex;
            flex-direction: column;
            gap: 12px;
        }
        .summary-title {
            font: 600 14px/1.3 -apple-system, sans-serif;
            color: var(--text-primary);
        }
        .summary-stats {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 8px;
        }
        .stat {
            display: flex;
            flex-direction: column;
            gap: 2px;
        }
        .stat-value {
            font: 600 18px/1 -apple-system, sans-serif;
            color: var(--text-primary);
            font-variant-numeric: tabular-nums;
        }
        .stat-label {
            font: 400 10px/1 -apple-system, sans-serif;
            color: var(--text-tertiary);
            text-transform: uppercase;
            letter-spacing: 0.04em;
        }
        .summary-topics {
            display: flex;
            flex-wrap: wrap;
            gap: 4px;
        }
        .topic-tag {
            font: 500 10px/1 -apple-system, sans-serif;
            padding: 3px 8px;
            background: var(--control-bg);
            border-radius: 4px;
            color: var(--text-secondary);
        }

        /* MathJax overrides */
        mjx-container {
            vertical-align: baseline !important;
            line-height: 1.5;
            display: inline !important;
        }
        mjx-container[jax="SVG"] > svg { vertical-align: middle !important; }
        .MathJax { vertical-align: baseline !important; }

        /* Identify loading */
        .identify-loading {
            padding: 16px 14px;
            text-align: center;
            color: var(--text-tertiary);
            font: 400 12px/1.5 -apple-system, sans-serif;
        }

        /* User input echo */
        .user-input-echo {
            padding: 8px 14px;
            margin-bottom: 4px;
        }
        .user-input-text {
            font: 500 12px/1.4 -apple-system, sans-serif;
            color: var(--text-primary);
            padding: 8px 12px;
            background: var(--control-bg);
            border-radius: 8px;
            border-bottom-right-radius: 2px;
            display: inline-block;
            max-width: 90%;
            word-wrap: break-word;
        }

        /* Streaming content area (for learn mode chat) */
        .content { word-wrap: break-word; padding: 4px 14px; }
        .content h1 { font: 700 16px/1.3 -apple-system, sans-serif; color: var(--text-primary); margin: 12px 0 6px; }
        .content h2 { font: 600 14px/1.3 -apple-system, sans-serif; color: var(--text-primary); margin: 10px 0 4px; }
        .content h3 { font: 600 13px/1.3 -apple-system, sans-serif; color: var(--text-primary); margin: 8px 0 4px; }
        .content p { margin: 0.4em 0; }
        .content strong { font-weight: 600; }
        .content em { font-style: italic; }
        .content ul, .content ol { padding-left: 1.4em; margin: 4px 0; }
        .content li { margin: 2px 0; font: 400 12px/1.5 -apple-system, sans-serif; color: var(--text-secondary); }
        .content blockquote {
            border-left: 2px solid var(--separator);
            padding-left: 10px;
            margin: 6px 0;
            color: var(--text-secondary);
            font-style: italic;
        }
        .content a { color: #6cb4ff; text-decoration: none; }
        .content a:hover { text-decoration: underline; }
        .content hr { border: none; border-top: 0.5px solid var(--separator); margin: 8px 0; }
        .content pre {
            background: var(--code-bg); border-radius: 6px;
            padding: 10px 12px; margin: 0.5em 0; overflow-x: auto;
            font-size: 12px; line-height: 1.45;
        }
        .content pre code {
            font-family: 'SF Mono', Menlo, Monaco, monospace;
            background: none; padding: 0; font-size: inherit;
        }
        .content code {
            font-family: 'SF Mono', Menlo, Monaco, monospace;
            background: var(--code-bg); padding: 0.15em 0.35em;
            border-radius: 3px; font-size: 0.9em;
        }
        /* Display math blocks */
        .content mjx-container[display="true"] {
            margin: 8px 0;
            padding: 6px 0;
            overflow-x: auto;
        }

        </style>

        <!-- MathJax config -->
        <script>
        MathJax = {
            tex: { inlineMath: [['\\\\(','\\\\)']], displayMath: [['\\\\[','\\\\]']] },
            svg: { fontCache: 'global' },
            options: { renderActions: { addMenu: [] } },
            startup: { typeset: false }
        };
        </script>
        <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js" async></script>

        <!-- streaming-markdown -->
        <script>\(smdJS)</script>
        <script src="https://cdn.jsdelivr.net/npm/marked/lib/marked.umd.js" async></script>
        <script src="https://cdn.jsdelivr.net/npm/dompurify@3/dist/purify.min.js" async></script>

        <script>
        function setTheme(isDark) {
            document.documentElement.className = isDark ? '' : 'light';
        }
        </script>
        </head>

        <body>
        <!-- Status Bar -->
        <div class="status-bar">
            <div class="activity-dot" id="activityDot"></div>
            <span class="status-label" id="statusLabel">Study Mode</span>
            <span class="status-spacer"></span>
            <div class="mode-toggle" id="modeToggle">
                <button class="active" id="btnLearn" onclick="switchMode('learn')">Learn</button>
                <button id="btnSolve" onclick="switchMode('solve')">Solve</button>
            </div>
            <button class="stop-btn" onclick="stopStudy()" title="Stop session">
                <svg width="8" height="8" viewBox="0 0 8 8"><rect width="8" height="8" rx="1.5" fill="currentColor"/></svg>
            </button>
        </div>

        <!-- Content Area -->
        <div class="content-area" id="contentArea">
            <div id="questionsContainer" style="display:none;"></div>
            <div class="content" id="learnContent"></div>
        </div>

        <script>
        var currentMode = 'learn';
        var expandedSteps = {};
        var rawMarkdown = '';
        var smdParser = null;

        // SVG icons
        var chevronDown = '<svg width="10" height="6" viewBox="0 0 10 6"><path d="M1 1l4 4 4-4" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        var chevronUp = '<svg width="10" height="6" viewBox="0 0 10 6"><path d="M1 5l4-4 4 4" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        var copyIcon = '<svg width="12" height="12" viewBox="0 0 12 12"><rect x="3.5" y="3.5" width="7" height="7" rx="1" stroke="currentColor" fill="none" stroke-width="1.2"/><path d="M8.5 3.5V2a1 1 0 00-1-1H2a1 1 0 00-1 1v5.5a1 1 0 001 1h1.5" stroke="currentColor" fill="none" stroke-width="1.2"/></svg>';
        var checkIcon = '<svg width="12" height="12" viewBox="0 0 12 12"><path d="M2.5 6.5l2.5 2.5 4.5-5" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';

        function switchMode(mode) {
            currentMode = mode;
            document.getElementById('btnSolve').classList.toggle('active', mode === 'solve');
            document.getElementById('btnLearn').classList.toggle('active', mode === 'learn');

            // Hide summary if visible
            var summary = document.getElementById('summaryContainer');
            if (summary) summary.style.display = 'none';

            document.getElementById('questionsContainer').style.display = mode === 'solve' ? '' : 'none';
            document.getElementById('learnContent').style.display = mode === 'learn' ? '' : 'none';

            // Adjust content area bottom to reclaim input field space in solve mode
            var contentArea = document.getElementById('contentArea');
            if (mode === 'solve') {
                contentArea.style.bottom = '0px';
            } else {
                contentArea.style.bottom = '48px';
            }

            window.webkit.messageHandlers.overlay.postMessage({action:'studyModeSwitch', mode: mode});
        }

        function stopStudy() {
            window.webkit.messageHandlers.overlay.postMessage({action:'studyStop'});
        }

        function updateStatus(text, dotState) {
            document.getElementById('statusLabel').textContent = text;
            var dot = document.getElementById('activityDot');
            dot.className = 'activity-dot';
            if (dotState === 'paused') dot.classList.add('paused');
            else if (dotState === 'solving') dot.classList.add('solving');
        }

        function showContentArea() {
            document.getElementById('contentArea').classList.add('visible');
        }

        function hideContentArea() {
            document.getElementById('contentArea').classList.remove('visible');
        }

        // MARK: - Question Row Building

        function buildQuestionRow(q) {
            var row = document.createElement('div');
            row.className = 'question-row' + (q.state === 'solving' ? ' solving' : '') + (q.state === 'failed' ? ' failed' : '');
            row.setAttribute('data-id', q.id);
            row.setAttribute('data-state', q.state);

            var header = document.createElement('div');
            header.className = 'row-header';

            var num = document.createElement('span');
            num.className = 'q-number';
            num.textContent = q.id;
            header.appendChild(num);

            var answer = document.createElement('span');
            answer.className = 'q-answer';

            if (q.state === 'solving') {
                answer.textContent = 'Solving...';
            } else if (q.state === 'failed') {
                answer.textContent = 'Could not solve';
                var retry = document.createElement('a');
                retry.className = 'retry-link';
                retry.textContent = 'Retry';
                retry.href = '#';
                (function(id) {
                    retry.onclick = function(e) {
                        e.preventDefault();
                        window.webkit.messageHandlers.overlay.postMessage({action:'autoSolveResolve', id: id});
                    };
                })(q.id);
                answer.appendChild(document.createTextNode(' \\u00B7 '));
                answer.appendChild(retry);
            } else if (q.state === 'solved' && q.latex) {
                var mathNode = document.createTextNode('\\\\(' + q.latex + '\\\\)');
                answer.appendChild(mathNode);
            } else if (q.state === 'pending') {
                answer.textContent = '';
                answer.style.color = 'var(--text-tertiary)';
            }

            header.appendChild(answer);

            // Actions (hover-visible)
            if (q.state === 'solved') {
                var actions = document.createElement('div');
                actions.className = 'row-actions';

                // Expand/collapse chevron
                var expandBtn = document.createElement('button');
                expandBtn.className = 'action-btn';
                expandBtn.innerHTML = expandedSteps[q.id] ? chevronDown : chevronUp;
                (function(id, btn) {
                    expandBtn.onclick = function() {
                        toggleSteps(id, btn);
                    };
                })(q.id, expandBtn);
                actions.appendChild(expandBtn);

                // Copy button
                if (q.copyable) {
                    var copyBtn = document.createElement('button');
                    copyBtn.className = 'action-btn';
                    copyBtn.innerHTML = copyIcon;
                    (function(text, btn) {
                        copyBtn.onclick = function() { doCopy(text, btn); };
                    })(q.copyable, copyBtn);
                    actions.appendChild(copyBtn);
                }

                header.appendChild(actions);
            }

            row.appendChild(header);

            // Steps container (always present for solved, hidden by default)
            if (q.state === 'solved') {
                var stepsContainer = document.createElement('div');
                stepsContainer.className = 'steps-container' + (expandedSteps[q.id] ? ' expanded' : '');
                stepsContainer.id = 'steps-' + q.id;

                if (expandedSteps[q.id] && q.steps && q.steps.length > 0) {
                    renderSteps(stepsContainer, q.steps);
                } else if (expandedSteps[q.id]) {
                    stepsContainer.innerHTML = '<div class="steps-loading">Loading steps...</div>';
                }

                row.appendChild(stepsContainer);
            }

            return row;
        }

        function renderSteps(container, steps) {
            container.innerHTML = '';
            for (var i = 0; i < steps.length; i++) {
                var s = steps[i];
                var step = document.createElement('div');
                step.className = 'step' + (s.isKeyStep ? ' key-step' : '');

                var stepNum = document.createElement('span');
                stepNum.className = 'step-number';
                stepNum.textContent = s.stepNumber + '.';
                step.appendChild(stepNum);

                var stepContent = document.createElement('div');
                stepContent.className = 'step-content';

                var stepMath = document.createElement('div');
                stepMath.className = 'step-math';
                stepMath.appendChild(document.createTextNode('\\\\(' + s.latex + '\\\\)'));
                stepContent.appendChild(stepMath);

                var stepExpl = document.createElement('div');
                stepExpl.className = 'step-explanation';
                stepExpl.textContent = s.explanation;
                stepContent.appendChild(stepExpl);

                step.appendChild(stepContent);
                container.appendChild(step);
            }
            typesetElement(container);
        }

        function toggleSteps(id, btn) {
            var container = document.getElementById('steps-' + id);
            if (!container) return;
            if (expandedSteps[id]) {
                expandedSteps[id] = false;
                container.classList.remove('expanded');
                btn.innerHTML = chevronUp;
            } else {
                expandedSteps[id] = true;
                container.classList.add('expanded');
                btn.innerHTML = chevronDown;
                // Request steps if not loaded
                if (container.querySelector('.steps-loading') || container.children.length === 0) {
                    container.innerHTML = '<div class="steps-loading">Loading steps...</div>';
                    window.webkit.messageHandlers.overlay.postMessage({action:'studyExpandSteps', id: id});
                }
            }
        }

        function updateSteps(id, steps) {
            var container = document.getElementById('steps-' + id);
            if (!container) return;
            if (steps && steps.length > 0) {
                renderSteps(container, steps);
            } else {
                container.innerHTML = '<div class="step-explanation">No steps available</div>';
            }
        }

        function doCopy(text, btn) {
            window.webkit.messageHandlers.overlay.postMessage({action:'copy', text: text});
            btn.innerHTML = checkIcon;
            btn.classList.add('copied');
            setTimeout(function() {
                btn.innerHTML = copyIcon;
                btn.classList.remove('copied');
            }, 1500);
        }

        // MARK: - Full Refresh

        function refreshStudyUI(statusText, dotState, questions) {
            updateStatus(statusText, dotState);
            var container = document.getElementById('questionsContainer');
            container.innerHTML = '';

            var lastPage = -1;
            for (var i = 0; i < questions.length; i++) {
                var q = questions[i];
                // Page divider
                if (q.page !== lastPage && lastPage !== -1) {
                    var divider = document.createElement('div');
                    divider.className = 'page-divider';
                    divider.innerHTML = '<span>Page ' + q.page + '</span>';
                    container.appendChild(divider);
                }
                lastPage = q.page;

                var row = buildQuestionRow(q);
                row.style.opacity = '0';
                row.style.transform = 'translateX(12px)';
                row.style.transition = 'opacity 0.25s ease, transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)';
                container.appendChild(row);

                // Staggered entrance
                (function(r, idx) {
                    setTimeout(function() {
                        r.style.opacity = '1';
                        r.style.transform = 'translateX(0)';
                    }, idx * 60);
                })(row, i);
            }

            // Typeset MathJax
            typesetElement(container);

            // Only show questions container if in solve mode
            if (currentMode === 'solve') {
                container.style.display = '';
                document.getElementById('learnContent').style.display = 'none';
                showContentArea();
            } else {
                container.style.display = 'none';
            }
        }

        // Update a single row without full rebuild
        function updateQuestionRow(q) {
            var existing = document.querySelector('[data-id="' + q.id + '"]');
            if (!existing) {
                // New row — append with animation
                var newRow = buildQuestionRow(q);
                newRow.style.opacity = '0';
                newRow.style.transform = 'translateX(12px)';
                newRow.style.transition = 'opacity 0.25s ease, transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)';
                document.getElementById('questionsContainer').appendChild(newRow);
                setTimeout(function() { newRow.style.opacity = '1'; newRow.style.transform = 'translateX(0)'; }, 30);
                typesetElement(newRow);
                return;
            }

            // Existing row — update in-place with cross-fade
            var wasState = existing.getAttribute('data-state') || '';
            if (wasState === q.state) return;

            existing.setAttribute('data-state', q.state);
            existing.className = 'question-row' + (q.state === 'solving' ? ' solving' : '') + (q.state === 'failed' ? ' failed' : '');

            var answerEl = existing.querySelector('.q-answer');
            if (!answerEl) return;

            answerEl.style.transition = 'opacity 0.15s ease';
            answerEl.style.opacity = '0';

            setTimeout(function() {
                if (q.state === 'solving') {
                    answerEl.textContent = 'Solving...';
                } else if (q.state === 'failed') {
                    answerEl.innerHTML = 'Could not solve';
                    var retry = document.createElement('a');
                    retry.className = 'retry-link';
                    retry.textContent = 'Retry';
                    retry.href = '#';
                    retry.onclick = function(e) { e.preventDefault(); window.webkit.messageHandlers.overlay.postMessage({action:'autoSolveResolve', id: q.id}); };
                    answerEl.appendChild(document.createTextNode(' \\u00B7 '));
                    answerEl.appendChild(retry);
                } else if (q.state === 'solved' && q.latex) {
                    answerEl.innerHTML = '';
                    answerEl.appendChild(document.createTextNode('\\\\(' + q.latex + '\\\\)'));

                    var actions = existing.querySelector('.row-actions');
                    if (!actions) {
                        actions = document.createElement('div');
                        actions.className = 'row-actions';
                        existing.querySelector('.row-header').appendChild(actions);
                    }
                    actions.innerHTML = '';
                    var expandBtn = document.createElement('button');
                    expandBtn.className = 'action-btn';
                    expandBtn.innerHTML = chevronUp;
                    expandBtn.onclick = function() { toggleSteps(q.id, expandBtn); };
                    actions.appendChild(expandBtn);
                    if (q.copyable) {
                        var copyBtn = document.createElement('button');
                        copyBtn.className = 'action-btn';
                        copyBtn.innerHTML = copyIcon;
                        copyBtn.onclick = function() { doCopy(q.copyable, copyBtn); };
                        actions.appendChild(copyBtn);
                    }
                    if (!document.getElementById('steps-' + q.id)) {
                        var sc = document.createElement('div');
                        sc.className = 'steps-container';
                        sc.id = 'steps-' + q.id;
                        existing.appendChild(sc);
                    }
                }
                answerEl.style.opacity = '1';
                typesetElement(answerEl);
            }, 150);
        }

        // MARK: - Session Summary

        function showSessionSummary(data) {
            // Hide both mode containers — summary is mode-independent
            document.getElementById('questionsContainer').style.display = 'none';
            document.getElementById('learnContent').style.display = 'none';

            var existing = document.getElementById('summaryContainer');
            if (existing) existing.remove();

            var summaryEl = document.createElement('div');
            summaryEl.id = 'summaryContainer';
            summaryEl.style.display = 'block';
            document.getElementById('contentArea').appendChild(summaryEl);

            var card = document.createElement('div');
            card.className = 'summary-card';
            card.style.opacity = '0';
            card.style.transform = 'translateY(8px)';
            card.style.transition = 'opacity 0.3s ease, transform 0.3s ease';

            card.innerHTML =
                '<div class="summary-title">Session Complete</div>' +
                '<div class="summary-stats">' +
                    '<div class="stat"><span class="stat-value">' + data.duration + '</span><span class="stat-label">Duration</span></div>' +
                    '<div class="stat"><span class="stat-value">' + data.solved + '</span><span class="stat-label">Solved</span></div>' +
                    '<div class="stat"><span class="stat-value">' + data.pages + '</span><span class="stat-label">Pages</span></div>' +
                    '<div class="stat"><span class="stat-value">' + (data.topics ? data.topics.length : 0) + '</span><span class="stat-label">Topics</span></div>' +
                '</div>';

            if (data.topics && data.topics.length > 0) {
                var topicsDiv = document.createElement('div');
                topicsDiv.className = 'summary-topics';
                for (var i = 0; i < data.topics.length; i++) {
                    var tag = document.createElement('span');
                    tag.className = 'topic-tag';
                    tag.textContent = data.topics[i];
                    topicsDiv.appendChild(tag);
                }
                card.appendChild(topicsDiv);
            }

            summaryEl.appendChild(card);
            showContentArea();
            setTimeout(function() {
                card.style.opacity = '1';
                card.style.transform = 'translateY(0)';
            }, 50);
        }

        // MARK: - Learn Mode Streaming

        function showUserInput(text) {
            var el = document.getElementById('learnContent');
            el.innerHTML = '';
            el.style.display = '';
            document.getElementById('questionsContainer').style.display = 'none';

            var echo = document.createElement('div');
            echo.className = 'user-input-echo';
            echo.id = 'currentUserInput';
            var bubble = document.createElement('div');
            bubble.className = 'user-input-text';
            bubble.textContent = text;
            echo.appendChild(bubble);
            el.appendChild(echo);

            var responseContainer = document.createElement('div');
            responseContainer.id = 'learnResponseContainer';
            responseContainer.className = 'content';
            responseContainer.style.padding = '4px 14px';
            el.appendChild(responseContainer);

            showContentArea();
        }

        function appendChunk(text) {
            var container = document.getElementById('learnResponseContainer');
            if (!container) container = document.getElementById('learnContent');
            if (!smdParser) {
                var renderer = smd.default_renderer(container);
                smdParser = smd.parser(renderer);
            }
            rawMarkdown += text;
            smd.parser_write(smdParser, text);
            var area = document.getElementById('contentArea');
            area.scrollTop = area.scrollHeight;
        }

        function finalize() {
            if (smdParser) { smd.parser_end(smdParser); }
            doFullFinalize();
        }

        function doFullFinalize() {
            if (!rawMarkdown.trim()) return;

            var el = document.getElementById('learnResponseContainer');
            if (!el) el = document.getElementById('learnContent');

            // If marked isn't loaded yet, just do MathJax on the raw smd output
            if (!window.marked || !window.DOMPurify) {
                typesetElement(el);
                rawMarkdown = '';
                smdParser = null;
                return;
            }

            // Step 1: Extract all math blocks into placeholders before markdown parsing
            var mathStore = [];

            function extractMath(text, open, close, store) {
                var s = 0;
                while (s < text.length) {
                    var a = text.indexOf(open, s);
                    if (a === -1) break;
                    var b = text.indexOf(close, a + open.length);
                    if (b === -1) break;
                    var m = text.substring(a, b + close.length);
                    var ph = '%%MATH_' + store.length + '%%';
                    store.push(m);
                    text = text.substring(0, a) + ph + text.substring(b + close.length);
                    s = a + ph.length;
                }
                return text;
            }

            var processed = rawMarkdown;

            // Extract display math first (greedy), then inline
            processed = extractMath(processed, '$$', '$$', mathStore);

            // Extract single $ inline math (same-line only)
            var pos = 0;
            while (pos < processed.length) {
                var a = processed.indexOf('$', pos);
                if (a === -1) break;
                if (a >= 2 && processed.substring(a - 2, a) === '%%') { pos = a + 1; continue; }
                var nl = processed.indexOf('\\n', a + 1);
                var lim = (nl === -1) ? processed.length : nl;
                var b = processed.indexOf('$', a + 1);
                if (b === -1 || b >= lim) { pos = a + 1; continue; }
                var m = processed.substring(a, b + 1);
                var ph = '%%MATH_' + mathStore.length + '%%';
                mathStore.push(m);
                processed = processed.substring(0, a) + ph + processed.substring(b + 1);
                pos = a + ph.length;
            }

            processed = extractMath(processed, '\\\\[', '\\\\]', mathStore);
            processed = extractMath(processed, '\\\\(', '\\\\)', mathStore);

            // Step 2: Parse markdown
            var raw = marked.parse(processed);

            // Step 3: Sanitize
            var safe = DOMPurify.sanitize(raw, { ADD_ATTR: ['target'] });

            // Step 4: Re-insert math blocks
            for (var i = 0; i < mathStore.length; i++) {
                safe = safe.split('%%MATH_' + i + '%%').join(mathStore[i]);
            }

            // Step 5: Set HTML and typeset
            el.innerHTML = safe;
            typesetElement(el);

            rawMarkdown = '';
            smdParser = null;
        }

        function clearLearnContent() {
            document.getElementById('learnContent').innerHTML = '';
            rawMarkdown = '';
            smdParser = null;
        }

        // Show explain card
        function showExplainCard(data) {
            var el = document.getElementById('learnContent');
            el.style.display = '';
            document.getElementById('questionsContainer').style.display = 'none';
            var echo = document.getElementById('currentUserInput');
            el.innerHTML = '';
            if (echo) el.appendChild(echo);

            var card = document.createElement('div');
            card.className = 'concept-card';
            card.innerHTML = '<div class="concept-title">' + escapeHtml(data.conceptName) + '</div>';
            card.innerHTML += '<div class="concept-body">' + escapeHtml(data.conceptExplanation) + '</div>';
            if (data.formulaLatex) {
                card.innerHTML += '<div class="concept-formula">\\\\[' + data.formulaLatex + '\\\\]</div>';
            }
            if (data.strategy) {
                card.innerHTML += '<div class="concept-body" style="font-style:italic;margin-top:4px;">' + escapeHtml(data.strategy) + '</div>';
            }
            if (data.commonMistakes && data.commonMistakes.length > 0) {
                var mHtml = '<div style="margin-top:8px;"><div class="similar-example-label">Common Mistakes</div>';
                for (var i = 0; i < data.commonMistakes.length; i++) {
                    mHtml += '<div class="concept-body" style="padding:2px 0;">\\u2022 ' + escapeHtml(data.commonMistakes[i]) + '</div>';
                }
                mHtml += '</div>';
                card.innerHTML += mHtml;
            }
            el.appendChild(card);
            typesetElement(el);
            showContentArea();
        }

        // Show check feedback
        function showCheckFeedback(data) {
            var el = document.getElementById('learnContent');
            el.style.display = '';
            document.getElementById('questionsContainer').style.display = 'none';
            var echo = document.getElementById('currentUserInput');
            el.innerHTML = '';
            if (echo) el.appendChild(echo);

            var card = document.createElement('div');
            card.className = 'feedback-card';

            var scoreColor = data.correctnessPercentage >= 80 ? 'var(--accent-green)' :
                             data.correctnessPercentage >= 50 ? 'var(--accent-amber)' : 'var(--text-tertiary)';

            var safeFeedback = window.DOMPurify ? DOMPurify.sanitize(data.feedback) : escapeHtml(data.feedback);

            card.innerHTML =
                '<div class="feedback-score">' +
                    '<span style="font:600 18px/1 -apple-system,sans-serif;color:' + scoreColor + ';">' + data.correctnessPercentage + '%</span>' +
                    '<div class="score-bar"><div class="score-fill" style="width:0%;background:' + scoreColor + '"></div></div>' +
                '</div>' +
                '<div class="feedback-text">' + safeFeedback + '</div>';
            if (data.correctFromError) {
                var safeCorr = window.DOMPurify ? DOMPurify.sanitize(data.correctFromError) : escapeHtml(data.correctFromError);
                card.innerHTML += '<div style="margin-top:8px;padding:8px 10px;background:var(--control-bg);border-radius:6px;">' +
                    '<div class="similar-example-label">Correction</div>' +
                    '<div class="feedback-text">' + safeCorr + '</div></div>';
            }
            if (data.encouragement) {
                card.innerHTML += '<div class="feedback-text" style="margin-top:8px;font-style:italic;color:var(--text-tertiary);">' + escapeHtml(data.encouragement) + '</div>';
            }
            el.appendChild(card);
            setTimeout(function() {
                var fill = card.querySelector('.score-fill');
                if (fill) fill.style.width = data.correctnessPercentage + '%';
            }, 100);
            typesetElement(el);
            showContentArea();
        }

        // Normalize LaTeX delimiters: $...$ → \\(...\\), $$...$$ → \\[...\\]
        function normalizeLatex(text) {
            if (!text) return '';
            text = text.replace(/\\$\\$([\\s\\S]*?)\\$\\$/g, '\\\\\\\\[$1\\\\\\\\]');
            text = text.replace(/\\$([^\\$]*?)\\$/g, '\\\\\\\\($1\\\\\\\\)');
            return text;
        }

        // Show quiz card
        var quizData = [];
        function showQuizCard(questions) {
            quizData = questions;
            var el = document.getElementById('learnContent');
            el.style.display = '';
            document.getElementById('questionsContainer').style.display = 'none';
            var echo = document.getElementById('currentUserInput');
            el.innerHTML = '';
            if (echo) el.appendChild(echo);

            var card = document.createElement('div');
            card.className = 'concept-card';
            card.innerHTML = '<div class="concept-title">Practice Quiz</div>';
            card.innerHTML += '<div class="concept-body" style="margin-bottom:8px;">' + questions.length + ' questions based on your session topics</div>';

            for (var i = 0; i < questions.length; i++) {
                var q = questions[i];
                var qDiv = document.createElement('div');
                qDiv.style.cssText = 'padding:8px 0;border-top:0.5px solid var(--separator);';

                var questionDisplay = normalizeLatex(q.questionLatex);
                if (questionDisplay.indexOf('\\\\(') === -1 && questionDisplay.indexOf('\\\\[') === -1) {
                    questionDisplay = '\\\\(' + questionDisplay + '\\\\)';
                }

                qDiv.innerHTML =
                    '<div style="font:500 12px/1.5 -apple-system,sans-serif;color:var(--text-primary);margin-bottom:4px;">' +
                        '<span style="color:var(--text-tertiary);margin-right:6px;">' + q.quizId + '</span>' +
                        questionDisplay +
                    '</div>' +
                    '<div style="display:flex;gap:6px;align-items:center;">' +
                        '<input type="text" id="quiz-input-' + q.quizId + '" ' +
                            'style="flex:1;background:var(--control-bg);border:0.5px solid var(--separator);border-radius:6px;' +
                            'padding:6px 10px;font:400 12px/1 -apple-system,sans-serif;color:var(--text-primary);outline:none;" ' +
                            'placeholder="Your answer...">' +
                        '<button onclick="checkQuizAnswer(\\'' + q.quizId + '\\')" ' +
                            'style="background:var(--control-bg);border:0.5px solid var(--separator);border-radius:6px;' +
                            'padding:6px 10px;font:500 11px/1 -apple-system,sans-serif;color:var(--text-secondary);cursor:pointer;">Check</button>' +
                    '</div>' +
                    '<div id="quiz-result-' + q.quizId + '" style="display:none;margin-top:4px;font:400 11px/1.4 -apple-system,sans-serif;"></div>';
                card.appendChild(qDiv);
            }
            el.appendChild(card);
            typesetElement(el);
            showContentArea();
        }

        function checkQuizAnswer(quizId) {
            var input = document.getElementById('quiz-input-' + quizId);
            var resultDiv = document.getElementById('quiz-result-' + quizId);
            if (!input || !resultDiv) return;
            var userAnswer = input.value.trim();
            if (!userAnswer) return;
            var question = quizData.find(function(q) { return q.quizId === quizId; });
            if (!question) return;
            resultDiv.style.display = 'block';
            resultDiv.innerHTML =
                '<div style="color:var(--text-secondary);">Correct answer: ' + normalizeLatex(question.correctAnswerLatex) + '</div>' +
                (question.hint ? '<div style="color:var(--text-tertiary);font-style:italic;margin-top:2px;">' + escapeHtml(question.hint) + '</div>' : '');
            typesetElement(resultDiv);
            window.webkit.messageHandlers.overlay.postMessage({action:'quizAnswer', quizId:quizId, userAnswer:userAnswer});
        }

        // MARK: - Helpers

        function typesetElement(el) {
            if (window.MathJax && MathJax.typesetPromise) {
                MathJax.typesetClear([el]);
                MathJax.typesetPromise([el]).catch(function(){});
            } else if (window.MathJax && MathJax.startup && MathJax.startup.promise) {
                MathJax.startup.promise.then(function() {
                    MathJax.typesetClear([el]);
                    MathJax.typesetPromise([el]).catch(function(){});
                });
            }
        }

        function escapeHtml(s) {
            return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        }

        // Legacy compat — old coordinator calls these
        function showResponseArea() { showContentArea(); }
        function hideResponseArea() { hideContentArea(); }
        function showAutosolvePanel() {}
        function clearAutosolvePanel() {}
        function refreshAutoSolveUI(headerText, answers) {
            // Convert old format to new
            var qs = [];
            for (var i = 0; i < answers.length; i++) {
                var a = answers[i];
                qs.push({
                    id: a.id,
                    state: a.solving ? 'solving' : (a.failed ? 'failed' : 'solved'),
                    latex: a.latex,
                    copyable: a.copyable,
                    page: a.page,
                    steps: null
                });
            }
            refreshStudyUI(headerText, 'active', qs);
        }

        </script>

        <script>
        // Drag handling
        document.querySelector('.status-bar').addEventListener('mousedown', function(e) {
            if (e.target.closest('.mode-toggle') || e.target.closest('.stop-btn')) return;
            e.preventDefault();
            window.webkit.messageHandlers.overlay.postMessage({action:'dragStart', x: e.screenX, y: e.screenY});
            function onUp() {
                window.webkit.messageHandlers.overlay.postMessage({action:'dragEnd'});
                document.removeEventListener('mouseup', onUp);
            }
            document.addEventListener('mouseup', onUp);
        });
        // Nudge click — status label shows "Need help with Q1B?"
        document.getElementById('statusLabel').addEventListener('click', function() {
            var text = this.textContent;
            if (text.startsWith('Need help with Q')) {
                var match = text.match(/Need help with Q(.+)\\?/);
                if (match) {
                    window.webkit.messageHandlers.overlay.postMessage({action:'nudgeAccepted', id: match[1]});
                }
            }
        });
        setTheme(\(isDarkMode));
        </script>
        </body></html>
        """
    }

    // MARK: - Study Suggestion HTML

    private func suggestionHTML(text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html><html>
        \(sharedHead(extraStyle: """
        body { display: flex; flex-direction: column; height: 100vh; }
        .suggestion-body { flex: 1; padding: 14px 16px; display: flex; flex-direction: column; gap: 10px; }
        .suggestion-header { display: flex; align-items: center; justify-content: space-between; }
        .suggestion-title { font-size: 13px; font-weight: 600; color: var(--text); }
        .suggestion-close { background: none; border: none; color: var(--text-dim); cursor: pointer; font-size: 13px; padding: 2px 4px; }
        .suggestion-close:hover { color: var(--text); }
        .suggestion-text { font-size: 13px; color: var(--text-dim); line-height: 1.4; }
        .suggestion-actions { display: flex; gap: 8px; align-items: center; }
        .btn-accept {
            background: var(--subtle-bg); border: 1px solid var(--subtle-border);
            border-radius: 6px; color: var(--text); font-size: 12px; font-weight: 500;
            padding: 5px 14px; cursor: pointer; font-family: -apple-system, sans-serif;
            transition: background 0.15s;
        }
        .btn-accept:hover { background: var(--subtle-border); }
        .btn-dismiss {
            background: none; border: none; color: var(--text-dim); font-size: 12px;
            cursor: pointer; font-family: -apple-system, sans-serif; padding: 5px 8px;
        }
        .btn-dismiss:hover { color: var(--text); }
        """))
        <body>
        <div class="suggestion-body">
            <div class="suggestion-header">
                <span class="suggestion-title">Presto</span>
                <button class="suggestion-close" onclick="dismiss()">&times;</button>
            </div>
            <div class="suggestion-text">\(escaped)</div>
            <div class="suggestion-actions">
                <button class="btn-accept" onclick="accept()">Yes, help me</button>
                <button class="btn-dismiss" onclick="dismiss()">Dismiss</button>
            </div>
        </div>
        <script>
        function accept() { window.webkit.messageHandlers.overlay.postMessage({action:'suggestionAccept'}); }
        function dismiss() { window.webkit.messageHandlers.overlay.postMessage({action:'suggestionDismiss'}); }
        setTheme(\(isDarkMode));
        </script>
        </body></html>
        """
    }

    // MARK: - Study Summary HTML

    private func summaryHTML(text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html><html>
        \(sharedHead(extraStyle: """
        body { display: flex; align-items: center; justify-content: center; height: 100vh; }
        .summary { display: flex; align-items: center; gap: 8px; padding: 0 16px; }
        .check { font-size: 15px; color: var(--text-dim); }
        .summary-text { font-size: 13px; color: var(--text-dim); }
        """))
        <body>
        <div class="summary">
            <span class="check">&#10003;</span>
            <span class="summary-text">\(escaped)</span>
        </div>
        <script>setTheme(\(isDarkMode));</script>
        </body></html>
        """
    }

}
