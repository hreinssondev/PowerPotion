import AppKit
import AVFoundation
import CoreImage
import CoreMedia

final class CapturePreviewView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let ciContext = CIContext()
    var usesBetaRenderer = false {
        didSet {
            displayLayer.isHidden = usesBetaRenderer
            if usesBetaRenderer {
                displayLayer.flushAndRemoveImage()
            } else {
                layer?.contents = nil
            }
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override var mouseDownCanMoveWindow: Bool {
        return true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if usesBetaRenderer {
            enqueueViaCoreImage(sampleBuffer)
            return
        }

        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    func display(_ image: CGImage) {
        displayLayer.isHidden = true
        layer?.contentsGravity = .resizeAspect
        layer?.contents = image
    }

    func flush() {
        displayLayer.flushAndRemoveImage()
        layer?.contents = nil
    }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }

    private func setupLayer() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        displayLayer.frame = bounds
        layer?.addSublayer(displayLayer)
    }

    private func enqueueViaCoreImage(_ sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        layer?.contentsGravity = .resizeAspect
        layer?.contents = cgImage
    }
}
