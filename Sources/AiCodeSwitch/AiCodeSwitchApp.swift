import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct AiCodeSwitchApp: App {
    private let container: AppContainer
    @StateObject private var accountsModel: AccountsPageModel
    #if canImport(AppKit)
    private let menuBarIconLoader = MenuBarIconLoader()
    #endif

    init() {
        let container = AppContainer.liveOrCrash()
        self.container = container
        _accountsModel = StateObject(wrappedValue: container.accountsModel)
    }

    var body: some Scene {
        MenuBarExtra {
            RootScene(container: container)
        } label: {
            HStack(spacing: 4) {
                menuBarIcon
                if let remainingText = menuBarRemainingText {
                    Text(remainingText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: Image {
        #if canImport(AppKit)
        if let customIcon = menuBarIconLoader.loadOpenAITemplateIcon() {
            return Image(nsImage: customIcon)
        }
        if let icon = makeMenuBarSymbolImage() {
            return Image(nsImage: icon)
        }
        #endif
        return Image(systemName: accountsModel.hasQuotaWarning ? "exclamationmark.circle.fill" : "arrow.left.arrow.right.circle")
    }

    private var menuBarRemainingText: String? {
        guard let fiveHourWindow = accountsModel.currentAccount?.usage?.fiveHour else {
            return nil
        }
        let remainingPercent = max(0, min(100, Int((100 - fiveHourWindow.usedPercent).rounded())))
        return "\(remainingPercent)%"
    }

    #if canImport(AppKit)
    private func makeMenuBarSymbolImage() -> NSImage? {
        let symbolName = accountsModel.hasQuotaWarning ? "exclamationmark.circle.fill" : "arrow.left.arrow.right.circle"
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AiCodeSwitch") else {
            return nil
        }
        image.isTemplate = true
        return image
    }
    #endif
}

#if canImport(AppKit)
private struct MenuBarIconLoader {
    func loadOpenAITemplateIcon() -> NSImage? {
        resourceCandidates()
            .lazy
            .compactMap { NSImage(contentsOfFile: $0) }
            .first { image in
                image.isTemplate = true
                image.size = NSSize(width: 16, height: 16)
                return true
            }
    }

    private func resourceCandidates() -> [String] {
        let names = ["openai-menubar-template", "openai-menubar", "openai"]
        let extensions = ["pdf", "png"]
        let bundlePaths = names.flatMap { name in
            extensions.compactMap { ext in
                Bundle.main.path(forResource: name, ofType: ext)
            }
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")

        let sourcePaths = names.flatMap { name in
            extensions.map { ext in
                sourceRoot.appendingPathComponent("\(name).\(ext)").path
            }
        }

        return bundlePaths + sourcePaths
    }
}
#endif
