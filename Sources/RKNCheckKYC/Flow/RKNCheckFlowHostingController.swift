import SwiftUI
import UIKit

/// UIHostingController that lets UIKit integrators present the SwiftUI flow
/// without having to interact with SwiftUI directly.
final class RKNCheckFlowHostingController: UIHostingController<RKNCheckFlowContainerView> {
    init(clientToken: String, onFinish: @escaping (RKNCheckResult) -> Void) {
        super.init(rootView: RKNCheckFlowContainerView(clientToken: clientToken, onFinish: onFinish))
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
