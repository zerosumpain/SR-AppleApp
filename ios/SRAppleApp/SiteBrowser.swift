import SwiftUI
import SafariServices

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

    final class Presenter: UIViewController, SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
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
            safari.presentationController?.delegate = self
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            browser = nil; wantsPresentation = false; onClose?()
        }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            // Dismiss the presented browser explicitly before releasing it or
            // updating SwiftUI; UIKit may have forwarded presentation to an ancestor.
            wantsPresentation = false
            controller.dismiss(animated: true) { [weak self] in
                self?.browser = nil
                self?.onClose?()
            }
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
