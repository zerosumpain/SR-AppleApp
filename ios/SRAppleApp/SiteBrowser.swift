import SwiftUI
import SafariServices

struct SiteBrowserCover: View {
    let url: URL
    @Binding var isPresented: Bool
    let onFailure: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    isPresented = false
                } label: {
                    Label("Back to SR Companion", systemImage: "chevron.left")
                }
                .accessibilityIdentifier("site-browser-close")
                Spacer()
            }
            .font(.headline)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .foregroundStyle(Color(red: 0.102, green: 0.063, blue: 0.031))
            .background(Color(red: 0.929, green: 0.894, blue: 0.831))

            SafariController(
                url: url,
                onClose: { isPresented = false },
                onFailure: {
                    isPresented = false
                    onFailure()
                }
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.light)
    }
}

private struct SafariController: UIViewControllerRepresentable {
    let url: URL
    let onClose: () -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let safari = SFSafariViewController(url: url, configuration: configuration)
        safari.delegate = context.coordinator
        safari.dismissButtonStyle = .close
        safari.preferredBarTintColor = UIColor(red: 0.929, green: 0.894, blue: 0.831, alpha: 1)
        safari.preferredControlTintColor = UIColor(red: 0.769, green: 0.341, blue: 0.039, alpha: 1)
        return safari
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onClose: () -> Void
        private let onFailure: () -> Void

        init(onClose: @escaping () -> Void, onFailure: @escaping () -> Void) {
            self.onClose = onClose
            self.onFailure = onFailure
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onClose()
        }

        func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
            guard !didLoadSuccessfully else { return }
            onFailure()
        }
    }
}
