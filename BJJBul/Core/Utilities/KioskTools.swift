import Foundation
import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
import CryptoKit

enum QRCodeImage {
    /// Crisp QR image for a string (CoreImage, error correction M).
    static func make(_ text: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else {
            return nil
        }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = QRCodeImage.make(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary)
        }
    }
}

/// Exit PIN stored only on this device: salted SHA-256 in UserDefaults.
enum LocalKioskPin {
    private static func key(_ gymId: UUID) -> String { "kiosk.pin.\(gymId.uuidString)" }
    private static func saltKey(_ gymId: UUID) -> String { "kiosk.salt.\(gymId.uuidString)" }

    private static func hash(_ pin: String, salt: String) -> String {
        let digest = SHA256.hash(data: Data((salt + pin).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func save(_ pin: String, gymId: UUID) {
        let salt = UUID().uuidString
        UserDefaults.standard.set(salt, forKey: saltKey(gymId))
        UserDefaults.standard.set(hash(pin, salt: salt), forKey: key(gymId))
    }

    static func verify(_ pin: String, gymId: UUID) -> Bool {
        guard let salt = UserDefaults.standard.string(forKey: saltKey(gymId)),
              let stored = UserDefaults.standard.string(forKey: key(gymId)) else { return false }
        return hash(pin, salt: salt) == stored
    }

    static func isValid(_ pin: String) -> Bool {
        (4...6).contains(pin.count) && pin.allSatisfy { $0.isNumber }
    }
}

/// Camera QR scanner (front camera first, for iPads on a stand). Calls onCode once per distinct code.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var lastCode: String?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video)
            guard let device, let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            preview = layer
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            let session = self.session
            DispatchQueue.global(qos: .userInitiated).async {
                if !session.isRunning { session.startRunning() }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let session = self.session
            DispatchQueue.global(qos: .userInitiated).async {
                if session.isRunning { session.stopRunning() }
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue, value != lastCode else { return }
            lastCode = value
            onCode?(value)
        }
    }
}
