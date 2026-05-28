import Foundation
import UIKit

/// Single source of truth for the flow's progress, shared between the
/// orchestrator view and the capture sheets it presents.
@MainActor
final class FacedFlowState: ObservableObject {
    enum Stage: Equatable {
        case loading
        case prompt(FlowKind)
        case capturing(FlowKind)
        case processing(String)
        case finished(FacedResult)
        case error(FacedError)
    }

    enum FlowKind: String {
        case document
        case mrz
        case nfc
        case selfie
    }

    @Published var stage: Stage = .loading
    @Published var flow: FlowDefinitionDTO?
    @Published var latestStatus: SessionStatusDTO?
    @Published var documentImage: UIImage?
    @Published var selfieImage: UIImage?
    @Published var nfcAccessKey: NFCAccessKey?

    private(set) var sessionId: String = ""

    func bind(sessionId: String) {
        self.sessionId = sessionId
    }
}
