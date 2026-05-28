import SwiftUI
import UIKit

/// Lightweight theming hook so a fintech can adopt their brand colors without
/// touching the SDK source.
public struct FacedTheme {
    public let accentColor: Color
    public let backgroundColor: Color
    public let errorColor: Color
    public let successColor: Color

    public init(
        accentColor: Color = .accentColor,
        backgroundColor: Color = Color(.systemGroupedBackground),
        errorColor: Color = .red,
        successColor: Color = .green
    ) {
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.errorColor = errorColor
        self.successColor = successColor
    }

    public static let `default`: FacedTheme = FacedTheme()
}
