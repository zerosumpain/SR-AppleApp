import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A file on its way into the next turn.
///
/// Uploaded the moment it is picked, not when Send is pressed — the web
/// composer does the same. A photo on a train takes seconds to go up, and doing
/// it at send time turns every send with a picture into a wait with a spinner.
struct PendingAttachment: Identifiable, Hashable {
    enum State: Hashable {
        case uploading
        case ready(ChatAttachment)
        case failed(String)
    }

    let id = UUID()
    let filename: String
    let mimeType: String
    /// Kept for a picked photo so its chip, and the bubble it ends up in, can
    /// draw it without fetching back the bytes that were just sent.
    let preview: UIImage?
    var state: State = .uploading

    var isImage: Bool { mimeType.hasPrefix("image/") }

    var uploaded: ChatAttachment? {
        if case .ready(let attachment) = state { return attachment }
        return nil
    }
}

/// Turning what the pickers hand back into something the server takes.
enum ChatUpload {
    /// The longest edge a photo is sent at.
    ///
    /// A 48-megapixel HEIC is ~5 MB and 8064 px across. The models that read it
    /// downsample to well under 2000 px anyway, so the extra pixels are upload
    /// time on a phone connection and nothing else.
    static let maxEdge: CGFloat = 2048

    /// A photo, re-encoded as JPEG.
    ///
    /// NOT the HEIC the library hands over. The site's allow-list accepts HEIC,
    /// but the vision models behind jkai read JPEG, PNG, GIF and WebP — a HEIC
    /// would be stored perfectly and then understood by nobody.
    static func photo(_ image: UIImage) -> (data: Data, preview: UIImage)? {
        let scale = min(1, maxEdge / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.82) else { return nil }
        return (data, resized)
    }

    /// What the Files picker offers. The site's allow-list, as UTTypes — a file
    /// the server would refuse with a 415 is better never offered.
    static let documentTypes: [UTType] = [
        .pdf, .image, .plainText, .commaSeparatedText, .json, .xml, .yaml, .rtf,
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "docx"),
        UTType(filenameExtension: "xlsx"),
    ].compactMap { $0 }

    static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

/// Photos already on the phone, by attachment id.
///
/// A photo you just sent is put here under its server id, so the bubble draws it
/// at once instead of downloading back what it uploaded a second ago. Anything
/// else is fetched once and kept for the session.
@MainActor
final class AttachmentImages {
    static let shared = AttachmentImages()
    private let cache = NSCache<NSString, UIImage>()

    func put(_ image: UIImage, for id: String) { cache.setObject(image, forKey: id as NSString) }

    func image(for id: String) -> UIImage? { cache.object(forKey: id as NSString) }

    func load(_ id: String) async -> UIImage? {
        if let hit = image(for: id) { return hit }
        guard let data = try? await SiteClient.shared.bytes("api/native/chat/attachments/\(id)"),
              let image = UIImage(data: data) else { return nil }
        put(image, for: id)
        return image
    }
}

/// A photo in a sent turn.
struct AttachmentImage: View {
    let attachment: ChatAttachment
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(SR.line.opacity(0.4))
                    .overlay {
                        if failed {
                            Image(systemName: "photo")
                                .foregroundStyle(SR.inkMuted)
                        } else {
                            ProgressView().tint(SR.inkMuted)
                        }
                    }
            }
        }
        .frame(width: 200, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
        .accessibilityLabel(attachment.filename ?? "Photo")
        .task(id: attachment.id) {
            image = await AttachmentImages.shared.load(attachment.id)
            failed = image == nil
        }
    }
}

/// The picked files, in a row above the composer.
struct PendingAttachmentStrip: View {
    let items: [PendingAttachment]
    let remove: (PendingAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    chip(item)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func chip(_ item: PendingAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let preview = item.preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "doc")
                            .foregroundStyle(SR.accent)
                        Text(item.filename)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                            .frame(maxWidth: 140, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 60)
                    .srGlass(.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .overlay {
                switch item.state {
                case .uploading:
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(SR.paper.opacity(0.55))
                        .overlay { ProgressView().tint(SR.ink) }
                case .failed:
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(SR.paper.opacity(0.7))
                        .overlay {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(SR.error)
                        }
                case .ready:
                    EmptyView()
                }
            }

            Button {
                SRHaptic.tap()
                remove(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SR.paper)
                    .frame(width: 22, height: 22)
                    .background(SR.ink, in: Circle())
                    // The visible disc is 22 pt; the thumb gets the full target.
                    .frame(width: 44, height: 44, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: -8)
            .accessibilityLabel("Remove \(item.filename)")
        }
        .padding(.top, 8)
        .padding(.trailing, 8)
        .accessibilityElement(children: .contain)
    }
}

/// The camera, as a sheet.
///
/// `UIImagePickerController` rather than a capture session: one photo, the
/// system's own shutter and retake screen, and nothing to maintain.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
