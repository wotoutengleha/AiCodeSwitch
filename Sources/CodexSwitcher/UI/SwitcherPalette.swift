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
            return Color(red: 0.11, green: 0.12, blue: 0.14).opacity(0.96)
        default:
            return Color.white.opacity(0.92)
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
