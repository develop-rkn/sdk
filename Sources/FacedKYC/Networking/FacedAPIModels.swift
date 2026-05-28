import Foundation

struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: APIError?
}

struct APIError: Decodable {
    let message: String
    let code: String?
}

struct FlowDefinitionDTO: Decodable {
    let steps: [FlowStepDTO]
    let livenessMode: String
    let locale: String
    let brandName: String
}

struct FlowStepDTO: Decodable {
    let kind: String
    let required: Bool
    let skippable: Bool
}

struct SessionStatusDTO: Decodable {
    let sessionId: String?
    let customerId: String?
    let status: String?
    let documentFaceDetected: Bool?
    let documentFaceQuality: Double?
    let mrzDetected: Bool?
    let mrzValid: Bool?
    let nfcRequired: Bool?
    let documentNumber: String?
    let nationality: String?
    let dateOfBirth: String?
    let expiryDate: String?
    let mrzValidationErrors: [String]?
    let nfcRead: Bool?
    let nfcValid: Bool?
    let nfcValidationErrors: [String]?
    let selfieFaceDetected: Bool?
    let selfieFaceQuality: Double?
    let livenessDecision: String?
    let isIdentical: Bool?
    let matchConfidence: Double?
    let faceMatchScore: Double?
    let faceMatchDecision: String?
    let requiresManualReview: Bool?
    let reason: String?
    let documentImageId: String?
    let documentPortraitId: String?
    let selfieImageId: String?
    let completedAt: String?
}

struct LivenessSubmission {
    let decision: String
    let challenges: [String]
    let frameCount: Int
    let durationMs: Int
    let completedAt: String
}

struct NFCSubmission {
    let chipRead: Bool
    let chipValid: Bool
    let bacStatus: String?
    let paceStatus: String?
    let passiveAuthenticationStatus: String?
    let chipAuthenticationStatus: String?
    let dataGroups: [String]
    let dataGroupsPresent: [String]
    let portraitAvailable: Bool
    let documentType: String?
    let documentSubType: String?
    let documentNumber: String?
    let issuingAuthority: String?
    let nationality: String?
    let dateOfBirth: String?
    let expiryDate: String?
    let gender: String?
    let lastName: String?
    let firstName: String?
    let personalNumber: String?
    let ldsVersion: String?
    let mrz: String?
    let errorMessage: String?
    let readAt: String
    let portraitData: Data?
}

struct NFCAccessKey {
    let documentNumber: String
    let dateOfBirth: String
    let expiryDate: String
}
