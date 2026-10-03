import AppKit
import AVFoundation
import SwiftUI

final class CameraModel: ObservableObject {
    static let shared = CameraModel()

    let session = AVCaptureSession()
    @Published private(set) var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @Published private(set) var denied = false
    @Published private(set) var noCamera = false

    private let queue = DispatchQueue(label: "overhang.camera")
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
            queue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.authorized = granted
                    self.denied = !granted
                    if granted { self.queue.async { self.configureAndRun() } }
                }
            }
        default:
            denied = true
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configureAndRun() {
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .high
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.noCamera = true }
                return
            }
            session.addInput(input)
            session.commitConfiguration()
            configured = true
        }
        if !session.isRunning { session.startRunning() }
    }
}

/// Hosts an AVCaptureVideoPreviewLayer, mirrored like a real mirror.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.layer = CALayer()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        layer.frame = view.bounds
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        nsView.layer?.sublayers?.forEach { $0.frame = nsView.bounds }
    }
}

struct MirrorView: View {
    @ObservedObject private var camera = CameraModel.shared

    var body: some View {
        Group {
            if camera.denied {
                VStack(spacing: 8) {
                    EmptyState(symbol: "video.slash", title: "Camera access is off",
                               message: "Allow Overhang under System Settings → Privacy & Security → Camera.")
                    PillButton(title: "Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } else if camera.noCamera {
                EmptyState(symbol: "camera", title: "No camera found")
            } else {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Text("Only visible to you · nothing is recorded")
                            .font(.system(size: 10)).padding(6)
                            .background(Capsule().fill(.black.opacity(0.5))).padding(8)
                    }
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}
