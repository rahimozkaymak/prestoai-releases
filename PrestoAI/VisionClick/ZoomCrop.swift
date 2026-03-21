import AppKit

class ZoomCrop {

    /// Crops a region around a coarse grid cell, scales it up, and applies a fine grid.
    static func zoomAroundPoint(
        image: NSImage,
        coarseCenter: CGPoint,
        cropSize: CGFloat = 200,
        scaleFactor: CGFloat = 4,
        fineCellSize: CGFloat = 10
    ) -> (zoomedImage: NSImage, cropOrigin: CGPoint)? {
        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0 else { return nil }

        // Calculate crop rect centered on coarseCenter, clamped to image bounds
        let halfCrop = cropSize / 2
        var cropX = coarseCenter.x - halfCrop
        var cropY = coarseCenter.y - halfCrop

        // Clamp to image bounds
        cropX = max(0, min(cropX, imgW - cropSize))
        cropY = max(0, min(cropY, imgH - cropSize))

        let actualCropW = min(cropSize, imgW)
        let actualCropH = min(cropSize, imgH)

        let cropOrigin = CGPoint(x: cropX, y: cropY)

        // NSImage uses bottom-left origin, so flip Y for the crop rect
        let flippedY = imgH - cropY - actualCropH
        let cropRect = NSRect(x: cropX, y: flippedY, width: actualCropW, height: actualCropH)

        // Crop from the original image
        let croppedImage = NSImage(size: NSSize(width: actualCropW, height: actualCropH))
        croppedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: NSSize(width: actualCropW, height: actualCropH)),
                   from: cropRect,
                   operation: .copy,
                   fraction: 1.0)
        croppedImage.unlockFocus()

        // Scale up
        let zoomedW = actualCropW * scaleFactor
        let zoomedH = actualCropH * scaleFactor
        let zoomedImage = NSImage(size: NSSize(width: zoomedW, height: zoomedH))
        zoomedImage.lockFocus()
        croppedImage.draw(in: NSRect(origin: .zero, size: NSSize(width: zoomedW, height: zoomedH)))

        // Apply fine grid
        let fineCS = fineCellSize * scaleFactor  // cell size in zoomed pixels
        let fineCols = Int(ceil(zoomedW / fineCS))
        let fineRows = Int(ceil(zoomedH / fineCS))

        // Grid lines — slightly more visible than coarse grid
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let linePath = NSBezierPath()
        linePath.lineWidth = 0.5

        for c in 1..<fineCols {
            let x = CGFloat(c) * fineCS
            linePath.move(to: NSPoint(x: x, y: 0))
            linePath.line(to: NSPoint(x: x, y: zoomedH))
        }
        for r in 1..<fineRows {
            let y = zoomedH - CGFloat(r) * fineCS
            linePath.move(to: NSPoint(x: 0, y: y))
            linePath.line(to: NSPoint(x: zoomedW, y: y))
        }
        linePath.stroke()

        // Labels: numbers on both axes
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.shadowBlurRadius = 0

        let labelFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            .shadow: shadow
        ]

        // Column labels along top
        for c in 0..<fineCols {
            let label = "\(c + 1)"
            let x = CGFloat(c) * fineCS + fineCS / 2
            let labelSize = (label as NSString).size(withAttributes: attrs)
            let pt = NSPoint(x: x - labelSize.width / 2, y: zoomedH - labelSize.height - 2)
            (label as NSString).draw(at: pt, withAttributes: attrs)
        }

        // Row labels along left
        for r in 0..<fineRows {
            let label = "\(r + 1)"
            let y = zoomedH - CGFloat(r) * fineCS - fineCS / 2
            let labelSize = (label as NSString).size(withAttributes: attrs)
            let pt = NSPoint(x: 2, y: y - labelSize.height / 2)
            (label as NSString).draw(at: pt, withAttributes: attrs)
        }

        zoomedImage.unlockFocus()
        return (zoomedImage, cropOrigin)
    }

    /// Maps fine grid coordinates back to original screenshot coordinates.
    static func mapToScreenCoordinates(
        fineColumn: Int,
        fineRow: Int,
        cropOrigin: CGPoint,
        fineCellSize: CGFloat = 10
    ) -> CGPoint {
        let x = cropOrigin.x + CGFloat(fineColumn - 1) * fineCellSize + fineCellSize / 2
        let y = cropOrigin.y + CGFloat(fineRow - 1) * fineCellSize + fineCellSize / 2
        return CGPoint(x: x, y: y)
    }
}
