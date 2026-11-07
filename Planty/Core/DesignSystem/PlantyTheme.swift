import SwiftUI
import UIKit

/// Planty colour tokens. Each token has a light and a dark value.
/// Views use these tokens only, never raw colours.
extension Color {
    static let plantyBackground = Color(light: 0xF7F5ED, dark: 0x141A16)
    static let plantySurface = Color(light: 0xFFFDF8, dark: 0x1E2721)
    static let plantyMint = Color(light: 0xDDEBDD, dark: 0x2B3A2F)
    static let plantySage = Color(light: 0x8FAF91, dark: 0x8FAF91)
    static let plantyForest = Color(light: 0x355C46, dark: 0x8FAF91)
    static let plantyOnForest = Color(light: 0xFFFDF8, dark: 0x141A16)
    static let plantyBeige = Color(light: 0xE9E3D6, dark: 0x2E3A31)
    static let plantyTextPrimary = Color(light: 0x1F2D24, dark: 0xEEF2EA)
    static let plantyTextSecondary = Color(light: 0x56655A, dark: 0xA9B5A6)

    static let plantyHealthy = Color(light: 0x65A878, dark: 0x7DBE8F)
    static let plantyWarning = Color(light: 0xE7B75D, dark: 0xE7B75D)
    static let plantyCritical = Color(light: 0xD97870, dark: 0xE38D86)
    static let plantyWater = Color(light: 0x65B7DD, dark: 0x7CC3E4)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Type scale. Headings use SF Pro Rounded; all sizes follow Dynamic Type.
extension Font {
    static let plantyLargeTitle = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    static let plantyTitle = Font.system(.title2, design: .rounded).weight(.bold)
    static let plantyHeadline = Font.system(.headline)
    static let plantyBody = Font.system(.body)
    static let plantyCaption = Font.system(.footnote)
}

enum PlantySpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

enum PlantyRadius {
    static let card: CGFloat = 20
    static let button: CGFloat = 16
    static let hero: CGFloat = 32
}
