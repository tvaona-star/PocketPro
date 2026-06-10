import SwiftUI
import PocketProCore

// Design tokens (PRD 7.1). Dark mode is the primary design expression; light values
// are functional counterparts that follow the iOS system setting.

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Dark-primary adaptive color: `dark` is the designed value (PRD), `light` the secondary mode.
    static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .light ? light : dark
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

enum Theme {
    // Backgrounds
    static let bgPrimary = Color.adaptive(dark: 0x0F1117, light: 0xF2F3F7)
    static let bgCard = Color.adaptive(dark: 0x1C1F26, light: 0xFFFFFF)
    static let bgElevated = Color.adaptive(dark: 0x252930, light: 0xFFFFFF)

    // Accents
    static let accent = Color.adaptive(dark: 0x3B82F6, light: 0x2563EB)   // electric blue (DECISIONS.md D15)
    static let destructive = Color.adaptive(dark: 0xDC2626, light: 0xDC2626)
    static let success = Color.adaptive(dark: 0x16A34A, light: 0x15803D)
    static let warning = Color.adaptive(dark: 0xD97706, light: 0xB45309)

    // Text
    static let textPrimary = Color.adaptive(dark: 0xFFFFFF, light: 0x111318)
    static let textSecondary = Color.adaptive(dark: 0x9CA3AF, light: 0x5B6472)
    static let textMuted = Color.adaptive(dark: 0x6B7280, light: 0x8A919D)

    static let separator = Color.adaptive(dark: 0x2D3139, light: 0xE2E4EA)

    // Coverstock badge colors (PRD 7.1 iconography).
    static func coverstockColor(_ type: CoverstockType?) -> Color {
        switch type {
        case .solid: return Color.adaptive(dark: 0x4A7BA6, light: 0x3D6A94)      // steel blue
        case .pearl: return Color.adaptive(dark: 0xA855F7, light: 0x9333EA)      // purple
        case .hybrid: return Color.adaptive(dark: 0x14B8A6, light: 0x0D9488)     // teal
        case .urethane: return Color.adaptive(dark: 0xD97706, light: 0xB45309)   // amber
        case .polyester, .none: return Color.adaptive(dark: 0x6B7280, light: 0x8A919D) // grey
        }
    }

    /// Conversion-rate color coding (PRD 5.5.4): green 80%+, amber 50–79%, red below.
    static func conversionColor(_ percent: Double?) -> Color {
        guard let percent else { return textMuted }
        if percent >= 80 { return success }
        if percent >= 50 { return warning }
        return destructive
    }

    static func sessionTypeColor(_ type: SessionType) -> Color {
        switch type {
        case .league: return accent
        case .tournament: return Color.adaptive(dark: 0xA855F7, light: 0x9333EA)
        case .practice: return success
        case .misc: return textMuted
        }
    }

    // Typography (PRD 7.1): SF Pro only; stat numbers large/bold/tabular.
    static func statNumber(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .default).monospacedDigit()
    }

    static let statLabel = Font.system(size: 12, weight: .medium)
    static let cardTitle = Font.system(size: 17, weight: .semibold)
    static let cardSubtitle = Font.system(size: 13, weight: .regular)
    static let badge = Font.system(size: 11, weight: .semibold)

    static let cardCornerRadius: CGFloat = 14
    static let sectionSpring = Animation.spring(response: 0.25, dampingFraction: 0.9)
}

// MARK: - Common card chrome

struct CardBackground: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View {
        modifier(CardBackground(padding: padding))
    }
}
