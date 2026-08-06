import CoreGraphics
import Darwin
import Foundation

final class WindowSnapshotSession {
    private typealias CGWindowListCreateImageFunction = @convention(c) (
        CGRect,
        CGWindowListOption,
        CGWindowID,
        CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    private var timer: DispatchSourceTimer?
    private let imageHandler: (CGImage) -> Void
    private let createWindowImage: CGWindowListCreateImageFunction?

    init(imageHandler: @escaping (CGImage) -> Void) {
        self.imageHandler = imageHandler
        self.createWindowImage = Self.loadCreateWindowImage()
    }

    func start(windowID: CGWindowID) {
        stop()
        guard let createWindowImage else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "appspip.window.snapshots"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(125), leeway: .milliseconds(25))
        timer.setEventHandler { [weak self] in
            guard let self else { return }

            guard let unmanagedImage = createWindowImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.bestResolution, .boundsIgnoreFraming]
            )
            else {
                return
            }

            let image = unmanagedImage.takeRetainedValue()
            DispatchQueue.main.async { [imageHandler] in
                imageHandler(image)
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private static func loadCreateWindowImage() -> CGWindowListCreateImageFunction? {
        let handles = [
            dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
            dlopen(nil, RTLD_NOW)
        ].compactMap { $0 }

        for handle in handles {
            if let symbol = dlsym(handle, "CGWindowListCreateImage") {
                return unsafeBitCast(symbol, to: CGWindowListCreateImageFunction.self)
            }
        }

        return nil
    }
}
