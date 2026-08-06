import CoreGraphics
import CoreMedia
import ScreenCaptureKit

final class WindowCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    enum CaptureMode {
        case window
        case displayRegion(frame: CGRect)
    }

    private var stream: SCStream?
    private let sampleHandler: (CMSampleBuffer) -> Void

    init(sampleHandler: @escaping (CMSampleBuffer) -> Void) {
        self.sampleHandler = sampleHandler
        super.init()
    }

    func start(windowID: CGWindowID, mode: CaptureMode = .window) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let targetWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotAvailable
        }

        let filter: SCContentFilter
        let configuration = SCStreamConfiguration()

        switch mode {
        case .window:
            filter = SCContentFilter(desktopIndependentWindow: targetWindow)
            configuration.width = max(Int(targetWindow.frame.width), 1)
            configuration.height = max(Int(targetWindow.frame.height), 1)
        case .displayRegion(let frame):
            guard let display = Self.display(containing: frame, from: content.displays) else {
                throw CaptureError.displayNotAvailable
            }

            let excludedApplications = content.applications.filter {
                $0.processID == ProcessInfo.processInfo.processIdentifier
            }
            filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )

            let sourceRect = Self.sourceRect(for: frame, in: display)
            configuration.sourceRect = sourceRect
            configuration.width = max(Int(sourceRect.width), 1)
            configuration.height = max(Int(sourceRect.height), 1)
        }

        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        configuration.queueDepth = 3
        configuration.showsCursor = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "appspip.capture.samples"))
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        DispatchQueue.main.async { [sampleHandler] in
            sampleHandler(sampleBuffer)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .captureStreamStoppedWithError, object: error)
        }
    }

    private static func display(containing frame: CGRect, from displays: [SCDisplay]) -> SCDisplay? {
        displays.max { lhs, rhs in
            intersectionArea(lhs.frame, frame) < intersectionArea(rhs.frame, frame)
        }
    }

    private static func sourceRect(for frame: CGRect, in display: SCDisplay) -> CGRect {
        let clippedFrame = frame.intersection(display.frame)
        guard !clippedFrame.isNull, !clippedFrame.isEmpty else {
            return CGRect(x: 0, y: 0, width: max(frame.width, 1), height: max(frame.height, 1))
        }

        return CGRect(
            x: clippedFrame.minX - display.frame.minX,
            y: clippedFrame.minY - display.frame.minY,
            width: clippedFrame.width,
            height: clippedFrame.height
        )
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }
}

enum CaptureError: LocalizedError {
    case windowNotAvailable
    case displayNotAvailable

    var errorDescription: String? {
        switch self {
        case .windowNotAvailable:
            return "The frontmost window could not be captured."
        case .displayNotAvailable:
            return "The display containing the frontmost window could not be captured."
        }
    }
}

extension Notification.Name {
    static let captureStreamStoppedWithError = Notification.Name("captureStreamStoppedWithError")
}
