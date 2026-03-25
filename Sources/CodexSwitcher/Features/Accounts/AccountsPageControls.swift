import SwiftUI

enum SwitcherPalette {
    static func primaryText(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(red: 0.95, green: 0.95, blue: 0.97)
        default:
            return Color(red: 0.13, green: 0.13, blue: 0.15)
        }
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(red: 0.69, green: 0.70, blue: 0.74)
        default:
            return Color(red: 0.47, green: 0.47, blue: 0.50)
        }
    }

    static func panelBackground(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(red: 0.11, green: 0.12, blue: 0.14)
        default:
            return Color.white
        }
    }

    static func panelBorder(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.08)
        default:
            return Color.white.opacity(0.60)
        }
    }

    static func divider(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.10)
        default:
            return Color.black.opacity(0.10)
        }
    }

    static func subtleFill(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.05)
        default:
            return Color.black.opacity(0.028)
        }
    }

    static func subduedFill(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.08)
        default:
            return Color.black.opacity(0.04)
        }
    }

    static func buttonBorder(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.14)
        default:
            return Color.black.opacity(0.12)
        }
    }

    static func progressTrack(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    static func compactProgressTrack(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.10)
        default:
            return Color.black.opacity(0.06)
        }
    }

    static func windowBackground(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(red: 0.10, green: 0.11, blue: 0.13)
        default:
            return Color(red: 0.80, green: 0.82, blue: 0.86)
        }
    }

    static func windowGradient(for scheme: ColorScheme) -> LinearGradient {
        switch scheme {
        case .dark:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.white.opacity(0.015),
                    Color.black.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.30),
                    Color.white.opacity(0.12),
                    Color.black.opacity(0.03)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct UsageProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: Double
    var fillColor: Color = Color(red: 0.22, green: 0.69, blue: 0.78)
    var trackColor: Color? = nil
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width * progress)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor ?? SwitcherPalette.progressTrack(for: colorScheme))
                Capsule()
                    .fill(fillColor)
                    .frame(width: width)
            }
        }
        .frame(height: height)
    }
}

struct SwitcherMenuActionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        let resolvedTint = tint ?? SwitcherPalette.primaryText(for: colorScheme)
        Button(action: action) {
            HStack(spacing: LayoutRules.menuRowSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: LayoutRules.menuIconWidth, alignment: .leading)
                    .foregroundStyle(resolvedTint.opacity(0.85))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(resolvedTint)
                Spacer(minLength: 0)
            }
            .frame(height: LayoutRules.menuRowHeight)
        }
        .buttonStyle(.plain)
    }
}
