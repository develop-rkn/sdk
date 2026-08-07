import SwiftUI
import UIKit

/// Root SwiftUI view embedded inside the modal presentation. Drives the
/// orchestration through `RKNCheckFlowCoordinator` and routes UI off
/// `RKNCheckFlowState.stage`.
struct RKNCheckFlowContainerView: View {
    let clientToken: String
    let onFinish: (RKNCheckResult) -> Void

    @StateObject private var state = RKNCheckFlowState()
    @State private var coordinator: RKNCheckFlowCoordinator?
    @State private var didStart = false
    @State private var showDocumentCamera = false
    @State private var showMRZScanner = false
    @State private var showLivenessCapture = false
    @State private var nfcDocumentNumber: String = ""
    @State private var nfcDateOfBirth: String = ""
    @State private var nfcExpiryDate: String = ""

    private var theme: RKNCheckTheme {
        RKNCheckSDK.currentConfiguration?.theme ?? .default
    }

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            Task { await coordinator?.cancel() }
                        }
                    }
                    if let kind = currentSkippableKind {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Skip \(kind.label)") {
                                coordinator?.skipCurrentStep()
                            }
                            .foregroundStyle(theme.accentColor)
                        }
                    }
                }
        }
        .background(theme.backgroundColor.ignoresSafeArea())
        .task {
            guard !didStart else { return }
            didStart = true
            guard let api = RKNCheckRuntime.shared.makeAPIClient(clientToken: clientToken) else {
                onFinish(.failed(error: .notConfigured))
                return
            }
            let coordinator = RKNCheckFlowCoordinator(api: api, state: state, onFinish: onFinish)
            self.coordinator = coordinator
            await coordinator.start()
        }
        .sheet(isPresented: $showDocumentCamera) {
            DocumentCameraView(
                onImageCaptured: { image in
                    showDocumentCamera = false
                    coordinator?.handleDocumentImage(image)
                },
                onCancel: { showDocumentCamera = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showMRZScanner) {
            MRZCaptureView(
                onMRZCaptured: { mrz in
                    showMRZScanner = false
                    coordinator?.handleMRZ(mrz)
                },
                onCancel: { showMRZScanner = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showLivenessCapture) {
            ActiveLivenessCaptureView(
                onCompleted: { image, liveness in
                    showLivenessCapture = false
                    coordinator?.handleSelfie(image, liveness: liveness)
                },
                onCancel: { showLivenessCapture = false }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - View routing

    @ViewBuilder
    private var content: some View {
        switch state.stage {
        case .loading:
            stageLoading
        case .prompt(let kind):
            stagePrompt(kind)
        case .capturing:
            stageLoading
        case .processing(let message):
            stageProcessing(message: message)
        case .finished:
            stageProcessing(message: "Finishing…")
        case .error(let error):
            stageError(error)
        }
    }

    private var currentSkippableKind: RKNCheckFlowState.FlowKind? {
        guard let stage = currentStageKind, let flow = state.flow else { return nil }
        let step = flow.steps.first(where: { $0.kind == stage.rawValue })
        return step?.skippable == true ? stage : nil
    }

    private var currentStageKind: RKNCheckFlowState.FlowKind? {
        if case .prompt(let kind) = state.stage { return kind }
        return nil
    }

    // MARK: - Stage views

    private var stageLoading: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(theme.accentColor)
            Text("Preparing verification…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundColor.ignoresSafeArea())
    }

    private func stageProcessing(message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(theme.accentColor)
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundColor.ignoresSafeArea())
    }

    private func stageError(_ error: RKNCheckError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(theme.errorColor)
            Text("Something went wrong")
                .font(.title2.bold())
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Button("Cancel verification") {
                onFinish(.failed(error: error))
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentColor)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundColor.ignoresSafeArea())
    }

    @ViewBuilder
    private func stagePrompt(_ kind: RKNCheckFlowState.FlowKind) -> some View {
        switch kind {
        case .document:
            // The `document` step accepts ANY identity document the tenant
            // allows — national ID card, residency permit or passport. Naming
            // one of them told a Qatari ID holder to produce a passport they
            // may not have, and made the step look mandatory-by-passport even
            // where the MRZ/NFC steps are switched off server-side.
            promptCard(
                title: "Scan your ID document",
                subtitle: "Place your ID card or passport flat under good light. We'll detect the photo automatically.",
                buttonTitle: "Open camera",
                systemImage: "doc.viewfinder",
                action: { showDocumentCamera = true }
            )
        case .mrz:
            promptCard(
                title: "Scan the MRZ",
                subtitle: "Aim at the two machine-readable lines at the bottom of the passport's data page.",
                buttonTitle: "Scan MRZ",
                systemImage: "text.viewfinder",
                action: { showMRZScanner = true }
            )
        case .nfc:
            nfcPrompt
        case .selfie:
            promptCard(
                title: "Take a live selfie",
                subtitle: "Follow the on-screen prompts: turn left, turn right, blink, then center your face.",
                buttonTitle: "Start liveness",
                systemImage: "faceid",
                action: { showLivenessCapture = true }
            )
        }
    }

    private func promptCard(
        title: String,
        subtitle: String,
        buttonTitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundStyle(theme.accentColor)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Spacer()
            Button(action: action) {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentColor)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundColor.ignoresSafeArea())
    }

    private var nfcPrompt: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .font(.system(size: 44))
                        .foregroundStyle(theme.accentColor)
                    VStack(alignment: .leading) {
                        Text("Read passport chip")
                            .font(.title2.bold())
                        Text("Confirm the values below match your passport, then place the top of your phone against the data page.")
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 12) {
                    TextField("Passport number", text: $nfcDocumentNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    TextField("Date of birth (YYYY-MM-DD)", text: $nfcDateOfBirth)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    TextField("Expiry date (YYYY-MM-DD)", text: $nfcExpiryDate)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }

                Button(action: {
                    coordinator?.setNFCAccessKey(
                        NFCAccessKey(
                            documentNumber: nfcDocumentNumber,
                            dateOfBirth: nfcDateOfBirth,
                            expiryDate: nfcExpiryDate
                        )
                    )
                    coordinator?.startNFCStep()
                }) {
                    Text("Read passport chip")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentColor)
                .disabled(!isNFCFormReady)
            }
            .padding(24)
        }
        .background(theme.backgroundColor.ignoresSafeArea())
        .onAppear {
            if nfcDocumentNumber.isEmpty, let key = state.nfcAccessKey {
                nfcDocumentNumber = key.documentNumber
                nfcDateOfBirth = key.dateOfBirth
                nfcExpiryDate = key.expiryDate
            }
        }
    }

    private var isNFCFormReady: Bool {
        !nfcDocumentNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !nfcDateOfBirth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !nfcExpiryDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private extension RKNCheckFlowState.FlowKind {
    var label: String {
        switch self {
        case .document: return "document"
        case .mrz: return "MRZ"
        case .nfc: return "NFC"
        case .selfie: return "selfie"
        }
    }
}
