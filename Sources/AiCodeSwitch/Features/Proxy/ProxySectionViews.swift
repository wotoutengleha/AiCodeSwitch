import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ApiProxySectionView: View {
    @ObservedObject var model: ProxyPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.apiProxySectionExpanded {
                proxyHeroContent
                proxyDetailCards
            } else {
                collapsedSummaryPills
            }
        }
        .padding(16)
        .cardSurface(cornerRadius: LayoutRules.cardRadius)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(L10n.tr("proxy.section.api_proxy"))
                .font(.headline)

            Spacer(minLength: 0)

            CollapseChevronButton(isExpanded: model.apiProxySectionExpanded) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.apiProxySectionExpanded.toggle()
                }
            }
        }
    }

    private var collapsedSummaryPills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ProxyStatusPill(isRunning: model.proxyStatus.running)
                ProxyMetricPill(L10n.tr("proxy.port_line_format", model.proxyStatus.port.map(String.init) ?? "--"))
                ProxyMetricPill(L10n.tr("proxy.available_accounts_format", String(model.proxyStatus.availableAccounts)))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProxyStatusPill(isRunning: model.proxyStatus.running)
                    ProxyMetricPill(L10n.tr("proxy.port_line_format", model.proxyStatus.port.map(String.init) ?? "--"))
                }
                ProxyMetricPill(L10n.tr("proxy.available_accounts_format", String(model.proxyStatus.availableAccounts)))
            }
        }
    }

    private var proxyHeroContent: some View {
        VStack(spacing: 12) {
            expandedSummaryPills

            HStack(spacing: 10) {
                TextField("8787", text: $model.preferredPortText)
                    .frostedCapsuleInput()
                    .frame(width: LayoutRules.proxyHeroPortFieldWidth)

                Button("proxy.action.refresh_status") {
                    Task { await model.refreshStatus() }
                }
                .liquidGlassActionButtonStyle()
                .disabled(model.loading)

                if model.proxyStatus.running {
                    Button("proxy.action.stop_api_proxy", role: .destructive) {
                        Task { await model.stopProxy() }
                    }
                    .liquidGlassActionButtonStyle(prominent: true)
                    .disabled(model.loading)
                } else {
                    Button("proxy.action.start_api_proxy") {
                        Task { await model.startProxy() }
                    }
                    .liquidGlassActionButtonStyle(prominent: true)
                    .disabled(model.loading)
                }
            }

            HStack {
                Text("proxy.start_on_launch")
                    .font(.subheadline)
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { model.autoStartProxy },
                    set: { value in
                        Task { await model.setAutoStartProxy(value) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var expandedSummaryPills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ProxyStatusPill(isRunning: model.proxyStatus.running)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ProxyMetricPill(L10n.tr("proxy.port_line_format", model.proxyStatus.port.map(String.init) ?? "--"))
                    ProxyMetricPill(L10n.tr("proxy.available_accounts_format", String(model.proxyStatus.availableAccounts)))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ProxyStatusPill(isRunning: model.proxyStatus.running)
                HStack(spacing: 8) {
                    ProxyMetricPill(L10n.tr("proxy.port_line_format", model.proxyStatus.port.map(String.init) ?? "--"))
                    ProxyMetricPill(L10n.tr("proxy.available_accounts_format", String(model.proxyStatus.availableAccounts)))
                }
            }
        }
    }

    private var proxyDetailCards: some View {
        LazyVStack(spacing: LayoutRules.proxyDetailCardSpacing) {
            ProxyCopyableValueCard(
                title: L10n.tr("proxy.detail.base_url"),
                value: model.proxyStatus.baseURL ?? L10n.tr("proxy.value.generated_after_start"),
                canCopy: model.proxyStatus.baseURL != nil
            )

            ProxyCopyableValueCard(
                title: L10n.tr("proxy.detail.api_key"),
                value: model.proxyStatus.apiKey ?? L10n.tr("proxy.value.generated_after_first_start"),
                canCopy: model.proxyStatus.apiKey != nil
            ) {
                Button("common.refresh") {
                    Task { await model.refreshAPIKey() }
                }
                .liquidGlassActionButtonStyle()
                .disabled(model.loading)
            }

            ProxyInfoCard(
                title: L10n.tr("proxy.detail.active_routed_account"),
                headline: model.proxyStatus.activeAccountLabel ?? L10n.tr("proxy.info.no_request_matched"),
                detailText: model.proxyStatus.activeAccountID ?? L10n.tr("proxy.info.active_account_hint")
            )
            ProxyInfoCard(
                title: L10n.tr("proxy.detail.last_error"),
                headline: model.proxyStatus.lastError ?? L10n.tr("common.none"),
                detailText: ""
            )
        }
    }
}

struct RemoteServersSectionView: View {
    @ObservedObject var model: ProxyPageModel

    var body: some View {
        SectionCard(
            title: L10n.tr("proxy.section.remote_servers"),
            headerTrailing: {
                Button("proxy.action.add_server") {
                    Task { await model.addRemoteServer() }
                }
                .liquidGlassActionButtonStyle(prominent: true)
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("proxy.remote.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.remoteServers.isEmpty {
                    EmptyStateView(
                        title: L10n.tr("proxy.remote.empty.title"),
                        message: L10n.tr("proxy.remote.empty.message")
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(model.remoteServers) { server in
                            RemoteServerCardView(
                                server: server,
                                status: model.remoteStatuses[server.id],
                                logs: model.remoteLogs[server.id],
                                activeAction: model.remoteActions[server.id],
                                onSave: { updated in Task { await model.saveRemoteServer(updated) } },
                                onRemove: { id in Task { await model.removeRemoteServer(id: id) } },
                                onRefresh: { Task { await model.refreshRemote(server: server) } },
                                onDeploy: { Task { await model.deployRemote(server: server) } },
                                onStart: { Task { await model.startRemote(server: server) } },
                                onStop: { Task { await model.stopRemote(server: server) } },
                                onLogs: { Task { await model.readRemoteLogs(server: server) } }
                            )
                        }
                    }
                }
            }
        }
    }
}

struct ProxyInfoOnlySection: View {
    let title: String
    let message: String

    var body: some View {
        SectionCard(title: title) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProxyStatusPill: View {
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? Color.mint : Color.gray)
                .frame(width: 7, height: 7)
            Text(isRunning ? L10n.tr("proxy.status.running") : L10n.tr("proxy.status.stopped"))
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frostedCapsuleSurface()
    }
}

private struct ProxyMetricPill: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frostedCapsuleSurface()
    }
}

