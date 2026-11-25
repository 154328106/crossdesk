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
    static let canvasTop = Color(red: 0.925, green: 0.933, blue: 0.960)
    static let canvas = Color(red: 0.949, green: 0.953, blue: 0.972)
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
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        // A whisper of white keeps the frosted surface luminous
                        // over the tinted canvas instead of going grey.
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.52), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(elevated ? 0.08 : 0.04),
                    radius: elevated ? 22 : 12,
                    x: 0,
                    y: elevated ? 10 : 5)
    }
}

extension View {
    /// Frosted rounded surface with the app's border and shadow tokens.
    func cdCard(radius: CGFloat = CDTheme.cardRadius,
                padding: CGFloat = CDTheme.cardPadding,
                elevated: Bool = true) -> some View {
        modifier(CDCardModifier(radius: radius, padding: padding, elevated: elevated))
    }

    /// Inset field/segment background used inside cards.
    func cdInset(radius: CGFloat = CDTheme.innerRadius) -> some View {
        background(Color.white.opacity(0.44),
                   in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
            }
    }
}

/// Page background: cool canvas plus two soft brand glows.
struct CDCanvasBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [CDTheme.canvasTop, CDTheme.canvas, CDTheme.canvas],
                           startPoint: .top,
                           endPoint: .bottom)
            RadialGradient(colors: [CDTheme.accent.opacity(0.20), .clear],
                           center: .topLeading,
                           startRadius: 10,
                           endRadius: 460)
            RadialGradient(colors: [CDTheme.brandEnd.opacity(0.16), .clear],
                           center: .topTrailing,
                           startRadius: 10,
                           endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Grouped settings cards

/// Rounded container for a vertical list of rows. Rows are separated with a
/// leading-inset divider so the icon column keeps an unbroken rail.
struct CDGroupCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            VStack(spacing: 0) {
                content()
            }
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.52), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }
}

/// Row with a coloured icon tile, a title (and optional subtitle) and a
/// trailing accessory.
struct CDSettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var tint: Color = CDTheme.accent
    var titleColor: Color = .primary
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(colors: [tint, tint.opacity(0.72)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(titleColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }
}

extension CDSettingRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String? = nil,
         tint: Color = CDTheme.accent, titleColor: Color = .primary) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage,
                  tint: tint, titleColor: titleColor) { EmptyView() }
    }
}

/// Divider aligned with the row text column.
struct CDRowDivider: View {
    var inset: CGFloat = 54

    var body: some View {
        Divider()
            .padding(.leading, inset)
    }
}

/// Title above a grouped card, used for the segmented controls.
struct CDCardLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
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
            .background {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                            .fill(Color.white.opacity(0.20))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.52), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(CDTheme.danger, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.2))
                        .offset(x: 5, y: -4)
                } else if showsDot {
                    Circle()
                        .fill(CDTheme.danger)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.2))
                        .offset(x: 2, y: -2)
                }
            }
    }
}

/// Frosted segmented control that matches the rest of the card surfaces.
struct CDSegmented<Option: Hashable>: View {
    let items: [Option]
    let label: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = item
                    }
                } label: {
                    Text(label(item))
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.white.opacity(0.55))
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
                                    }
                                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.24),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
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
