import SwiftUI
import SafariServices
import ObjectiveC

private var siteBrowserDelegateKey: UInt8 = 0

private final class SiteBrowserDelegate: NSObject, SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private let onClose: () -> Void
    private let onFailure: () -> Void

    init(onClose: @escaping () -> Void, onFailure: @escaping () -> Void) {
        self.onClose = onClose
        self.onFailure = onFailure
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        close(controller)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onClose()
    }

    func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
        guard !didLoadSuccessfully else { return }
        close(controller, failed: true)
    }

    private func close(_ controller: SFSafariViewController, failed: Bool = false) {
        let presentingController = controller.presentingViewController
        presentingController?.dismiss(animated: true) { [onClose, onFailure] in
            onClose()
            if failed { onFailure() }
            objc_setAssociatedObject(controller, &siteBrowserDelegateKey, nil, .OBJC_ASSOCIATION_ASSIGN)
        }
    }
}

// Present Safari modally, as required by SafariServices. Never embed it in the
// tab hierarchy or share companion credentials with the separate web login.
struct SiteBrowserPresenter: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPresented: Bool
    let onFailure: () -> Void

    func makeUIViewController(context: Context) -> Presenter { Presenter() }
    func updateUIViewController(_ controller: Presenter, context: Context) {
        controller.update(url: url, presented: isPresented, onClose: { isPresented = false }, onFailure: onFailure)
    }

    final class Presenter: UIViewController {
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
            let closeHandler = onClose ?? {}
            let failureHandler = onFailure ?? {}
            let delegate = SiteBrowserDelegate(
                onClose: { [weak self] in
                    self?.browser = nil
                    self?.wantsPresentation = false
                    closeHandler()
                },
                onFailure: failureHandler
            )
            safari.delegate = delegate
            objc_setAssociatedObject(safari, &siteBrowserDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            browser = safari
            // This representable is a zero-sized anchor inside a SwiftUI
            // background. Present from its full-sized ancestor so Safari's
            // remote view receives the window's geometry and touch coordinates.
            var host: UIViewController = self
            while let parent = host.parent { host = parent }
            host.present(safari, animated: true)
            safari.presentationController?.delegate = delegate
        }
    }
}
