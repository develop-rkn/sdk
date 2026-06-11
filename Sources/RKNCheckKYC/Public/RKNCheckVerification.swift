import SwiftUI
import UIKit

/// The single entry point an integrator uses to start an eKYC verification.
///
/// SwiftUI integration:
/// ```swift
/// .rknCheckVerification(isPresented: $showKYC, clientToken: token) { result in
///     ...
/// }
/// ```
///
/// UIKit integration:
/// ```swift
/// RKNCheckVerification(clientToken: token) { result in ... }
///     .present(from: self)
/// ```
public struct RKNCheckVerification {
    public let clientToken: String
    public let onResult: (RKNCheckResult) -> Void

    public init(clientToken: String, onResult: @escaping (RKNCheckResult) -> Void) {
        self.clientToken = clientToken
        self.onResult = onResult
    }

    /// Present the verification flow modally from a UIKit view controller.
    ///
    /// Returns immediately. The completion handler passed to `init` is
    /// invoked when the flow finishes (or the user cancels it).
    public func present(from presenter: UIViewController, animated: Bool = true) {
        guard RKNCheckSDK.isConfigured else {
            onResult(.failed(error: .notConfigured))
            return
        }

        let host = RKNCheckFlowHostingController(clientToken: clientToken) { result in
            presenter.dismiss(animated: animated) {
                onResult(result)
            }
        }
        host.modalPresentationStyle = .fullScreen
        presenter.present(host, animated: animated)
    }
}

public extension View {
    /// Presents the RKN-Check verification flow when `isPresented` becomes `true`.
    func rknCheckVerification(
        isPresented: Binding<Bool>,
        clientToken: String,
        onResult: @escaping (RKNCheckResult) -> Void
    ) -> some View {
        modifier(
            RKNCheckVerificationPresenter(
                isPresented: isPresented,
                clientToken: clientToken,
                onResult: onResult
            )
        )
    }

    /// Deprecated. Use ``rknCheckVerification(isPresented:clientToken:onResult:)``.
    /// Removed in v0.4.0.
    @available(*, deprecated, renamed: "rknCheckVerification(isPresented:clientToken:onResult:)", message: "FacedKYC was rebranded to RKN-Check. Use `.rknCheckVerification(...)`. This shim is removed in v0.4.0.")
    func facedVerification(
        isPresented: Binding<Bool>,
        clientToken: String,
        onResult: @escaping (RKNCheckResult) -> Void
    ) -> some View {
        rknCheckVerification(isPresented: isPresented, clientToken: clientToken, onResult: onResult)
    }
}

private struct RKNCheckVerificationPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let clientToken: String
    let onResult: (RKNCheckResult) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                RKNCheckFlowContainerView(clientToken: clientToken) { result in
                    isPresented = false
                    onResult(result)
                }
                .ignoresSafeArea()
            }
    }
}
