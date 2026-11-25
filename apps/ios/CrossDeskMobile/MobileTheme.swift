import SwiftUI

// Shared visual language for the native iOS app.
//
// The screens were built one by one with slightly different radii, shadows and
// button treatments, which reads as "unpolished" next to the desktop app. Every
// surface token lives here so a screen only has to reach for `cdCard()`,
// `CDPrimaryButtonStyle` or `CDEmptyState` instead of hand-rolling a card.
//
// Target is iOS 16, so nothing newer than `ContentUnavailableView`/`.symbolEffect`
// is used here; those are iOS 17+.

enum CDTheme {
    // MARK: Palette

    static let brandStart = Color(red: 0.16, green: 0.40, blue: 0.94)
    static let brandEnd = Color(red: 0.45, green: 0.27, blue: 0.90)
    static let accent = Color(red: 0.22, green: 0.44, blue: 0.93)

    /// Page background. Slightly cool so white cards read as raised surfaces.
    static let canvas = Color(red: 0.956, green: 0.962, blue: 0.976)
    static let card = Color.white
    static let cardMuted = Color(red: 0.973, green: 0.976, blue: 0.984)

    static let stroke = Color.black.opacity(0.055)
    static let strokeStrong = Color.black.opacity(0.10)

    static let success = Color(red: 0.13, green: 0.62, blue: 0.36)
    static let warning = Color(red: 0.86, green: 0.55, blue: 0.10)
    static let danger = Color(red: 0.86, green: 0.26, blue: 0.24)
    static let unread = Color(red: 0.20, green: 0.42, blue: 0.95)

    // MARK: Metrics

    static let cardRadius: CGFloat = 22
    static let innerRadius: CGFloat = 14
    static let gutter: CGFloat = 16
    static let cardPadding: CGFloat = 18

    static let brandGradient = LinearGradient(
        colors: [brandStart, brandEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [accent, brandEnd],
        startPoint: .leading,
        endPoint: .trailing
    )

    static func platformGradient(for platform: RemoteHostPlatform) -> [Color] {
        switch platform {
        case .windows:
            return [Color(red: 0.13, green: 0.42, blue: 0.83), Color(red: 0.24, green: 0.58, blue: 0.94)]
        case .linux:
            return [Color(red: 0.74, green: 0.42, blue: 0.12), Color(red: 0.90, green: 0.62, blue: 0.20)]
        case .macos:
            return [Color(red: 0.44, green: 0.29, blue: 0.72), Color(red: 0.62, green: 0.44, blue: 0.92)]
        case .ios:
            return [Color(red: 0.10, green: 0.50, blue: 0.46), Color(red: 0.19, green: 0.68, blue: 0.60)]
        case .unknown:
            return [Color(red: 0.36, green: 0.41, blue: 0.48), Color(red: 0.52, green: 0.57, blue: 0.64)]
        }
    }
}

// MARK: - Surfaces

private struct CDCardModifier: ViewModifier {
    let radius: CGFloat
    let padding: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(CDTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(CDTheme.stroke, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(elevated ? 0.07 : 0.035),
                    radius: elevated ? 20 : 12,
                    x: 0,
                    y: elevated ? 9 : 5)
    }
}

extension View {
    /// White rounded surface with the app's border and shadow tokens.
    func cdCard(radius: CGFloat = CDTheme.cardRadius,
                padding: CGFloat = CDTheme.cardPadding,
                elevated: Bool = true) -> some View {
        modifier(CDCardModifier(radius: radius, padding: padding, elevated: elevated))
    }

    /// Inset field/segment background used inside cards.
    func cdInset(radius: CGFloat = CDTheme.innerRadius) -> some View {
        background(CDTheme.cardMuted, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(CDTheme.stroke, lineWidth: 1)
            }
    }
}

/// Page background: flat canvas plus two very soft brand glows.
struct CDCanvasBackground: View {
    var body: some View {
        ZStack {
            CDTheme.canvas
            RadialGradient(colors: [CDTheme.accent.opacity(0.13), .clear],
                           center: .topLeading,
                           startRadius: 10,
                           endRadius: 420)
            RadialGradient(colors: [CDTheme.brandEnd.opacity(0.10), .clear],
                           center: .topTrailing,
                           startRadius: 10,
                           endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Buttons

/// Filled brand button: gradient capsule, press scale, disabled dimming.
struct CDPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54
    var radius: CGFloat = 16

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(CDTheme.brandGradient,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: CDTheme.accent.opacity(isEnabled ? 0.28 : 0),
                    radius: 12, x: 0, y: 6)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Press feedback for cards and rows: no chrome, just a gentle shrink.
struct CDCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Square icon tile used in toolbars, with an optional numeric badge or dot.
struct CDIconTile: View {
    let systemImage: String
    var badgeText: String?
    var showsDot: Bool = false
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(CDTheme.accent)
            .frame(width: size, height: size)
            .background(CDTheme.card, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(CDTheme.stroke, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(CDTheme.danger, in: Capsule())
                        .overlay(Capsule().strokeBorder(CDTheme.card, lineWidth: 1.2))
                        .offset(x: 5, y: -4)
                } else if showsDot {
                    Circle()
                        .fill(CDTheme.danger)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(CDTheme.card, lineWidth: 1.2))
                        .offset(x: 2, y: -2)
                }
            }
    }
}

// MARK: - Small pieces

/// Status capsule: icon + short label, tinted.
struct CDPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = CDTheme.accent
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 9 : 11, weight: .bold))
            }
            Text(text)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.20), lineWidth: 1))
    }
}

/// Section title with an optional subtitle and trailing accessory.
struct CDSectionTitle<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension CDSectionTitle where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Inline message strip for errors and warnings.
enum CDBannerKind {
    case error
    case warning
    case info

    var tint: Color {
        switch self {
        case .error: return CDTheme.danger
        case .warning: return CDTheme.warning
        case .info: return CDTheme.accent
        }
    }

    var systemImage: String {
        switch self {
        case .error: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct CDBanner: View {
    let kind: CDBannerKind
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.systemImage)
                .font(.footnote.weight(.bold))
                .foregroundStyle(kind.tint)
                .padding(.top, 1)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(kind.tint)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(kind.tint.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: CDTheme.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CDTheme.innerRadius, style: .continuous)
                .strokeBorder(kind.tint.opacity(0.22), lineWidth: 1)
        }
    }
}

/// Empty / zero-data state with an optional action.
struct CDEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CDTheme.accent.opacity(0.10))
                    .frame(width: 66, height: 66)
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(CDTheme.accent)
            }
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CDTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(CDTheme.accent.opacity(0.10), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
    }
}

/// Compact metric used in the announcement header.
struct CDMetric: View {
    let value: String
    let label: String
    var tint: Color = CDTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
