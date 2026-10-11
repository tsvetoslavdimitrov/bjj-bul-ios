import Foundation
import AVFoundation
import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

enum VideoToolsError: Error, LocalizedError {
    case exportFailed(String)
    case tooLarge
    case tooLong

    var errorDescription: String? {
        switch self {
        case .exportFailed: return String(localized: "composer.video.exportFailed")
        case .tooLarge: return String(localized: "composer.video.tooLarge")
        case .tooLong: return String(localized: "composer.video.tooLong")
        }
    }
}

enum VideoTools {
    static let maxBytes = 50 * 1024 * 1024
    static let maxSeconds: Double = 60

    /// Re-encodes to MP4 at medium quality (AVAssetExportPresetMediumQuality) and returns the file data.
    static func compress(_ inputURL: URL) async throws -> Data {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        if CMTimeGetSeconds(duration) > maxSeconds + 1 { throw VideoToolsError.tooLong }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw VideoToolsError.exportFailed("no session")
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }
        guard session.status == .completed else {
            throw VideoToolsError.exportFailed(session.error?.localizedDescription ?? "export failed")
        }
        let data = try Data(contentsOf: outputURL)
        try? FileManager.default.removeItem(at: outputURL)
        if data.count > maxBytes { throw VideoToolsError.tooLarge }
        return data
    }

    /// JPEG thumbnail of the first second, for previews.
    static func thumbnail(_ url: URL) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }
}

/// A movie picked from the library via PhotosPicker (copied into a temp file we own).
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// In-app camera: photo or video (max 60 s, medium quality). Requires camera + microphone usage strings.
struct CameraPicker: UIViewControllerRepresentable {
    enum Result {
        case image(UIImage)
        case movie(URL)
    }

    let onFinish: (Result?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoMaximumDuration = VideoTools.maxSeconds
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Result?) -> Void

        init(onFinish: @escaping (Result?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                onFinish(.movie(url))
            } else if let image = info[.originalImage] as? UIImage {
                onFinish(.image(image))
            } else {
                onFinish(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
