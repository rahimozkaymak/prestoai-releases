import Foundation
import AppKit
import CoreGraphics

enum CaptureError: LocalizedError {
    case noPermission
    case cancelled
    case encodingFailed
    case noImage
    
    var errorDescription: String? {
        switch self {
        case .noPermission: return "Screen recording permission required. Enable in System Settings → Privacy & Security → Screen Recording."
        case .cancelled: return "Screenshot cancelled."
        case .encodingFailed: return "Failed to encode screenshot."
        case .noImage: return "No image captured."
        }
    }
}

class ScreenCaptureService {
    
    /// Interactive region selection → returns base64 PNG
    static func captureInteractive() async throws -> String {
        print("[Capture] Starting interactive capture → clipboard")

        // Clear clipboard before capture so we can detect cancellation
        await MainActor.run { NSPasteboard.general.clearContents() }

        // Run the blocking Process on a background thread
        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    process.arguments = ["-i", "-x", "-c"]

                    try process.run()
                    process.waitUntilExit()

                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard status == 0 else {
            print("[Capture] screencapture exited with status \(status)")
            throw CaptureError.cancelled
        }

        let images = await MainActor.run {
            NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
        }

        guard let nsImage = images?.first else {
            print("[Capture] No image on clipboard — user cancelled")
            throw CaptureError.cancelled
        }

        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodingFailed
        }

        print("[Capture] Got \(pngData.count) bytes from clipboard, encoding to base64")
        return pngData.base64EncodedString()
    }
    
    /// Check if screen recording permission is granted
    static func hasPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    /// Request screen recording permission
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }
}
