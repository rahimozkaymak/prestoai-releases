import AppKit
import Foundation

/// Provides interaction guides ("skills") for apps and websites.
/// Skills tell Haiku how to use specific apps — where to click, how to search, what success looks like.
/// Built-in skills for common apps, auto-generates and caches skills for unknown apps.
class AppSkills {

    static let shared = AppSkills()

    /// Cache of auto-generated skills (bundle ID or website key → skill text)
    private var generatedSkills: [String: String] = [:]
    private let cacheFile: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PrestoAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        cacheFile = support.appendingPathComponent("learned_skills.json")
        loadCache()
    }

    // MARK: - Public API

    /// Get skill instructions for the current context.
    /// Checks: built-in app skill → built-in website skill (from OCR) → cached skill → nil
    func getSkill(for app: NSRunningApplication, ocrText: [String]) -> String? {
        let bundleID = app.bundleIdentifier ?? ""

        // 1. Built-in app skill
        if let skill = builtInAppSkills[bundleID] {
            return skill
        }

        // 2. For browsers, check website skills
        if isBrowser(bundleID) {
            if let websiteSkill = detectWebsiteSkill(from: ocrText) {
                return websiteSkill
            }
        }

        // 3. Cached auto-generated skill
        if let cached = generatedSkills[bundleID] {
            return cached
        }

        return nil
    }

    /// Generate and cache a skill for an unknown app using Sonnet.
    /// Call this once at the start of automation if getSkill returns nil.
    func generateSkill(for app: NSRunningApplication, base64Screenshot: String, elementList: String, completion: @escaping (String?) -> Void) {
        let bundleID = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? "this app"

        let prompt = """
        You are looking at a screenshot of "\(appName)" (bundle: \(bundleID)).

        Write a concise interaction guide for an AI agent that needs to control this app.
        Describe in 5-10 bullet points:
        - Where is the search bar / main input?
        - How to navigate (sidebar, tabs, back/forward)?
        - How to trigger the main action (play, open, send, submit)?
        - What does success look like (what changes on screen)?
        - Any quirks (e.g., need to wait for loading, double-click vs single-click)?

        ELEMENT LIST (what the agent can see):
        \(elementList.prefix(2000))

        Return ONLY the bullet points. No intro, no markdown headers. Keep it under 300 words.
        """

        var fullResponse = ""
        APIService.shared.sendScreenshot(
            base64Screenshot,
            prompt: prompt,
            model: "claude-sonnet-4-6",
            onChunk: { chunk in fullResponse += chunk },
            onComplete: { [weak self] _, _ in
                let skill = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !skill.isEmpty else { completion(nil); return }

                let formatted = "APP SKILL FOR \(appName.uppercased()):\n\(skill)"
                self?.generatedSkills[bundleID] = formatted
                self?.saveCache()
                print("[Skills] Generated skill for \(appName)")
                completion(formatted)
            },
            onError: { error in
                print("[Skills] Failed to generate skill: \(error.localizedDescription)")
                completion(nil)
            }
        )
    }

    /// Generate and cache a skill for a website detected in a browser.
    func generateWebsiteSkill(websiteKey: String, base64Screenshot: String, elementList: String, completion: @escaping (String?) -> Void) {
        let prompt = """
        You are looking at a screenshot of the website "\(websiteKey)".

        Write a concise interaction guide for an AI agent that needs to fill in forms / complete tasks on this website.
        Describe in 5-10 bullet points:
        - What type of site is this (homework, email, social media, search engine)?
        - Where are the input fields / answer boxes?
        - How are questions structured (numbered, labeled, grouped)?
        - How to submit answers (submit button location, auto-submit)?
        - What does success/failure look like (green checkmark, red X, score)?
        - Any quirks (iframes, popups, MathJax rendering delays)?

        ELEMENT LIST:
        \(elementList.prefix(2000))

        Return ONLY the bullet points. No intro, no markdown headers. Keep it under 300 words.
        """

        var fullResponse = ""
        APIService.shared.sendScreenshot(
            base64Screenshot,
            prompt: prompt,
            model: "claude-sonnet-4-6",
            onChunk: { chunk in fullResponse += chunk },
            onComplete: { [weak self] _, _ in
                let skill = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !skill.isEmpty else { completion(nil); return }

                let formatted = "WEBSITE SKILL FOR \(websiteKey.uppercased()):\n\(skill)"
                self?.generatedSkills["web:\(websiteKey)"] = formatted
                self?.saveCache()
                print("[Skills] Generated skill for website: \(websiteKey)")
                completion(formatted)
            },
            onError: { error in
                print("[Skills] Failed to generate website skill: \(error.localizedDescription)")
                completion(nil)
            }
        )
    }

    // MARK: - Browser Detection

    private func isBrowser(_ bundleID: String) -> Bool {
        let browsers: Set<String> = [
            "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox",
            "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
            "com.operasoftware.Opera", "com.vivaldi.Vivaldi"
        ]
        return browsers.contains(bundleID)
    }

    // MARK: - Website Detection from OCR

    private func detectWebsiteSkill(from ocrText: [String]) -> String? {
        let allText = ocrText.joined(separator: " ").lowercased()

        for (keywords, skill) in builtInWebsiteSkills {
            if keywords.contains(where: { allText.contains($0) }) {
                return skill
            }
        }

        // Check cached website skills
        for (key, skill) in generatedSkills where key.hasPrefix("web:") {
            let websiteName = String(key.dropFirst(4)).lowercased()
            if allText.contains(websiteName) {
                return skill
            }
        }

        return nil
    }

    /// Detect the website name from OCR text for auto-generation
    func detectWebsiteName(from ocrText: [String]) -> String? {
        let allText = ocrText.joined(separator: " ").lowercased()

        // Known website patterns
        let patterns: [(keywords: [String], name: String)] = [
            (["webassign", "cengage"], "WebAssign"),
            (["pearson", "mylab", "mastering"], "Pearson MyLab"),
            (["canvas", "instructure"], "Canvas"),
            (["chegg"], "Chegg"),
            (["mcgraw", "connect", "aleks"], "McGraw-Hill"),
            (["google.com", "google search"], "Google"),
            (["youtube.com", "youtube"], "YouTube"),
            (["gmail"], "Gmail"),
            (["docs.google"], "Google Docs"),
            (["github.com", "github"], "GitHub"),
            (["stackoverflow", "stack overflow"], "StackOverflow"),
            (["reddit.com", "reddit"], "Reddit"),
            (["amazon.com", "amazon"], "Amazon"),
        ]

        for pattern in patterns {
            if pattern.keywords.contains(where: { allText.contains($0) }) {
                return pattern.name
            }
        }

        // Try to extract domain from URL bar text
        for text in ocrText {
            let t = text.lowercased().trimmingCharacters(in: .whitespaces)
            if t.contains(".com") || t.contains(".edu") || t.contains(".org") || t.contains(".io") {
                // Looks like a URL — extract domain
                let cleaned = t.replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                    .replacingOccurrences(of: "www.", with: "")
                if let slash = cleaned.firstIndex(of: "/") {
                    return String(cleaned[..<slash])
                }
                return cleaned.count < 50 ? cleaned : nil
            }
        }

        return nil
    }

    // MARK: - Persistence

    private func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheFile.path),
              let data = try? Data(contentsOf: cacheFile),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        generatedSkills = dict
        print("[Skills] Loaded \(dict.count) cached skills")
    }

    private func saveCache() {
        guard let data = try? JSONSerialization.data(withJSONObject: generatedSkills, options: .prettyPrinted) else { return }
        try? data.write(to: cacheFile)
    }

    // MARK: - Built-in App Skills

    private let builtInAppSkills: [String: String] = [

        "com.spotify.client": """
        APP SKILL FOR SPOTIFY:
        - To play a song: Click the search bar "What do you want to play?" at the top center, TYPE the song/artist name, WAIT 1-2s for results to appear below, then CLICK the song row in the results. A single click on a song row starts playback.
        - The search bar is always visible at the top. It has a magnifying glass icon and placeholder text.
        - After searching, results appear as a list with song titles, artist names, and durations. Click anywhere on the song row to play it.
        - Playback controls are at the bottom: previous (⏮), play/pause (▶/⏸), next (⏭), progress bar with timestamps.
        - SUCCESS: If you can see a pause button (⏸) at the bottom and the progress bar shows time (e.g., "0:02 / 3:45"), the song IS playing. Say DONE immediately.
        - The left sidebar has navigation: Home, Search, Library. Playlists are listed below.
        - Do NOT press Enter after typing in the search bar — results appear automatically as you type.
        - Do NOT double-click songs — a single click plays them.
        """,

        "com.apple.finder": """
        APP SKILL FOR FINDER:
        - Navigation: sidebar on the left shows favorites (Desktop, Documents, Downloads, etc.), devices, and tags.
        - To open a folder: double-click it. To go back: click the back arrow or Cmd+[.
        - To open a file: double-click it. It opens in the default app for that file type.
        - Search: click the search icon (magnifying glass) in the top-right toolbar, or the search field if visible. Type the filename.
        - View modes: icons, list, columns, gallery — buttons in the toolbar.
        - Path bar at the bottom shows current location. You can click path components to navigate.
        - To create a new folder: right-click in empty space → New Folder, or use the File menu.
        """,

        "com.apple.systempreferences": """
        APP SKILL FOR SYSTEM SETTINGS:
        - Search bar is at the top left — type to find any setting quickly.
        - Left sidebar shows categories: Wi-Fi, Bluetooth, Network, Sound, Display, etc.
        - Click a category to see its settings on the right side.
        - Toggle switches are used for on/off settings — click to toggle.
        - Some settings have sub-pages — click the row to drill in, use back arrow to go back.
        - Changes are usually applied immediately, no save button needed.
        """,

        "com.apple.Safari": """
        APP SKILL FOR SAFARI:
        - URL/search bar is at the top center. Click it to focus, TYPE a URL or search query, press Enter.
        - Tabs are shown at the top. Click a tab to switch, click + to open new tab.
        - Back/forward buttons are at the top left.
        - To interact with a webpage: look at the page content in the element list. Web forms, buttons, links are detected.
        - Bookmarks: click the sidebar icon or bookmarks bar below the tab bar.
        """,

        "com.google.Chrome": """
        APP SKILL FOR CHROME:
        - URL/search bar (omnibox) is at the top center. Click it to focus, TYPE a URL or search query, press Enter.
        - Tabs are at the top. Click a tab to switch, click + to open new tab.
        - Back/forward buttons are at the top left of the toolbar.
        - To interact with a webpage: look at the page content in the element list. Web forms, buttons, links are detected.
        - Extensions are in the top-right toolbar area (puzzle piece icon).
        - Downloads appear at the bottom of the screen or in the downloads shelf.
        """,

        "com.apple.MobileSMS": """
        APP SKILL FOR MESSAGES:
        - Conversation list on the left. Click a conversation to open it.
        - To send a new message: click the compose button (pencil icon) at the top.
        - Message input is at the bottom of the conversation — click it, TYPE the message, press Enter to send.
        - To search conversations: use the search bar at the top of the conversation list.
        - SUCCESS: If your typed message appears in the conversation as a sent bubble, it was sent. Say DONE.
        """,

        "com.apple.mail": """
        APP SKILL FOR MAIL:
        - Sidebar on left: mailboxes (Inbox, Sent, Drafts, etc.). Click to view.
        - Message list in the middle. Click a message to read it on the right.
        - To compose: click the compose button (pencil/paper icon) in the toolbar.
        - In compose: To field at top, Subject below, body below that. Type in each field, use Tab to move between them.
        - Send button is at the top of the compose window (paper airplane icon or blue send button).
        - Search bar is at the top of the message list.
        """,
    ]

    // MARK: - Built-in Website Skills

    /// Each entry: ([keywords to detect], skill text)
    private let builtInWebsiteSkills: [([String], String)] = [

        (["webassign", "cengage"], """
        WEBSITE SKILL FOR WEBASSIGN (CENGAGE):
        - This is a homework platform. Questions are numbered and stacked vertically.
        - Answer boxes are small white input fields next to labels like "R =", "I =", "f(x) =".
        - Some questions have multiple answer boxes (e.g., radius AND interval of convergence).
        - Input fields may be inside iframes — they still appear as detected elements.
        - After typing an answer, press Tab to move to the next field or click the next box directly.
        - Submit button: look for "Submit Assignment" or "Submit" at the bottom of the page. Individual questions may have their own submit/check buttons.
        - Correct answers show a green checkmark (✓). Wrong answers show a red X (✗) and the box may turn red.
        - If a box already has text and shows a red X, click the box, select all (Cmd+A), then type the new answer.
        - Math notation: use standard text like (-1, 1) for intervals, INF or infinity for ∞, DNE for "does not exist".
        - The page may be long — scroll down to see more questions.
        - MathJax renders equations — wait 1-2s after page load for equations to render before reading them.
        """),

        (["pearson", "mylab", "mastering"], """
        WEBSITE SKILL FOR PEARSON MYLAB/MASTERING:
        - Homework platform similar to WebAssign. Questions are numbered.
        - Answer boxes are input fields near question text.
        - Some questions use dropdowns — click to open, then click the correct option.
        - Multiple choice questions use radio buttons — click the correct option.
        - "Check Answer" button submits individual questions.
        - Correct: green highlight. Incorrect: red highlight with "Try Again" option.
        - Math palette may appear for special symbols — prefer typing text notation instead.
        - Navigation between questions: "Previous" and "Next" buttons, or a question list sidebar.
        """),

        (["canvas", "instructure"], """
        WEBSITE SKILL FOR CANVAS:
        - Learning management system with assignments, quizzes, and discussions.
        - Quiz questions may be multiple choice (radio buttons), multiple select (checkboxes), or free response (text areas).
        - Submit button is usually "Submit Quiz" at the bottom.
        - Navigation: sidebar has links to modules, assignments, grades, etc.
        - File upload questions have a "Choose File" or drag-and-drop area.
        - Time limit may be shown at the top if it's a timed quiz.
        """),

        (["chegg"], """
        WEBSITE SKILL FOR CHEGG:
        - Homework help and textbook solutions platform.
        - Search bar at the top — type a question or ISBN to find solutions.
        - Solutions are shown step-by-step. May need to scroll to see all steps.
        - Expert Q&A sections have answer boxes for follow-up questions.
        - Some content is behind a paywall — look for "Subscribe" or "Unlock" prompts.
        """),

        (["google.com", "google search"], """
        WEBSITE SKILL FOR GOOGLE SEARCH:
        - Search bar is the large input field at the center (or top after searching).
        - Type the query, press Enter to search.
        - Results appear as blue links with snippets below. Click a result to visit the page.
        - "People also ask" sections expand when clicked.
        - Image/video/news tabs are below the search bar to filter results.
        - SUCCESS: Search results are visible on screen after pressing Enter. Navigate to specific results by clicking them.
        """),

        (["youtube.com", "youtube"], """
        WEBSITE SKILL FOR YOUTUBE:
        - Search bar is at the top center with a magnifying glass button.
        - Type the query, press Enter or click the search icon.
        - Video thumbnails appear in results — click a thumbnail to play the video.
        - The video player has play/pause, volume, fullscreen, and progress bar controls.
        - SUCCESS: If the video player is visible and has a pause button, the video is playing. Say DONE.
        - To like/subscribe: buttons are below the video title.
        """),

        (["gmail"], """
        WEBSITE SKILL FOR GMAIL:
        - Compose: click the "Compose" button (usually bottom-left or top-left).
        - In compose: To field, Subject, Body. Tab between them. Click Send (blue button) to send.
        - Inbox: emails listed in the center. Click to open, click back arrow to return.
        - Search bar at the top — type to search emails.
        - Labels/folders in the left sidebar: Inbox, Sent, Drafts, etc.
        - SUCCESS: After sending, look for "Message sent" notification at the bottom.
        """),
    ]
}
