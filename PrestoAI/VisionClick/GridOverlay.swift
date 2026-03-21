import AppKit

struct GridConfig {
    let cellSize: Int
    let lineColor: NSColor
    let lineWidth: CGFloat
    let labelFont: NSFont
    let labelColor: NSColor
    let labelShadowColor: NSColor
}

class GridOverlay {

    static let defaultConfig = GridConfig(
        cellSize: 50,
        lineColor: NSColor.white.withAlphaComponent(0.15),
        lineWidth: 0.5,
        labelFont: NSFont.monospacedSystemFont(ofSize: 7, weight: .regular),
        labelColor: NSColor.white.withAlphaComponent(0.85),
        labelShadowColor: NSColor.black.withAlphaComponent(0.6)
    )

    /// Draws a coordinate grid on the screenshot.
    /// Columns: A, B, C… across the top. Rows: 1, 2, 3… down the left.
    static func applyGrid(to image: NSImage, config: GridConfig = defaultConfig) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()

        image.draw(in: NSRect(origin: .zero, size: size))

        let cs = CGFloat(config.cellSize)
        let cols = Int(ceil(size.width / cs))
        let rows = Int(ceil(size.height / cs))

        // Draw grid lines
        config.lineColor.setStroke()
        let linePath = NSBezierPath()
        linePath.lineWidth = config.lineWidth

        for c in 1..<cols {
            let x = CGFloat(c) * cs
            linePath.move(to: NSPoint(x: x, y: 0))
            linePath.line(to: NSPoint(x: x, y: size.height))
        }
        for r in 1..<rows {
            let y = size.height - CGFloat(r) * cs  // flip Y for NSImage
            linePath.move(to: NSPoint(x: 0, y: y))
            linePath.line(to: NSPoint(x: size.width, y: y))
        }
        linePath.stroke()

        // Shadow for labels
        let shadow = NSShadow()
        shadow.shadowColor = config.labelShadowColor
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.shadowBlurRadius = 0

        let attrs: [NSAttributedString.Key: Any] = [
            .font: config.labelFont,
            .foregroundColor: config.labelColor,
            .shadow: shadow
        ]

        // Column labels along top edge
        for c in 0..<cols {
            let label = columnLabel(for: c)
            let x = CGFloat(c) * cs + cs / 2
            let labelSize = (label as NSString).size(withAttributes: attrs)
            let pt = NSPoint(x: x - labelSize.width / 2, y: size.height - labelSize.height - 2)
            (label as NSString).draw(at: pt, withAttributes: attrs)
        }

        // Row labels along left edge
        for r in 0..<rows {
            let label = "\(r + 1)"
            let y = size.height - CGFloat(r) * cs - cs / 2
            let labelSize = (label as NSString).size(withAttributes: attrs)
            let pt = NSPoint(x: 2, y: y - labelSize.height / 2)
            (label as NSString).draw(at: pt, withAttributes: attrs)
        }

        result.unlockFocus()
        return result
    }

    /// Spreadsheet-style column label: 0=A, 1=B, …, 25=Z, 26=AA, 27=AB…
    static func columnLabel(for index: Int) -> String {
        var idx = index
        var label = ""
        repeat {
            label = String(Character(UnicodeScalar(65 + (idx % 26))!)) + label
            idx = idx / 26 - 1
        } while idx >= 0
        return label
    }

    /// Parse column label back to index: A=0, B=1, …, Z=25, AA=26…
    static func columnIndex(for label: String) -> Int {
        var result = 0
        for ch in label.uppercased() {
            result = result * 26 + Int(ch.asciiValue! - 65) + 1
        }
        return result - 1
    }

    /// Given a grid cell reference like "G4", returns the center point in pixel coordinates.
    static func centerPoint(column: String, row: Int, cellSize: Int = 50) -> CGPoint {
        let colIdx = columnIndex(for: column)
        let cs = CGFloat(cellSize)
        let x = CGFloat(colIdx) * cs + cs / 2
        let y = CGFloat(row - 1) * cs + cs / 2  // row is 1-indexed
        return CGPoint(x: x, y: y)
    }
}
