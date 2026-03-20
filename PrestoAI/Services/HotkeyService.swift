import Carbon
import AppKit

// ============================================================================
// Carbon RegisterEventHotKey — same API that Hammerspoon uses internally.
// Works system-wide, no Accessibility permission required for hotkeys.
// ============================================================================

class HotkeyService {
    static let shared = HotkeyService()
    
    private var eventHandlerRef: EventHandlerRef?
    private var captureHotKeyRef: EventHotKeyRef?
    private var quickPromptHotKeyRef: EventHotKeyRef?
    private var escHotKeyRef: EventHotKeyRef?
    private var studyModeHotKeyRef: EventHotKeyRef?

    var onCapture: (() -> Void)?
    var onQuickPrompt: (() -> Void)?
    var onEsc: (() -> Void)?
    var onStudyModeToggle: (() -> Void)?
    
    private init() {
        installCarbonHandler()
    }
    
    // MARK: - Carbon Event Handler (one handler for all hotkeys)
    
    private func installCarbonHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        // Pass `self` as userData so the C callback can route back to us
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
                guard let event = event, let userData = userData else {
                    return OSStatus(eventNotHandledErr)
                }
                
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr else { return result }
                
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    service.handleHotKey(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        
        print("[Hotkey] Carbon event handler installed: \(status == noErr)")
    }
    
    // MARK: - Register / Unregister
    
    /// Register Cmd+Shift+X globally (call once at app launch)
    func registerCapture() {
        let hotKeyID = EventHotKeyID(signature: hotKeySignature(), id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_X),           // keycode for X
            UInt32(cmdKey | shiftKey),     // modifiers
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &captureHotKeyRef
        )
        print("[Hotkey] Cmd+Shift+X registered: \(status == noErr)")
    }

    /// Register Cmd+Shift+Z globally (call once at app launch)
    func registerQuickPrompt() {
        let hotKeyID = EventHotKeyID(signature: hotKeySignature(), id: 3)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_Z),           // keycode for Z
            UInt32(cmdKey | shiftKey),     // modifiers
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &quickPromptHotKeyRef
        )
        print("[Hotkey] Cmd+Shift+Z registered: \(status == noErr)")
    }

    /// Register Cmd+Shift+S globally (call once at app launch)
    func registerStudyMode() {
        let hotKeyID = EventHotKeyID(signature: hotKeySignature(), id: 4)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_S),           // keycode for S
            UInt32(cmdKey | shiftKey),     // modifiers
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &studyModeHotKeyRef
        )
        print("[Hotkey] Cmd+Shift+S registered: \(status == noErr)")
    }
    
    /// Register ESC globally (call when overlay appears)
    func registerEsc() {
        guard escHotKeyRef == nil else { return } // already registered
        let hotKeyID = EventHotKeyID(signature: hotKeySignature(), id: 2)
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),            // keycode for ESC
            0,                             // no modifiers
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &escHotKeyRef
        )
        print("[Hotkey] ESC registered: \(status == noErr)")
    }
    
    /// Unregister ESC (call when overlay is dismissed, so ESC works normally in other apps)
    func unregisterEsc() {
        guard let ref = escHotKeyRef else { return }
        UnregisterEventHotKey(ref)
        escHotKeyRef = nil
        print("[Hotkey] ESC unregistered")
    }
    
    // MARK: - Dispatch
    
    func handleHotKey(id: UInt32) {
        switch id {
        case 1:
            print("[Hotkey] Cmd+Shift+X fired")
            onCapture?()
        case 2:
            print("[Hotkey] ESC fired")
            onEsc?()
        case 3:
            print("[Hotkey] Cmd+Shift+Z fired")
            onQuickPrompt?()
        case 4:
            print("[Hotkey] Cmd+Shift+S fired")
            onStudyModeToggle?()
        default:
            break
        }
    }
    
    // MARK: - Helpers
    
    /// FourCharCode "PRST" as OSType
    private func hotKeySignature() -> OSType {
        let chars: [UInt8] = [0x50, 0x52, 0x53, 0x54] // P R S T
        return OSType(chars[0]) << 24 | OSType(chars[1]) << 16 | OSType(chars[2]) << 8 | OSType(chars[3])
    }
    
    deinit {
        if let ref = captureHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = quickPromptHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = escHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = studyModeHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
    }
}
