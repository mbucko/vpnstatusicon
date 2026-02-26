import AppKit

extension NSImage {
    /// Modern tinting for NSImage using NSImage(size:flipped:drawingHandler:)
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
            let context = NSGraphicsContext.current!.cgContext
            
            // Draw original image
            context.draw(cgImage, in: rect)
            
            // Tint with sourceAtop
            context.setBlendMode(.sourceAtop)
            context.setFillColor(color.cgColor)
            context.fill(rect)
            
            return true
        }
        image.isTemplate = false
        return image
    }
}
