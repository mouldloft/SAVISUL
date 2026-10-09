import AppKit
@preconcurrency import AVFoundation
import Observation
import SwiftUI

/// A mirror from the FaceTime camera, shown under the notch before a call.
@MainActor
@Observable
final class CameraMirror {
    private(set) var running = false
    private(set) var access: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var cameras: [AVCaptureDevice] = []
    var selected: String? { didSet { if running { restart() } } }

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.savisul.camera")
    @ObservationIgnored private var input: AVCaptureDeviceInput?

    func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                         mediaType: .video, position: .unspecified)
        cameras = discovery.devices
        if selected == nil || !cameras.contains(where: { $0.uniqueID == selected }) {
            selected = cameras.first { $0.deviceType == .builtInWideAngleCamera }?.uniqueID ?? cameras.first?.uniqueID
        }
    }

    func start() {
        access = AVCaptureDevice.authorizationStatus(for: .video)
        switch access {
        case .authorized:
            refreshDevices()
            begin()
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.access = AVCaptureDevice.authorizationStatus(for: .video)
                        if granted { self?.start() }
                    }
                }
            }
        default:
            break
        }
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }

    func stop() {
        guard running else { return }
        running = false
        let session = session
        queue.async { session.stopRunning() }
    }

    private func restart() {
        stop()
        begin()
    }

    private func begin() {
        guard let id = selected, let device = AVCaptureDevice(uniqueID: id) else { return }
        running = true
        let session = session
        let previous = input
        queue.async { [weak self] in
            session.beginConfiguration()
            session.sessionPreset = .high
            if let previous { session.removeInput(previous) }
            var added: AVCaptureDeviceInput?
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
                added = input
            }
            session.commitConfiguration()
            session.startRunning()
            nonisolated(unsafe) let fresh = added
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.input = fresh } }
        }
    }
}

/// The live preview layer, mirrored like a mirror.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        if view.preview.session !== session { view.preview.session = session }
    }

    final class PreviewView: NSView {
        let preview = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
            preview.backgroundColor = NSColor.black.cgColor
            layer?.addSublayer(preview)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            preview.frame = bounds
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            CATransaction.commit()
        }
    }
}
