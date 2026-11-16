import SwiftUI

struct ProviderQuotaCard: View {
    let status: ProviderStatus
    var isCompact = false
    var onSelect: (() -> Void)?

    @State private var didCopyCommand = false
    @State private var isRequestingAccess = false
    @State private var isHovered = false

    private var peak: Double { status.primaryUsagePercent ?? status.peakUsagePercent }
    private var isHighUsage: Bool { peak >= 80.0 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                header

                if status.hasReading {
                    readings(now: context.date)
                }

                if showsDiagnostics {
                    diagnostics
                } else if !status.hasReading {
                    Text(status.actionSuggestion ?? localized("Waiting for first reading…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !isCompact {
                    footer(now: context.date)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(onSelect != nil && isHovered ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if isHighUsage {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(UsageColor.forRatio(peak / 100, base: .clear).opacity(0.5), lineWidth: 1)
                }
            }
        }
        .contentShape(.rect(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            guard onSelect != nil else { return }
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .onTapGesture {
            onSelect?()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(onSelect == nil ? [] : .isButton)
        .accessibilityAction(named: localized("Show details")) {
            onSelect?()
        }
    }

    private var showsDiagnostics: Bool {
        guard status.errorMessage != nil || status.state.isError else { return false }
        guard status.hasReading, isCompact else { return true }
        if case .expired = status.state { return true }
        return false
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandTile(provider: status.provider, size: isCompact ? 28 : 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(status.provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            stateBadge

            if onSelect != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
                    .offset(x: isHovered ? 2 : 0)
                    .accessibilityHidden(true)
            }
        }
    }

    private var subtitle: String {
        let cleanPlan = status.planName.contains("@") ? nil : status.planName
        let cleanDetail = status.accountDetail.flatMap { $0.contains("@") ? nil : $0 }
        return [cleanPlan, cleanDetail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var stateBadge: some View {
        if let headline = status.headlineValue, status.hasReading {
            Text(headline)
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(status.windows.isEmpty ? Color.primary : UsageColor.forRatio(peak / 100, base: .primary))
                .fixedSize()
                .layoutPriority(2)
                .contentTransition(.numericText(value: peak))
                .animation(.snappy, value: headline)
                .accessibilityLabel(status.balance != nil && status.windows.isEmpty ? String(format: localized("Balance %@"), headline) : String(format: localized("%@ used"), headline))
        } else {
            Label(status.state.statusBadgeTitle, systemImage: status.state.statusSymbol)
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .foregroundStyle(status.state.statusBadgeColor)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @State private var claudeSessions: [ClaudeContextSession] = []
    @State private var antigravityModels: [AntigravityModelInfo] = []

    @ViewBuilder
    private func readings(now: Date) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
            ForEach(status.windows) { window in
                QuotaUsageBar(
                    title: window.name,
                    percent: window.effectiveUsedPercent,
                    detail: isCompact ? compactReset(window, now: now) : window.formattedReset(now: now),
                    pacing: window.pacing,
                    accentColor: status.provider.accentColor,
                    isCompact: isCompact,
                    subtitle: window.includedModels
                )
            }
            if let balance = status.balance {
                balanceView(balance)
            }
            if !isCompact, !status.bankedCredits.isEmpty {
                bankedCreditsView
            }
            if status.provider == .claude, !claudeSessions.isEmpty {
                claudeContextView
            }
            if !isCompact, status.provider == .antigravity {
                antigravityModelsView
            }
        }
        .task(id: status.lastUpdated) {
            if status.provider == .claude {
                claudeSessions = await ClaudeContextService.shared.fetchRecentSessions(limit: isCompact ? 1 : 2)
            } else if status.provider == .antigravity && !isCompact {
                antigravityModels = await AntigravityUsageService.shared.fetchAvailableModels()
            }
        }
    }

    private var bankedCreditsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(status.bankedCredits) { credit in
                HStack(spacing: 6) {
                    Image(systemName: credit.isExpiringSoon ? "clock.badge.exclamationmark.fill" : "creditcard.fill")
                        .foregroundStyle(credit.isExpiringSoon ? .orange : .secondary)
                    Text(credit.label)
                        .font(.caption)
                    Spacer()
                    if let expiresAt = credit.expiresAt {
                        Text(credit.isExpiringSoon ? localized("Expiring soon") : expiresAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(credit.isExpiringSoon ? .orange : .secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var claudeContextView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isCompact {
                HStack {
                    Label(localized("Claude Code Context"), systemImage: "text.book.closed.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            ForEach(claudeSessions.prefix(isCompact ? 1 : 2)) { session in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if isCompact {
                            Image(systemName: "text.book.closed.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        Text(session.projectName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text("(\(session.modelName))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(session.formattedTokens)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(session.contextPercent >= 80 ? .orange : .secondary)
                    }
                    if !isCompact {
                        UsageBar(
                            ratio: session.contextPercent / 100.0,
                            tint: .purple,
                            height: 4
                        )
                    }
                }
                .padding(.vertical, isCompact ? 0 : 2)
            }
        }
        .padding(.top, isCompact ? 2 : 4)
    }

    private var antigravityModelsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(localized("Available Models in Antigravity"), systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            let models = antigravityModels.isEmpty ? AntigravityUsageService.defaultModels : antigravityModels

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
                ForEach(models) { model in
                    HStack(spacing: 5) {
                        Image(systemName: model.isNew ? "flame.fill" : (model.family == "Claude" ? "brain.head.profile" : "cpu.fill"))
                            .font(.system(size: 10))
                            .foregroundStyle(model.isNew ? .orange : (model.family == "Claude" ? .purple : .cyan))

                        Text(model.displayName)
                            .font(.caption.weight(model.isNew ? .semibold : .regular))
                            .lineLimit(1)

                        if model.isNew {
                            Text(localized("NEW"))
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.2)))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .padding(.top, 4)
    }

    private func compactReset(_ window: QuotaWindow, now: Date) -> String? {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        let remaining = Int(resetsAt.timeIntervalSince(now))
        let hours = remaining / 3600
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        return hours > 0 ? "\(hours)h \((remaining % 3600) / 60)m" : "\(max(1, remaining / 60))m"
    }

    private func balanceView(_ balance: ProviderBalance) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(localized("Available balance"))
                    .font(.callout)
                Spacer()
                Text(balance.formatted)
                    .font(.callout.weight(.semibold).monospacedDigit())
            }
            if !isCompact {
                ForEach(balance.lines, id: \.label) { line in
                    HStack {
                        Text(line.label)
                        Spacer()
                        Text(balance.formatted(line.amount)).monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func footer(now: Date) -> some View {
        HStack(spacing: 6) {
            Label(status.authSource, systemImage: sourceSymbol)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)

            if let lastUpdated = status.lastUpdated {
                Text("·")
                Text(lastUpdated, format: .relative(presentation: .named))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let command = status.provider.terminalCommand {
                Button {
                    openTerminal(with: command)
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help(String(format: localized("Copy `%@` and open Terminal"), command))
                .accessibilityLabel(localized("Open Terminal"))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var sourceSymbol: String {
        let source = status.authSource.lowercased()
        if source.contains("keychain") { return "key.fill" }
        if source.contains("rpc") { return "network" }
        if source.contains("cli") || source.contains(".json") { return "terminal" }
        if source.contains("offline") || source.contains("missing") { return "bolt.horizontal.circle" }
        return "lock.fill"
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: status.state.statusSymbol)
                    .foregroundStyle(status.state.statusBadgeColor)
                    .imageScale(.medium)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.errorMessage ?? status.state.statusBadgeTitle)
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if let suggestion = status.actionSuggestion {
                        Text(LocalizedStringKey(suggestion))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            actionRow
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.state.statusBadgeColor.opacity(0.1), in: .rect(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var actionRow: some View {
        let command = suggestedCommand
        let showsCopy = command != nil && status.actionSuggestion?.contains("`") == true

        if showsCopy || !status.hasReading || status.provider.usesAPIKey {
            HStack(spacing: 8) {
                if showsCopy, let command {
                    Button {
                        copy(command)
                    } label: {
                        Label(didCopyCommand ? localized("Copied") : String(format: localized("Copy %@"), command), systemImage: didCopyCommand ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.bordered)
                }

                if !status.hasReading {
                    Button {
                        AIQuotaStatusItemController.shared.openSettings()
                    } label: {
                        Label(localized("Settings"), systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                } else if status.provider.usesAPIKey {
                    Text(localized("Settings › API Keys"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
        }
    }

    private var suggestedCommand: String? {
        if let suggestion = status.actionSuggestion,
           let start = suggestion.firstIndex(of: "`"),
           let end = suggestion[suggestion.index(after: start)...].firstIndex(of: "`") {
            return String(suggestion[suggestion.index(after: start)..<end])
        }
        return status.provider.loginCommand
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        didCopyCommand = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyCommand = false
        }
    }

    private func openTerminal(with command: String) {
        copy(command)
        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminalURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