private struct ProxyCopyableValueCard<Trailing: View>: View {
    let title: String
    let value: String
    let canCopy: Bool
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        value: String,
        canCopy: Bool,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.value = value
        self.canCopy = canCopy
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                trailing
                Button("common.copy") {
                    PlatformClipboard.copy(canCopy ? value : nil)
                }
                .liquidGlassActionButtonStyle()
                .disabled(!canCopy)
            }
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .cardSurface(cornerRadius: 12)
    }
}

private struct ProxyInfoCard: View {
    let title: String
    let headline: String
    let detailText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(headline)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            if !detailText.isEmpty {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .cardSurface(cornerRadius: 12)
    }
}

private struct RemoteServerCardView: View {
    let server: RemoteServerConfig
    let status: RemoteProxyStatus?
    let logs: String?
    let activeAction: RemoteServerAction?
    let onSave: (RemoteServerConfig) -> Void
    let onRemove: (String) -> Void
    let onRefresh: () -> Void
    let onDeploy: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onLogs: () -> Void

    @State private var draft: RemoteServerConfig
    @State private var isExpanded: Bool

    init(
        server: RemoteServerConfig,
        status: RemoteProxyStatus?,
        logs: String?,
        activeAction: RemoteServerAction?,
        onSave: @escaping (RemoteServerConfig) -> Void,
        onRemove: @escaping (String) -> Void,
        onRefresh: @escaping () -> Void,
        onDeploy: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onLogs: @escaping () -> Void
    ) {
        self.server = server
        self.status = status
        self.logs = logs
        self.activeAction = activeAction
        self.onSave = onSave
        self.onRemove = onRemove
        self.onRefresh = onRefresh
        self.onDeploy = onDeploy
        self.onStart = onStart
        self.onStop = onStop
        self.onLogs = onLogs
        _draft = State(initialValue: server)
        _isExpanded = State(initialValue: RemoteServerConfiguration.isPlaceholderDraft(server))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if isExpanded {
                fieldGrid
                authSection
                actionBar
                statusGrid
                detailGrid
                logsSection
                errorSection
            }
        }
        .padding(10)
        .cardSurface(cornerRadius: 10)
        .onChange(of: server) { _, newValue in
            draft = newValue
            if RemoteServerConfiguration.isPlaceholderDraft(draft) {
                isExpanded = true
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.label.isEmpty ? RemoteServerConfiguration.defaultLabel : draft.label)
                    .font(.headline)
                if !isExpanded {
                    Text("\(draft.sshUser)@\(draft.host):\(draft.listenPort)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            CollapseChevronButton(isExpanded: isExpanded) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            Text(RemoteServerConfiguration.statusLabel(status))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frostedCapsuleSurface(
                    prominent: status?.running == true,
                    tint: status?.running == true ? .green : .gray
                )
        }
    }

