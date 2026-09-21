import SwiftUI
import SafariServices

struct JKAIView: View {
    @State private var browserPresented = false
    @State private var loadError: String?
    private let chatURL = URL(string: "https://strangeramblings.com/jkai")!
    private let paper = Color(red: 0.929, green: 0.894, blue: 0.831)
    private let ink = Color(red: 0.102, green: 0.063, blue: 0.031)
    private let accent = Color(red: 0.769, green: 0.341, blue: 0.039)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("STRANGE RAMBLINGS / JKAI").font(.system(.caption, design: .monospaced)).tracking(1)
                    Text("A place to think.").font(.system(size: 44, weight: .black)).tracking(-2).accessibilityAddTraits(.isHeader)
                    Text("Pick up a conversation, explore an idea, or start something new.").font(.title3)
                    Divider()
                    Label("Your existing JKAI workspace", systemImage: "bubble.left.and.bubble.right").font(.headline)
                    Text("Open your conversations and tools with the same mobile chat you use on the website.")
                    Button {
                        loadError = nil
                        browserPresented = true
                    } label: {
                        Label("Open JKAI chat", systemImage: "bubble.left.and.text.bubble.right")
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("open-jkai-chat")
                    Text("Sign in with your Strange Ramblings Google account. Your existing JKAI access permissions apply.").font(.callout)
                    Text("Tap Close in the chat browser to return to your health and family views.").font(.callout).foregroundStyle(.secondary)
                    if let loadError {
                        Text(loadError).font(.callout).accessibilityIdentifier("jkai-load-error")
                        Link("Try in Safari", destination: chatURL)
                    }
                }.padding(22)
            }
            .background(paper.ignoresSafeArea(.container)).foregroundStyle(ink).tint(accent)
            .navigationTitle("JKAI").navigationBarTitleDisplayMode(.inline)
            .background {
                JKAIBrowserPresenter(url: chatURL, isPresented: $browserPresented) {
                    loadError = "JKAI could not load. Check your connection and try again."
                }.frame(width: 0, height: 0)
            }
        }.preferredColorScheme(.light)
    }
}

// Present Safari modally, as required by SafariServices. Never embed it in the
// tab hierarchy or share companion credentials with the separate web login.
private struct JKAIBrowserPresenter: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPresented: Bool
    let onFailure: () -> Void

    func makeUIViewController(context: Context) -> Presenter { Presenter() }
    func updateUIViewController(_ controller: Presenter, context: Context) {
        controller.update(url: url, presented: isPresented, onClose: { isPresented = false }, onFailure: onFailure)
    }

    final class Presenter: UIViewController, SFSafariViewControllerDelegate {
        private var browser: SFSafariViewController?
        private var requestedURL: URL?
        private var wantsPresentation = false
        private var onClose: (() -> Void)?
        private var onFailure: (() -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentIfReady()
        }
        func update(url: URL, presented: Bool, onClose: @escaping () -> Void, onFailure: @escaping () -> Void) {
            requestedURL = url; wantsPresentation = presented
            self.onClose = onClose; self.onFailure = onFailure
            if presented { presentIfReady() }
        }
        private func presentIfReady() {
            guard wantsPresentation, browser == nil, view.window != nil, let url = requestedURL else { return }
            let configuration = SFSafariViewController.Configuration()
            configuration.entersReaderIfAvailable = false
            let safari = SFSafariViewController(url: url, configuration: configuration)
            safari.delegate = self
            safari.dismissButtonStyle = .close
            safari.preferredBarTintColor = UIColor(red: 0.929, green: 0.894, blue: 0.831, alpha: 1)
            safari.preferredControlTintColor = UIColor(red: 0.769, green: 0.341, blue: 0.039, alpha: 1)
            browser = safari
            present(safari, animated: true)
        }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            browser = nil; wantsPresentation = false; onClose?()
        }
        func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
            guard !didLoadSuccessfully else { return }
            controller.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.browser = nil; self.wantsPresentation = false
                self.onClose?(); self.onFailure?()
            }
        }
    }
}
