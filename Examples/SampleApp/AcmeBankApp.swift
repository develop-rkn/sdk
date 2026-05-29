import SwiftUI
import FacedKYC

@main
struct AcmeBankApp: App {
    init() {
        FacedSDK.configure(
            FacedConfiguration(
                host: URL(string: "https://kyc.acme-bank.com")!,
                theme: FacedTheme(accentColor: .blue)
            )
        )
    }

    var body: some Scene {
        WindowGroup { OnboardingView() }
    }
}

struct OnboardingView: View {
    @State private var clientToken: String?
    @State private var showVerification = false
    @State private var status = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Verify your identity")
                .font(.largeTitle.bold())
            Text("Takes about a minute.")
                .foregroundStyle(.secondary)

            Button(action: start) {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Start").frame(maxWidth: .infinity).padding(.vertical, 10)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            if !status.isEmpty {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding()
        .facedVerification(
            isPresented: $showVerification,
            clientToken: clientToken ?? "",
            onResult: handle
        )
    }

    private func start() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                clientToken = try await fetchClientToken()
                showVerification = true
            } catch {
                status = "Could not start: \(error.localizedDescription)"
            }
        }
    }

    private func handle(_ result: FacedResult) {
        switch result {
        case .approved(let sessionId):
            status = "Approved (\(sessionId)). Awaiting webhook confirmation."
        case .needsReview(let sessionId, let reason):
            status = "Manual review for \(sessionId): \(reason ?? "no reason given")"
        case .rejected(let sessionId, let reason):
            status = "Rejected for \(sessionId): \(reason ?? "no reason given")"
        case .canceled(let sessionId):
            status = "Canceled \(sessionId.map { "(\($0))" } ?? "")"
        case .failed(let error):
            status = "Error: \(error.localizedDescription)"
        }
    }

    // Replace with a real call to YOUR backend. Your backend calls
    // POST /v1/sessions on the Faced deployment and returns the clientToken.
    private func fetchClientToken() async throws -> String {
        struct Response: Decodable { let clientToken: String }
        var request = URLRequest(url: URL(string: "https://api.acme-bank.com/onboarding/start")!)
        request.httpMethod = "POST"
        request.setValue("Bearer USER_SESSION_TOKEN", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Response.self, from: data).clientToken
    }
}
