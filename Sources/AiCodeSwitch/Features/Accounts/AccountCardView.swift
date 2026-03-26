import SwiftUI

struct AccountCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let account: AccountSummary
    let showEmails: Bool
    let switching: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    private var presentation: SwitchAccountRowPresentation {
        AccountCardPresentation.row(account: account, showEmails: showEmails)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center, spacing: 8) {
                    Text(presentation.emailText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SwitcherPalette.primaryText(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                        .allowsTightening(true)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Text(presentation.planText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(presentation.isExpired ? .red : SwitcherPalette.secondaryText(for: colorScheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(SwitcherPalette.subduedFill(for: colorScheme), in: Capsule())

                        if switching {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                SwitcherMetricView(
                    title: presentation.fiveHourLabelText,
                    percentText: presentation.fiveHourPercentText,
                    progress: presentation.fiveHourProgress,
                    fillColor: Color(red: 0.98, green: 0.28, blue: 0.46)
                )

                SwitcherMetricView(
                    title: presentation.weekLabelText,
                    percentText: presentation.weekPercentText,
                    progress: presentation.weekProgress,
                    fillColor: Color(red: 0.20, green: 0.79, blue: 0.39)
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SwitcherPalette.subtleFill(for: colorScheme))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label(L10n.tr("switcher.action.delete_account"), systemImage: "trash")
            }
            .disabled(switching)
        }
    }
}

private struct SwitcherMetricView: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let percentText: String
    let progress: Double
    let fillColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(fillColor)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
                Spacer(minLength: 0)
                Text(percentText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(fillColor)
            }

            UsageProgressBar(
                progress: progress,
                fillColor: fillColor,
                trackColor: SwitcherPalette.compactProgressTrack(for: colorScheme),
                height: 5
            )
        }
    }
}
