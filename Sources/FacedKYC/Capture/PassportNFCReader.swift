import Foundation
import NFCPassportReader
import UIKit

struct PassportNFCCapture {
    let submission: NFCSubmission
    let portrait: UIImage?
}

enum PassportNFCReadError: LocalizedError {
    case missingMRZField(String)
    case invalidMRZDate(String)

    var errorDescription: String? {
        switch self {
        case .missingMRZField(let field):
            return "NFC reading needs the validated MRZ \(field). Scan the passport MRZ again."
        case .invalidMRZDate(let field):
            return "NFC reading needs the MRZ \(field) in YYYY-MM-DD or YYMMDD format."
        }
    }
}

final class PassportNFCReader {
    private let reader = PassportReader()

    func readPassport(accessKey: NFCAccessKey) async throws -> PassportNFCCapture {
        let documentNumber = try requiredMRZField(accessKey.documentNumber, name: "document number")
        let dateOfBirth = try yyMMdd(from: requiredMRZField(accessKey.dateOfBirth, name: "date of birth"), name: "date of birth")
        let expiryDate = try yyMMdd(from: requiredMRZField(accessKey.expiryDate, name: "expiry date"), name: "expiry date")

        let passport = try await reader.readPassport(
            mrzKey: Self.makeMRZKey(
                documentNumber: documentNumber,
                dateOfBirth: dateOfBirth,
                expiryDate: expiryDate
            ),
            tags: [.COM, .DG1, .DG2],
            skipSecureElements: true,
            skipCA: true,
            useExtendedMode: true,
            customDisplayMessage: Self.displayMessage
        )
        return makeCapture(from: passport)
    }

    private func makeCapture(from passport: NFCPassportModel) -> PassportNFCCapture {
        let authSucceeded = passport.BACStatus == .success || passport.PACEStatus == .success
        let portrait = passport.passportImage
        let chipValid = authSucceeded && !passport.documentNumber.isEmpty && passport.documentNumber != "?"

        let submission = NFCSubmission(
            chipRead: true,
            chipValid: chipValid,
            bacStatus: "\(passport.BACStatus)",
            paceStatus: "\(passport.PACEStatus)",
            passiveAuthenticationStatus: passport.passportDataNotTampered ? "data_groups_match_sod" : "not_checked",
            chipAuthenticationStatus: "\(passport.chipAuthenticationStatus)",
            dataGroups: passport.dataGroupsRead.keys.map { $0.getName() }.sorted(),
            dataGroupsPresent: passport.dataGroupsPresent.sorted(),
            portraitAvailable: portrait != nil,
            documentType: passport.documentType.cleanedMRZFiller,
            documentSubType: passport.documentSubType.cleanedMRZFiller,
            documentNumber: passport.documentNumber.cleanedMRZFiller,
            issuingAuthority: passport.issuingAuthority.cleanedMRZFiller,
            nationality: passport.nationality.cleanedMRZFiller,
            dateOfBirth: Self.isoDate(fromYYMMDD: passport.dateOfBirth),
            expiryDate: Self.isoDate(fromYYMMDD: passport.documentExpiryDate),
            gender: passport.gender.cleanedMRZFiller,
            lastName: passport.lastName.cleanedMRZFiller,
            firstName: passport.firstName.cleanedMRZFiller,
            personalNumber: passport.personalNumber?.cleanedMRZFiller,
            ldsVersion: passport.LDSVersion,
            mrz: passport.passportMRZ,
            errorMessage: nil,
            readAt: Self.isoNow(),
            portraitData: portrait?.jpegData(compressionQuality: 0.92)
        )

        return PassportNFCCapture(submission: submission, portrait: portrait)
    }

    private func requiredMRZField(_ value: String?, name: String) throws -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw PassportNFCReadError.missingMRZField(name)
        }
        return trimmed
    }

    private func yyMMdd(from value: String, name: String) throws -> String {
        let digits = value.filter(\.isNumber)
        if digits.count == 6 {
            return digits
        }
        if digits.count == 8 {
            return String(digits.suffix(6))
        }
        throw PassportNFCReadError.invalidMRZDate(name)
    }

    private static func isoDate(fromYYMMDD value: String) -> String? {
        let digits = value.filter(\.isNumber)
        guard digits.count == 6 else { return nil }

        let year = Int(digits.prefix(2)) ?? 0
        let currentTwoDigitYear = Calendar.current.component(.year, from: Date()) % 100
        let century = year <= currentTwoDigitYear + 10 ? 2000 : 1900
        return "\(century + year)-\(digits.dropFirst(2).prefix(2))-\(digits.suffix(2))"
    }

    private static func makeMRZKey(documentNumber: String, dateOfBirth: String, expiryDate: String) -> String {
        let documentField = padMRZ(documentNumber.cleanedMRZFiller, length: 9)
        let birthField = padMRZ(dateOfBirth, length: 6)
        let expiryField = padMRZ(expiryDate, length: 6)

        return documentField +
            String(checkDigit(for: documentField)) +
            birthField +
            String(checkDigit(for: birthField)) +
            expiryField +
            String(checkDigit(for: expiryField))
    }

    private static func padMRZ(_ value: String, length: Int) -> String {
        String((value.uppercased() + String(repeating: "<", count: length)).prefix(length))
    }

    private static func checkDigit(for value: String) -> Int {
        let weights = [7, 3, 1]
        let total = value.enumerated().reduce(0) { partial, item in
            partial + mrzValue(item.element) * weights[item.offset % weights.count]
        }
        return total % 10
    }

    private static func mrzValue(_ character: Character) -> Int {
        if character == "<" { return 0 }
        if let digit = character.wholeNumberValue { return digit }
        guard let scalar = character.unicodeScalars.first else { return 0 }
        return Int(scalar.value) - Int(UnicodeScalar("A").value) + 10
    }

    nonisolated private static func displayMessage(_ message: NFCViewDisplayMessage) -> String? {
        switch message {
        case .requestPresentPassport:
            return "Hold the top of your iPhone on the passport chip icon. Keep it still until this finishes."
        case .authenticatingWithPassport:
            return "Unlocking passport chip using the scanned MRZ..."
        case .readingDataGroupProgress(let group, let progress):
            return "Reading passport chip \(group.getName())...\n\(progress)%"
        case .successfulRead:
            return "Passport chip read successfully."
        case .error:
            return "Could not read the passport chip. Keep the phone on the chip icon and try again."
        default:
            return nil
        }
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

private extension String {
    var cleanedMRZFiller: String {
        replacingOccurrences(of: "<", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