    private var fieldGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: LayoutRules.proxyRemoteFieldMinWidth), spacing: 8)],
            spacing: 8
        ) {
            labeledField(title: "Name") {
                TextField("tokyo-01", text: $draft.label)
                    .frostedRoundedInput()
            }
            labeledField(title: "Host") {
                TextField("1.2.3.4", text: $draft.host)
                    .frostedRoundedInput()
            }
            labeledField(title: "SSH Port") {
                TextField("22", value: $draft.sshPort, format: .number.grouping(.never))
                    .frostedRoundedInput()
            }
            labeledField(title: "SSH User") {
                TextField(RemoteServerConfiguration.defaultSSHUser, text: $draft.sshUser)
                    .frostedRoundedInput()
            }
            labeledField(title: "Deploy Dir") {
                TextField(RemoteServerConfiguration.defaultRemoteDir, text: $draft.remoteDir)
                    .frostedRoundedInput()
            }
            labeledField(title: "Proxy Port") {
                TextField(
                    String(RemoteServerConfiguration.defaultProxyPort),
                    value: $draft.listenPort,
                    format: .number.grouping(.never)
                )
                .frostedRoundedInput()
            }
        }
    }

    private var authSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("SSH Auth", selection: $draft.authMode) {
                Text("Path").tag("keyPath")
                Text("Private key").tag("keyContent")
                Text("Password").tag("password")
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)

            switch draft.authMode {
            case "keyContent":
                TextEditor(text: Binding(
                    get: { draft.privateKey ?? "" },
                    set: { draft.privateKey = $0 }
                ))
                .font(.caption.monospaced())
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frostedRoundedSurface(cornerRadius: 8)
            case "password":
                SecureField("SSH password", text: Binding(
                    get: { draft.password ?? "" },
                    set: { draft.password = $0 }
                ))
                .frostedRoundedInput()
            default:
                HStack(spacing: 8) {
                    TextField("~/.ssh/id_ed25519", text: Binding(
                        get: { draft.identityFile ?? "" },
                        set: { draft.identityFile = $0 }
                    ))
                    .frostedRoundedInput()
                    #if canImport(AppKit)
                    Button {
                        if let path = chooseIdentityFilePath() {
                            draft.identityFile = path
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .liquidGlassActionButtonStyle()
                    .help("Choose key file")
                    #endif
                }
            }
        }
    }

    private var actionBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                remoteActionButton("common.save", kind: .save) { onSave(draft) }
                remoteActionButton("common.remove", role: .destructive, kind: .remove) { onRemove(server.id) }
                remoteActionButton("common.deploy", kind: .deploy, action: onDeploy)
                remoteActionButton("common.refresh", kind: .refresh, action: onRefresh)
                if status?.running == true {
                    remoteActionButton("common.stop", role: .destructive, kind: .stop, action: onStop)
                } else {
                    remoteActionButton("common.start", kind: .start, action: onStart)
                }
                remoteActionButton("common.logs", kind: .logs, action: onLogs)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var statusGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: LayoutRules.proxyRemoteMetricMinWidth), spacing: 8)],
            spacing: 8
        ) {
            remoteMetric(title: "Installed", value: RemoteServerConfiguration.boolText(status?.installed))
            remoteMetric(title: "Systemd", value: RemoteServerConfiguration.boolText(status?.serviceInstalled))
            remoteMetric(title: "Enabled on boot", value: RemoteServerConfiguration.boolText(status?.enabled))
            remoteMetric(title: "Running", value: RemoteServerConfiguration.boolText(status?.running))
            remoteMetric(title: "PID", value: status?.pid.map(String.init) ?? "--")
        }
    }

    private var detailGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: LayoutRules.proxyRemoteDetailMinWidth), spacing: 8)],
            spacing: 8
        ) {
            remoteDetailCard(title: "Remote Base URL", value: status?.baseURL ?? "--", canCopy: status?.baseURL != nil)
            remoteDetailCard(
                title: "Remote API key",
                value: status?.apiKey ?? "Generated after first start",
                canCopy: status?.apiKey != nil
            )
            remoteDetailCard(
                title: "Service name",
                value: status?.serviceName ?? "Unknown",
                canCopy: status?.serviceName != nil
            )
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Remote logs")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("common.copy") {
                    PlatformClipboard.copy(logs)
                }
                .liquidGlassActionButtonStyle()
                .disabled((logs ?? "").isEmpty)
            }

            ScrollView(.vertical) {
                Text(logs?.isEmpty == false ? logs! : "Logs have not been loaded yet")
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(height: LayoutRules.proxyRemoteLogsHeight)
            .cardSurface(cornerRadius: 8)
            .scrollIndicators(.visible)
        }
    }

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Remote error")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(status?.lastError ?? L10n.tr("common.none"))
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .cardSurface(cornerRadius: 8)
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func remoteMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: LayoutRules.proxyRemoteMetricHeight, alignment: .topLeading)
        .padding(8)
        .cardSurface(cornerRadius: 10)
    }

    private func remoteDetailCard(title: String, value: String, canCopy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("common.copy") {
                    PlatformClipboard.copy(canCopy ? value : nil)
                }
                .liquidGlassActionButtonStyle()
                .disabled(!canCopy)
            }
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .cardSurface(cornerRadius: 10)
    }

    @ViewBuilder
    private func remoteActionButton(
        _ titleKey: LocalizedStringKey,
        role: ButtonRole? = nil,
        kind: RemoteServerAction,
        action: @escaping () -> Void
    ) -> some View {
        let isCurrent = activeAction == kind
        Button(role: role, action: action) {
            if isCurrent {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(titleKey)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: LayoutRules.proxyRemoteActionMinWidth)
        .liquidGlassActionButtonStyle()
        .disabled(activeAction != nil)
    }

    private func chooseIdentityFilePath() -> String? {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Select SSH key file"
        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.url?.path
        #else
        return nil
        #endif
    }
}
