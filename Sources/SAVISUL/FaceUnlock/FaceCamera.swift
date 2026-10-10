@preconcurrency import AVFoundation
import Foundation

/// The camera for Face Unlock: small frames from the built-in camera, each read for a face off the main thread.
/// Separate from the island's camera mirror, which can run at the same time.
final class FaceCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.savisul.face", qos: .userInitiated)
    private var configured = false
    /// Called on the camera's queue with each frame's face, nil when there was none.
    private var handler: ((FaceFrame?) -> Void)?
    /// Every frame is read for the eyes, every `printEvery`-th also for who it is.
    private var printEvery = 3
    private var frameIndex = 0

    /// Whether the camera may be used, without asking.
    static var allowed: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }

    /// The built-in camera when there is one, then any other.
    private static func device() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                         mediaType: .video, position: .unspecified)
        return discovery.devices.first { $0.deviceType == .builtInWideAngleCamera } ?? discovery.devices.first
    }

    func start(printEvery: Int = 3, _ handler: @escaping (FaceFrame?) -> Void) {
        queue.async { [self] in
            self.handler = handler
            self.printEvery = max(printEvery, 1)
            frameIndex = 0
            if !configured { configured = configure() }
            guard configured, !session.isRunning else { return }
            session.startRunning()
        }
    }

    /// Sets the camera up without starting it, so a later start is quicker.
    func prepare() {
        queue.async { [self] in
            if !configured { configured = configure() }
        }
    }

    func stop() {
        queue.async { [self] in
            handler = nil
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() -> Bool {
        guard let device = Self.device(), let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // 720p rather than VGA: a face across the room is a few dozen pixels in VGA, too few to recognize.
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720
            : session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .medium
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let handler, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameIndex += 1
        handler(FaceEngine.read(buffer, print: frameIndex % printEvery == 1 || printEvery == 1))
    }
}
