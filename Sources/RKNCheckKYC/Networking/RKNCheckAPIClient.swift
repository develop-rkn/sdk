import Foundation
import UIKit

/// Internal HTTP client that talks to the RKN-Check `/v1/...` endpoints using a
/// client-token-only credential. The fintech's secret key NEVER lives on the
/// device; the token is short-lived and scoped to a single session.
struct RKNCheckAPIClient {
    private let host: URL
    private let clientToken: String
    private let tokenExpiresAt: Date?
    private let licenseKey: String?
    private let session: URLSession

    init(host: URL, clientToken: String, timeout: TimeInterval, licenseKey: String? = nil) {
        self.host = host
        self.clientToken = clientToken
        self.tokenExpiresAt = Self.decodeTokenExpiry(clientToken)
        self.licenseKey = licenseKey
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = max(timeout, 60)
        configuration.httpAdditionalHeaders = [
            "User-Agent": "RKNCheckKYC-iOS/\(RKNCheckSDK.version)"
        ]
        self.session = URLSession(configuration: configuration)
    }

    /// Throws if the token is structurally invalid or already expired. Cheap
    /// to call — no network. The flow coordinator runs this once at startup
    /// so integrators get a precise error before any modal UI appears.
    func validateToken() throws {
        guard !clientToken.isEmpty else { throw RKNCheckError.clientTokenMalformed }
        guard let expiresAt = tokenExpiresAt else { throw RKNCheckError.clientTokenMalformed }
        if Date() >= expiresAt { throw RKNCheckError.clientTokenExpired(expiredAt: expiresAt) }
    }

    func fetchSession() async throws -> SessionStatusDTO {
        let url = try endpoint("/v1/sessions/\(sessionId)")
        let request = makeRequest(url: url, method: "GET")
        return try await sendForEnvelope(request)
    }

    func fetchFlow() async throws -> FlowDefinitionDTO {
        let url = try endpoint("/v1/sessions/\(sessionId)/flow")
        let request = makeRequest(url: url, method: "GET")
        return try await sendForEnvelope(request)
    }

    func uploadDocument(imageData: Data) async throws -> SessionStatusDTO {
        let url = try endpoint("/v1/sessions/\(sessionId)/document")
        let (request, body) = makeMultipartRequest(url: url, image: imageData, imageField: "image")
        return try await sendForEnvelope(request, body: body)
    }

    func submitMRZ(mrzText: String) async throws -> SessionStatusDTO {
        let url = try endpoint("/v1/sessions/\(sessionId)/document/mrz")
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(["mrzText": mrzText, "source": "ios_sdk"])
        return try await sendForEnvelope(request, body: body)
    }

    func submitNFC(submission: NFCSubmission) async throws -> SessionStatusDTO {
        let url = try endpoint("/v1/sessions/\(sessionId)/document/nfc")
        let (request, body) = makeNFCMultipart(url: url, submission: submission)
        return try await sendForEnvelope(request, body: body)
    }

    func uploadSelfie(imageData: Data, liveness: LivenessSubmission) async throws -> SessionStatusDTO {
        let url = try endpoint("/v1/sessions/\(sessionId)/selfie")
        let (request, body) = makeSelfieMultipart(url: url, image: imageData, liveness: liveness)
        return try await sendForEnvelope(request, body: body)
    }

    func completeSession(clientStatus: String) async throws -> SessionStatusDTO {
        let url = try endpoint("/v1/sessions/\(sessionId)/complete")
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONSerialization.data(
            withJSONObject: [
                "clientStatus": clientStatus,
                "device": ["platform": "ios", "sdkVersion": RKNCheckSDK.version]
            ],
            options: [.sortedKeys]
        )
        return try await sendForEnvelope(request, body: body)
    }

    // MARK: - Helpers

