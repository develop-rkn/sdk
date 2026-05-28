import SwiftUI
import UIKit

/// UIHostingController that lets UIKit integrators present the SwiftUI flow
/// without having to interact with SwiftUI directly.
final class FacedFlowHostingController: UIHostingController<FacedFlowContainerView> {
    init(clientToken: String, onFinish: @escaping (FacedResult) -> Void) {
        super.init(rootView: FacedFlowContainerView(clientToken: clientToken, onFinish: onFinish))
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
