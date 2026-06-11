import Foundation
import UIKit

/// Drives the verification flow according to the server-supplied
/// `FlowDefinitionDTO`. Owned by `RKNCheckFlowContainerView`; never visible to
/// integrators.
@MainActor
final class RKNCheckFlowCoordinator {
    private let api: RKNCheckAPIClient
    private let state: RKNCheckFlowState
    private let nfcReader = PassportNFCReader()
    private let onFinish: (RKNCheckResult) -> Void

    private var stepIndex = 0
    private var skippedSteps: Set<RKNCheckFlowState.FlowKind> = []

    private static let maxDocumentJPEGBytes = 10 * 1024 * 1024
    private static let maxSelfieJPEGBytes = 8 * 1024 * 1024

    init(api: RKNCheckAPIClient, state: RKNCheckFlowState, onFinish: @escaping (RKNCheckResult) -> Void) {
        self.api = api
        self.state = state
        self.onFinish = onFinish
    }

    func start() async {
        state.bind(sessionId: api.sessionId)
        state.stage = .loading
        do {
            try api.validateToken()
            let flow = try await api.fetchFlow()
            state.flow = flow
            let status = try await api.fetchSession()
            state.latestStatus = status
            advanceToNextStep()
        } catch let error as RKNCheckError {
            state.stage = .error(error)
        } catch {
            state.stage = .error(.internalError(error.localizedDescription))
        }
    }

    /// Mid-flow user-initiated cancel.
    func cancel() async {
        let sessionId = state.sessionId
        do {
            _ = try await api.completeSession(clientStatus: "canceled")
            onFinish(.canceled(sessionId: sessionId))
        } catch {
            onFinish(.canceled(sessionId: sessionId))
        }
    }

    /// Allows the user to skip a `skippable` step. Server still treats the
    /// session as in-progress until a terminal status is reached.
    func skipCurrentStep() {
        guard let kind = currentKind else { return }
        skippedSteps.insert(kind)
        stepIndex += 1
        advanceToNextStep()
    }

    func handleDocumentImage(_ image: UIImage) {
        Task { await uploadDocument(image) }
    }

    func handleMRZ(_ mrzText: String) {
        Task { await submitMRZ(mrzText) }
    }

    func handleSelfie(_ image: UIImage, liveness: LivenessSubmission) {
        Task { await uploadSelfie(image, liveness: liveness) }
    }

    func startNFCStep() {
        Task { await runNFCStep() }
    }

    func setNFCAccessKey(_ accessKey: NFCAccessKey) {
        state.nfcAccessKey = accessKey
    }

    // MARK: - Step routing

    private var currentKind: RKNCheckFlowState.FlowKind? {
        guard let steps = state.flow?.steps, stepIndex < steps.count else { return nil }
        return RKNCheckFlowState.FlowKind(rawValue: steps[stepIndex].kind)
    }

    private var currentStep: FlowStepDTO? {
        guard let steps = state.flow?.steps, stepIndex < steps.count else { return nil }
        return steps[stepIndex]
    }

    private func advanceToNextStep() {
        guard let steps = state.flow?.steps else {
            state.stage = .error(.internalError("Server did not return a flow definition."))
            return
        }

        while stepIndex < steps.count {
            let step = steps[stepIndex]
            guard let kind = RKNCheckFlowState.FlowKind(rawValue: step.kind) else {
                stepIndex += 1
                continue
            }
            if skippedSteps.contains(kind) || shouldSkipForState(kind, step: step) {
                stepIndex += 1
                continue
            }
            state.stage = .prompt(kind)
            return
        }

        finalizeFlow()
    }

    private func shouldSkipForState(_ kind: RKNCheckFlowState.FlowKind, step: FlowStepDTO) -> Bool {
        switch kind {
        case .nfc:
            // The server tells us per-passport whether NFC is required; skip
            // the step if a previous response said `nfcRequired: false`.
            if state.latestStatus?.nfcRequired == false { return true }
            return false
        case .document:
            return state.latestStatus?.documentFaceDetected == true
        case .mrz:
            return state.latestStatus?.mrzValid == true
        case .selfie:
            return state.latestStatus?.selfieFaceDetected == true
        }
    }

    private func finalizeFlow() {
        Task { await pollUntilTerminal() }
    }