    /// `sid` extracted from the client token payload, used to build URLs.
    var sessionId: String {
        let stripped = clientToken.hasPrefix("ct_") ? String(clientToken.dropFirst(3)) : clientToken
        guard let payloadPart = stripped.split(separator: ".").first else { return "" }
        guard let decoded = base64URLDecode(String(payloadPart)) else { return "" }
        guard let object = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] else { return "" }
        return object["sid"] as? String ?? ""
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let url = Self.composeURL(host: host, path: path) else {
            throw RKNCheckError.internalError("Could not build URL for \(path).")
        }
        return url
    }

    /// Compose `host + path` such that any proxy prefix baked into `host` is
    /// preserved (e.g. `https://kyc-host/biometrics`). We deliberately do not
    /// use `URL(string:relativeTo:)` because the relative-URL resolver treats
    /// an absolute path (one starting with `/`) as replacing the host's entire
    /// path component — which would silently drop the prefix on every call
    /// and break KYC's `/biometrics/*` reverse proxy.
    static func composeURL(host: URL, path: String) -> URL? {
        let base = host.absoluteString
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: trimmedBase + normalizedPath)
    }

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
        // The client's RKN licence rides along on every call; the backend
        // verifies the signature and refuses modules the licence doesn't
        // cover (belt-and-braces with the tenant's stored licence).
        if let licenseKey, !licenseKey.isEmpty {
            request.setValue(licenseKey, forHTTPHeaderField: "X-RKN-License")
        }
        return request
    }

    private func makeMultipartRequest(
        url: URL,
        image: Data,
        imageField: String
    ) -> (URLRequest, Data) {
        let boundary = "rkn-check-\(UUID().uuidString)"
        var request = makeRequest(url: url, method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendField(boundary: boundary, name: imageField, filename: "\(imageField).jpg", mimeType: "image/jpeg", data: image)
        body.append("--\(boundary)--\r\n")
        return (request, body)
    }

    private func makeSelfieMultipart(
        url: URL,
        image: Data,
        liveness: LivenessSubmission
    ) -> (URLRequest, Data) {
        let boundary = "rkn-check-\(UUID().uuidString)"
        var request = makeRequest(url: url, method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendField(boundary: boundary, name: "image", filename: "selfie.jpg", mimeType: "image/jpeg", data: image)
        body.appendTextField(boundary: boundary, name: "activeLivenessDecision", value: liveness.decision)
        body.appendTextField(boundary: boundary, name: "activeLivenessChallenges", value: liveness.challenges.joined(separator: ","))
        body.appendTextField(boundary: boundary, name: "activeLivenessFrameCount", value: String(liveness.frameCount))
        body.appendTextField(boundary: boundary, name: "activeLivenessDurationMs", value: String(liveness.durationMs))
        body.appendTextField(boundary: boundary, name: "activeLivenessCompletedAt", value: liveness.completedAt)
        body.append("--\(boundary)--\r\n")
        return (request, body)
    }

    private func makeNFCMultipart(
        url: URL,
        submission: NFCSubmission
    ) -> (URLRequest, Data) {
        let boundary = "rkn-check-\(UUID().uuidString)"
        var request = makeRequest(url: url, method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendTextField(boundary: boundary, name: "chipRead", value: submission.chipRead ? "true" : "false")
        body.appendTextField(boundary: boundary, name: "chipValid", value: submission.chipValid ? "true" : "false")
        body.appendTextField(boundary: boundary, name: "portraitAvailable", value: submission.portraitAvailable ? "true" : "false")
        body.appendTextField(boundary: boundary, name: "dataGroups", value: submission.dataGroups.joined(separator: ","))
        body.appendTextField(boundary: boundary, name: "dataGroupsPresent", value: submission.dataGroupsPresent.joined(separator: ","))
        body.appendTextField(boundary: boundary, name: "readAt", value: submission.readAt)

        let optionalPairs: [(String, String?)] = [
            ("bacStatus", submission.bacStatus),
            ("paceStatus", submission.paceStatus),
            ("passiveAuthenticationStatus", submission.passiveAuthenticationStatus),
            ("chipAuthenticationStatus", submission.chipAuthenticationStatus),
            ("documentType", submission.documentType),
            ("documentSubType", submission.documentSubType),
            ("documentNumber", submission.documentNumber),
            ("issuingAuthority", submission.issuingAuthority),
            ("nationality", submission.nationality),
            ("dateOfBirth", submission.dateOfBirth),
            ("expiryDate", submission.expiryDate),
            ("gender", submission.gender),
            ("lastName", submission.lastName),
            ("firstName", submission.firstName),
            ("personalNumber", submission.personalNumber),
            ("ldsVersion", submission.ldsVersion),
            ("mrz", submission.mrz),
            ("errorMessage", submission.errorMessage)
        ]
        for (name, value) in optionalPairs {
            if let value, !value.isEmpty {
                body.appendTextField(boundary: boundary, name: name, value: value)
            }
        }

        if let portraitData = submission.portraitData {
            body.appendField(
                boundary: boundary,
                name: "chipPortrait",
                filename: "nfc_portrait.jpg",
                mimeType: "image/jpeg",
                data: portraitData
            )
        }

        body.append("--\(boundary)--\r\n")
        return (request, body)
    }

    private func sendForEnvelope<T: Decodable>(_ request: URLRequest, body: Data? = nil) async throws -> T {
        var requestCopy = request
        if let body {
            requestCopy.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: requestCopy)
        } catch let urlError as URLError {
            throw RKNCheckError.network(urlError)
        } catch {
            throw RKNCheckError.internalError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RKNCheckError.internalError("Response was not an HTTP response.")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            // If the token has a past `exp` claim, prefer the more specific
            // error — saves integrators from hunting down stale tokens.
            if let expiresAt = tokenExpiresAt, expiresAt <= Date() {
                throw RKNCheckError.clientTokenExpired(expiredAt: expiresAt)
            }
            throw RKNCheckError.clientTokenUnauthorized
        }

        if !(200..<300).contains(http.statusCode) {
            let message = decodeErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw RKNCheckError.server(statusCode: http.statusCode, message: message)
        }

        do {
            let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
            guard envelope.success, let payload = envelope.data else {
                throw RKNCheckError.server(
                    statusCode: http.statusCode,
                    message: envelope.error?.message ?? "Backend returned an error envelope."
                )
            }
            return payload
        } catch let decodingError {
            throw RKNCheckError.internalError("Response decode failed: \(decodingError)")
        }
    }

    private static func decodeTokenExpiry(_ token: String) -> Date? {
        let stripped = token.hasPrefix("ct_") ? String(token.dropFirst(3)) : token
        guard let payloadPart = stripped.split(separator: ".").first else { return nil }
        let padded = padBase64URL(String(payloadPart))
        guard let data = Data(base64Encoded: padded) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let exp = object["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private static func padBase64URL(_ value: String) -> String {
        var s = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return s
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(APIEnvelope<SessionStatusDTO>.self, from: data),
           let message = envelope.error?.message {
            return message
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? String {
                return detail
            }
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
        }
        return nil
    }

    private func base64URLDecode(_ value: String) -> Data? {
        var s = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendField(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        append("\r\n")
    }

    mutating func appendTextField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }
}
