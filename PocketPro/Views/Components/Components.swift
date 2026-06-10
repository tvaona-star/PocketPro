import SwiftUI
import PocketProCore

// Shared UI building blocks (PRD 7.1–7.3). Every data-rich screen composes these.

// MARK: - Badges & chips

struct Badge: View {
    let text: String
    var color: Color = Theme.accent
    var filled: Bool = true

    var body: some View {
        Text(text)
            .font(Theme.badge)
            .foregroundStyle(filled ? Color.white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(filled ? color : color.opacity(0.18))
            .clipShape(Capsule())
    }
}

struct CoverstockBadge: View {
    let type: CoverstockType?

    var body: some View {
        Badge(text: type?.displayName ?? "Unknown", color: Theme.coverstockColor(type))
    }
}

struct ThumbBadge: View {
    let type: ThumbType

    var body: some View {
        Text(type.displayName)
            .font(Theme.badge)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
    }
}

struct FilterChip: View {
    let label: String
    var isActive: Bool = false
    var onTap: () -> Void = {}
    var onDismiss: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(isActive ? Color.white : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isActive ? Theme.accent : Theme.bgElevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat tiles (PRD 7.5: broadcast style — big number, small label, trend beside)

struct StatTile: View {
    let label: String
    let value: String
    var trend: Double?
    var trendGoodWhenUp: Bool = true
    var numberSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(Theme.statNumber(numberSize))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let trend, trend != 0 {
                    TrendArrow(delta: trend, goodWhenUp: trendGoodWhenUp)
                }
            }
            Text(label.uppercased())
                .font(Theme.statLabel)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .card()
    }
}

struct TrendArrow: View {
    let delta: Double
    var goodWhenUp: Bool = true
    var suffix: String = ""

    private var isGood: Bool {
        goodWhenUp ? delta > 0 : delta < 0
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                .font(.system(size: 11, weight: .bold))
            Text(String(format: "%.1f%@", abs(delta), suffix))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(isGood ? Theme.success : Theme.destructive)
    }
}

/// Count-up animation on first load, 300 ms (PRD 7.3); later updates render instantly.
struct CountUpText: View {
    let target: Double
    let formatter: (Double) -> String
    var font: Font = Theme.statNumber()

    @State private var displayed: Double = 0
    @State private var hasAnimated = false

    var body: some View {
        Text(formatter(displayed))
            .font(font)
            .foregroundStyle(Theme.textPrimary)
            .onAppear {
                guard !hasAnimated else {
                    displayed = target
                    return
                }
                hasAnimated = true
                animate()
            }
            .onChange(of: target) { _, newValue in
                displayed = newValue
            }
    }

    private func animate() {
        let steps = 12
        let duration = 0.3
        for step in 1...steps {
            let fraction = Double(step) / Double(steps)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * fraction) {
                displayed = target * fraction
            }
        }
    }
}

// MARK: - Collapsible section card (PRD 7.2 card model, Tier 2)

struct SectionCard<Preview: View, Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var preview: () -> Preview
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Theme.sectionSpring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(Theme.cardTitle)
                            .foregroundStyle(Theme.textPrimary)
                        preview()
                            .font(Theme.cardSubtitle)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(Theme.separator)
                    .padding(.vertical, 10)
                content()
            }
        }
        .card()
    }
}

// MARK: - Empty states (PRD 7.4: always say what to do next)

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.textMuted)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Pin deck (PRD 7.1: filled circles standing, outline knocked)

/// Interactive pin deck for live entry (PRD 5.1 scorecard).
/// Semantics: the bowler taps the pins LEFT STANDING after the ball — untapped pins
/// count as knocked down, so the default commit is a strike (ball 1) or spare (ball 2).
/// Filled circle = standing, outline = down (PRD 7.1 iconography).
struct PinDeckView: View {
    /// Pins standing at the current rack before this ball is thrown.
    let available: PinSet
    /// Pins the bowler marked as still standing after the ball (subset of `available`).
    @Binding var standingAfter: PinSet
    var pinSize: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(1...10, id: \.self) { pin in
                    pinView(pin)
                        .position(position(pin: pin, in: geo.size))
                }
            }
        }
        .aspectRatio(1.45, contentMode: .fit)
    }

    private func position(pin: Int, in size: CGSize) -> CGPoint {
        let unit = PinGeometry.unitPoint(pin: pin)
        return CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }

    @ViewBuilder
    private func pinView(_ pin: Int) -> some View {
        let isAvailable = available.contains(pin)
        let isStanding = standingAfter.contains(pin)

        Button {
            guard isAvailable else { return }
            standingAfter.toggle(pin)
        } label: {
            ZStack {
                Circle()
                    .fill(isStanding ? Theme.textPrimary : Color.clear)
                Circle()
                    .strokeBorder(isStanding ? Theme.textPrimary : Theme.textMuted, lineWidth: 2)
                Text("\(pin)")
                    .font(.system(size: pinSize * 0.34, weight: .bold).monospacedDigit())
                    .foregroundStyle(isStanding ? Theme.bgPrimary : Theme.textMuted)
            }
            .frame(width: pinSize, height: pinSize)
            .opacity(isAvailable ? 1 : 0.25)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }
}

/// Small display-only pin diagram for leave rows (standing pins filled).
struct PinDiagram: View {
    let standing: PinSet
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            ForEach(1...10, id: \.self) { pin in
                let unit = PinGeometry.unitPoint(pin: pin)
                Circle()
                    .fill(standing.contains(pin) ? Theme.textPrimary : Color.clear)
                    .overlay(Circle().strokeBorder(standing.contains(pin) ? Theme.textPrimary : Theme.textMuted.opacity(0.5), lineWidth: 1))
                    .frame(width: size * 0.2, height: size * 0.2)
                    .position(x: unit.x * size, y: unit.y * size)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Sheet chrome

struct SheetHeader: View {
    let title: String
    var trailing: String = "Done"
    var trailingDisabled: Bool = false
    var onTrailing: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button(trailing, action: onTrailing)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(trailingDisabled ? Theme.textMuted : Theme.accent)
                .disabled(trailingDisabled)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Optional numeric entry

/// Numeric entry bound to `Double?` where an empty field means nil.
/// Text-backed on purpose: SwiftUI's format-based TextField initializers require
/// `Binding<F.FormatInput>` exactly (no Optional overload), and the legacy
/// formatter-based one only commits on return — useless with a decimal pad.
struct OptionalNumberField: View {
    let placeholder: String
    @Binding var value: Double?
    var keyboard: UIKeyboardType = .decimalPad

    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.trailing)
            .onAppear {
                text = value.map(Self.format) ?? ""
            }
            .onChange(of: text) { _, newText in
                value = Self.parse(newText)
            }
            .onChange(of: value) { _, newValue in
                // Refresh on external resets (form repopulation) without
                // clobbering in-progress typing ("4." parses equal to 4).
                if newValue != Self.parse(text) {
                    text = newValue.map(Self.format) ?? ""
                }
            }
    }

    private static func parse(_ raw: String) -> Double? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(normalized)
    }

    private static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}

// MARK: - Labeled rows

struct SpecRow: View {
    let label: String
    let value: String
    var highlighted: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(highlighted ? Theme.warning : Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}
