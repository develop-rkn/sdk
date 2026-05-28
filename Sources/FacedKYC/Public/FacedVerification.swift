import SwiftUI
import UIKit

/// The single entry point an integrator uses to start an eKYC verification.
///
/// SwiftUI integration:
/// ```swift
/// .facedVerification(isPresented: $showKYC, clientToken: token) { result in
///     ...
/// }
/// ```
///
/// UIKit integration:
/// ```swift
/// FacedVerification(clientToken: token) { result in ... }
///     .present(from: self)
/// ```
public struct FacedVerification {
    public let clientToken: String
    public let onResult: (FacedResult) -> Void

    public init(clientToken: String, onResult: @escaping (FacedResult) -> Void) {
        self.clientToken = clientToken
        self.onResult = onResult
    }

    /// Present the verification flow modally from a UIKit view controller.
    ///
    /// Returns immediately. The completion handler passed to `init` is
    /// invoked when the flow finishes (or the user cancels it).
    public func present(from presenter: UIViewController, animated: Bool = true) {
        guard FacedSDK.isConfigured else {
            onResult(.failed(error: .notConfigured))
            return
        }

        let host = FacedFlowHostingController(clientToken: clientToken) { result in
            presenter.dismiss(animated: animated) {
                onResult(result)
            }
        }
        host.modalPresentationStyle = .fullScreen
        presenter.present(host, animated: animated)
    }
}

public extension View {
    /// Presents the Faced verification flow when `isPresented` becomes `true`.
    func facedVerification(
        isPresented: Binding<Bool>,
        clientToken: String,
        onResult: @escaping (FacedResult) -> Void
    ) -> some View {
        modifier(
            FacedVerificationPresenter(
                isPresented: isPresented,
                clientToken: clientToken,
                onResult: onResult
            )
        )
    }
}

private struct FacedVerificationPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let clientToken: String
    let onResult: (FacedResult) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                FacedFlowContainerView(clientToken: clientToken) { result in
                    isPresented = false
                    onResult(result)
                }
                .ignoresSafeArea()
            }
    }
}