    // MARK: - Network handlers

    private func uploadDocument(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.9), data.count <= Self.maxDocumentJPEGBytes else {
            state.stage = .error(.internalError("Document image is too large or could not be encoded."))
            return
        }
        state.documentImage = image
        state.stage = .processing("Analyzing passport page…")
        do {
            let status = try await api.uploadDocument(imageData: data)
            state.latestStatus = status
            stepIndex += 1
            advanceToNextStep()
        } catch let error as RKNCheckError {
            state.stage = .error(error)
        } catch {
            state.stage = .error(.internalError(error.localizedDescription))
        }
    }

    private func submitMRZ(_ mrzText: String) async {
        state.stage = .processing("Validating MRZ…")
        do {
            let status = try await api.submitMRZ(mrzText: mrzText)
            state.latestStatus = status
            if let docNumber = status.documentNumber,
               let dob = status.dateOfBirth,
               let exp = status.expiryDate {
                state.nfcAccessKey = NFCAccessKey(
                    documentNumber: docNumber,
                    dateOfBirth: dob,
                    expiryDate: exp
                )
            }
            stepIndex += 1
            advanceToNextStep()
        } catch let error as RKNCheckError {
            state.stage = .error(error)
        } catch {
            state.stage = .error(.internalError(error.localizedDescription))
        }
    }

    private func runNFCStep() async {
        guard let accessKey = state.nfcAccessKey else {
            state.stage = .error(.internalError("Missing MRZ access key for NFC reading."))
            return
        }
        state.stage = .processing("Reading passport chip — hold the phone on the passport.")
        do {
            let capture = try await nfcReader.readPassport(accessKey: accessKey)
            let status = try await api.submitNFC(submission: capture.submission)
            state.latestStatus = status
            stepIndex += 1
            advanceToNextStep()
        } catch let error as RKNCheckError {
            state.stage = .error(error)
        } catch let nfcError as PassportNFCReadError {
            state.stage = .error(.internalError(nfcError.errorDescription ?? "NFC read failed"))
        } catch {
            state.stage = .error(.internalError(error.localizedDescription))
        }
    }

    private func uploadSelfie(_ image: UIImage, liveness: LivenessSubmission) async {
        guard let data = image.jpegData(compressionQuality: 0.88), data.count <= Self.maxSelfieJPEGBytes else {
            state.stage = .error(.internalError("Selfie image is too large or could not be encoded."))
            return
        }
        state.selfieImage = image
        state.stage = .processing("Comparing your selfie against the passport portrait…")
        do {
            let status = try await api.uploadSelfie(imageData: data, liveness: liveness)
            state.latestStatus = status
            stepIndex += 1
            advanceToNextStep()
        } catch let error as RKNCheckError {
            state.stage = .error(error)
        } catch {
            state.stage = .error(.internalError(error.localizedDescription))
        }
    }

    private func pollUntilTerminal() async {
        var status = state.latestStatus
        for _ in 0..<8 {
            if let status, isTerminal(status.status) {
                onFinish(mapResult(status))
                return
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            do {
                status = try await api.fetchSession()
                state.latestStatus = status
            } catch {
                break
            }
        }
        if let status {
            onFinish(mapResult(status))
        } else {
            onFinish(.failed(error: .internalError("Could not fetch final session status.")))
        }
    }

    private func mapResult(_ status: SessionStatusDTO) -> RKNCheckResult {
        let id = status.sessionId ?? state.sessionId
        switch (status.status ?? "").lowercased() {
        case "verified", "approved":
            return .approved(sessionId: id)
        case "rejected":
            return .rejected(sessionId: id, reason: status.reason)
        case "needs_manual_review", "pending_review":
            return .needsReview(sessionId: id, reason: status.reason)
        case "canceled", "cancelled":
            return .canceled(sessionId: id)
        default:
            return .needsReview(sessionId: id, reason: status.reason ?? "no_terminal_status")
        }
    }

    private func isTerminal(_ status: String?) -> Bool {
        guard let status = status?.lowercased() else { return false }
        return ![
            "created",
            "not_started",
            "pending",
            "processing",
            "running",
            "in_progress",
            "document_uploaded",
            "mrz_validated",
            "nfc_validated"
        ].contains(status)
    }
}
