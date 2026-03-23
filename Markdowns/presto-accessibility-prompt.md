# Task: Add Accessibility Tree Scanner to Presto AI

## Project Context
- Presto AI is a macOS menu bar app at `/Volumes/T7/PrestoAI/`
- Bundle ID: `ai.presto.PrestoAI`
- Built with Swift/SwiftUI
- Already has global hotkey system (Cmd+Shift+X for screenshot capture)
- Already has screen capture via CGWindowListCreateImage or ScreenCaptureKit
- Already has a floating WKWebView overlay for displaying results
- Already has Claude API integration with streaming SSE responses

## What to Build
Add a new global hotkey **Cmd+Shift+D** that triggers a full accessibility tree scan of the frontmost application and displays every interactive element on screen.

## Implementation Requirements

### 1. Accessibility Permission Check
- On first trigger of Cmd+Shift+D, check if the app has Accessibility access via `AXIsProcessTrusted()`
- If not granted, show a prompt explaining why it's needed and open System Preferences > Privacy & Security > Accessibility using:
  ```swift
  AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
  ```
- Do not proceed with scanning until permission is confirmed

### 2. Global Hotkey Registration
- Register Cmd+Shift+D using the same hotkey system already used for Cmd+Shift+X
- The hotkey should work globally, regardless of which app is focused

### 3. Accessibility Tree Walker
Create a new file `AccessibilityScanner.swift` with a class that:

- Gets the PID of the frontmost application via `NSWorkspace.shared.frontmostApplication?.processIdentifier`
- Creates an AXUIElement for that app via `AXUIElementCreateApplication(pid)`
- Recursively walks the element tree extracting ALL interactive elements
- For each element, extract:
  - `kAXRoleAttribute` (button, textField, checkBox, menuItem, link, popUpButton, slider, etc.)
  - `kAXTitleAttribute` (visible label)
  - `kAXDescriptionAttribute` (accessibility description)
  - `kAXValueAttribute` (current value for text fields, checkbox state, etc.)
  - `kAXPositionAttribute` (screen coordinates as CGPoint)
  - `kAXSizeAttribute` (element dimensions as CGSize)
  - `kAXEnabledAttribute` (is it interactable)
  - `kAXRoleDescriptionAttribute` (human-readable role)
  - Available actions via `AXUIElementCopyActionNames`
- Filter to only interactive/relevant roles: buttons, text fields, checkboxes, links, menu items, pop-up buttons, sliders, tabs, radio buttons, text areas, combo boxes, scroll bars, toolbars
- Skip decorative/container elements that aren't directly interactable unless they contain interactable children
- Assign each element a sequential index (1, 2, 3...)
- Handle errors gracefully -- some elements will refuse to return attributes, just skip them
- Set a max recursion depth of 15 to avoid infinite loops
- Set a timeout of 3 seconds for the full scan -- abort and return partial results if exceeded

The walker should return an array of structs:

```swift
struct ScannedElement {
    let index: Int
    let role: String
    let title: String?
    let description: String?
    let value: String?
    let position: CGPoint
    let size: CGSize
    let isEnabled: Bool
    let actions: [String]
    let appName: String
}
```

### 4. Screen Capture with Overlay Badges
When Cmd+Shift+D is pressed:

1. Run the accessibility scan on the frontmost app
2. Capture a screenshot of the frontmost window (reuse existing screenshot logic)
3. Create an overlay image that draws numbered badges on top of each scanned element's position:
   - Small colored circle (red or orange, ~20px diameter) with white number text
   - Position each badge at the top-left corner of the element's frame
   - Use Core Graphics to composite badges onto the screenshot
4. Generate a text summary of all elements in this format:
   ```
   [1] Button "Save" (412, 305) 80x32
   [2] TextField "Email" value:"user@test.com" (200, 180) 250x28
   [3] CheckBox "Remember me" value:checked (200, 220) 18x18
   [4] Link "Forgot password?" (200, 250) 120x16
   [5] PopUpButton "Country" value:"United States" (200, 290) 200x28
   ```

### 5. Display Results
Use the existing Presto overlay (WKWebView) to show:
- The annotated screenshot (with numbered badges)
- The text element list below it
- Store both the image and text list in memory so they can be sent to Claude API on follow-up

### 6. Action Execution (Foundation)
Create `AccessibilityExecutor.swift` that can perform actions on scanned elements:

```swift
class AccessibilityExecutor {
    // Store the last scan's element references (actual AXUIElement refs, not just data)
    private var elementMap: [Int: AXUIElement] = [:]
    
    func click(elementIndex: Int) -> Bool
    // Uses AXUIElementPerformAction(element, kAXPressAction)
    
    func type(elementIndex: Int, text: String) -> Bool
    // Uses AXUIElementSetAttributeValue(element, kAXValueAttribute, text)
    // Then posts AXValueChanged notification
    
    func focus(elementIndex: Int) -> Bool
    // Uses AXUIElementSetAttributeValue(element, kAXFocusedAttribute, true)
    
    func getValue(elementIndex: Int) -> String?
    // Reads current kAXValueAttribute
}
```

**Important**: The elementMap must store actual AXUIElement references from the scan, not recreated ones. The scan and execution must share the same references.

### 7. Integration with Existing Presto Flow
The long-term flow will be:
1. User presses Cmd+Shift+D → scan + annotated screenshot
2. User types a command in Presto overlay ("click Sign In", "fill the email field with test@test.com")
3. Presto sends the annotated screenshot + element list + user command to Claude API
4. Claude responds with action instructions ("click 3", "type 2 test@test.com")
5. Presto executes via AccessibilityExecutor

For now, just build steps 1-2 and the executor foundation. Do NOT modify the existing Cmd+Shift+X screenshot flow. This is a parallel feature.

### 8. Entitlements
Add to the app's entitlements if not already present:
- `com.apple.security.automation.apple-events` (for accessibility access)

In Info.plist, add or update:
- `NSAccessibilityUsageDescription` with a clear explanation string

## File Structure
Add these new files:
```
PrestoAI/
├── Accessibility/
│   ├── AccessibilityScanner.swift
│   ├── AccessibilityExecutor.swift
│   ├── AccessibilityOverlay.swift  (badge rendering logic)
│   └── ScannedElement.swift (the data model)
```

## What NOT to Do
- Do not modify existing Cmd+Shift+X capture flow
- Do not modify existing overlay display logic beyond reusing it
- Do not add any third-party dependencies
- Do not use private APIs -- stick to the public AX framework
- Do not attempt to scan all windows/apps, only the frontmost app
- Do not block the main thread -- run the scan on a background queue and dispatch results to main

## Testing
After implementation, pressing Cmd+Shift+D with any app in the foreground (Safari, Finder, System Settings) should:
1. Show the accessibility permission prompt if not yet granted
2. After granting, capture and display an annotated screenshot with numbered badges on every interactive element
3. Print the element list to the overlay and to the Xcode console for debugging
