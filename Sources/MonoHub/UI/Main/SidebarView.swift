import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Visão Geral"
    case modules = "Módulos"
    case monitor = "Monitor do Sistema"
    case ports = "Portas de Rede"
    case battery = "Saúde da Bateria"
    case displayControl = "Monitores Externos"
    case menuBar = "Barra de Menus"
    case aiQuota = "Cotas de IA"
    case notch = "Notch Dinâmico"
    case windowSwitcher = "Alternador de Janelas"
    case windowTiling = "Organização de Janelas"
    case screenshot = "Capturas de Tela"
    case mediaConverter = "Conversor de Mídia"
    case urlRouter = "Roteador de URLs"
    case snippets = "Expansão de Texto"
    case bluetoothQuickConnect = "Conexão Bluetooth"
    case audioControl = "Controle de Som"
    case uninstaller = "Desinstalador"
    case orphans = "Resíduos Órfãos"
    case cleaner = "Limpeza do Sistema"
    case purge = "Purga de Projetos"
    case env = "Ambientes de Dev"
    case dupes = "Arquivos Duplicados"
    case startup = "Itens de Inicialização"
    case disk = "Análise de Disco"
    case maintenance = "Otimização"
    case history = "Histórico"
    case settings = "Configurações"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return localized("Overview")
        case .modules: return localized("Modules")
        case .monitor: return localized("System Monitor")
        case .ports: return localized("Network Ports")
        case .battery: return localized("Battery Health")
        case .displayControl: return localized("External Displays")
        case .menuBar: return localized("Menu Bar")
        case .aiQuota: return localized("AI Quotas")
        case .notch: return localized("Dynamic Notch")
        case .windowSwitcher: return localized("Window Switcher")
        case .windowTiling: return localized("Window Tiling")
        case .screenshot: return localized("Screenshots")
        case .mediaConverter: return localized("Media Converter")
        case .urlRouter: return localized("URL Router")
        case .snippets: return localized("Text Snippets")
        case .bluetoothQuickConnect: return localized("Bluetooth & Audio")
        case .audioControl: return localized("Sound & Audio Control")
        case .uninstaller: return localized("Uninstaller")
        case .orphans: return localized("Orphaned Remnants")
        case .cleaner: return localized("System Clean")
        case .purge: return localized("Project Purge")
        case .env: return localized("Dev Environments")
        case .dupes: return localized("Duplicate Files")
        case .startup: return localized("Startup Items")
        case .disk: return localized("Disk Analysis")
        case .maintenance: return localized("Optimization")
        case .history: return localized("History")
        case .settings: return localized("Settings")
        }
    }

    var systemIcon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .modules: return "puzzlepiece.extension.fill"
        case .monitor: return "waveform.path.ecg"
        case .ports: return "network"
        case .battery: return "battery.100"
        case .displayControl: return "display"
        case .menuBar: return "menubar.rectangle"
        case .aiQuota: return AIQuotaStyle.symbol
        case .notch: return "rectangle.topthird.inset.filled"
        case .windowSwitcher: return "macwindow.on.rectangle"
        case .windowTiling: return "rectangle.split.2x2.fill"
        case .screenshot: return ScreenshotStyle.symbol
        case .mediaConverter: return "film.stack.fill"
        case .urlRouter: return "link.badge.plus"
        case .snippets: return "character.bubble.fill"
        case .bluetoothQuickConnect: return "antenna.radiowaves.left.and.right"
        case .audioControl: return "slider.horizontal.below.square.and.square.filled"
        case .uninstaller: return "xmark.app.fill"
        case .orphans: return "trash.fill"
        case .cleaner: return "sparkles"
        case .purge: return "shippingbox.fill"
        case .env: return "terminal.fill"
        case .dupes: return "doc.on.doc.fill"
        case .startup: return "power.circle.fill"
        case .disk: return "internaldrive.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .dashboard: return .blue
        case .modules: return .purple
        case .monitor: return .teal
        case .ports: return .cyan
        case .battery: return .green
        case .displayControl: return .blue
        case .menuBar: return .indigo
        case .aiQuota: return AIQuotaStyle.tint
        case .notch: return .pink
        case .windowSwitcher: return .purple
        case .windowTiling: return .indigo
        case .screenshot: return ScreenshotStyle.tint
        case .mediaConverter: return .teal
        case .urlRouter: return .blue
        case .snippets: return .mint
        case .bluetoothQuickConnect: return .blue
        case .audioControl: return .orange
        case .uninstaller: return .blue
        case .orphans: return .red
        case .cleaner: return .orange
        case .purge: return .brown
        case .env: return .blue
        case .dupes: return .purple
        case .startup: return .indigo
        case .disk: return .mint
        case .maintenance: return .yellow
        case .history: return .green
        case .settings: return .gray
        }
    }

    var feature: HubFeature? {
        HubFeature.allCases.first { $0.sidebarItems.contains(self) }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem
    private let features = FeatureManager.shared

    init(selection: Binding<SidebarItem>) {
        self._selection = selection
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                row(.dashboard)
                row(.modules)
            }

            section(localized("Monitoring"), items: [.monitor, .ports, .battery, .displayControl, .menuBar, .aiQuota])
            section(localized("Productivity"), items: [.audioControl, .bluetoothQuickConnect, .urlRouter, .snippets, .notch, .windowSwitcher, .windowTiling, .screenshot, .mediaConverter])
            section(localized("Cleanup"), items: [.uninstaller, .orphans, .cleaner, .purge, .env, .dupes, .disk])
            section(localized("Maintenance"), items: [.startup, .maintenance, .history])

            Section {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppInfo.name)
    }

    @ViewBuilder
    private func section(_ title: String, items: [SidebarItem]) -> some View {
        let visible = items.filter(features.isSidebarItemAvailable)
        if !visible.isEmpty {
            Section(title) {
                ForEach(visible) { row($0) }
            }
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label {
            Text(item.title)
                .lineLimit(1)
        } icon: {
            HubIcon(systemName: item.systemIcon, tint: item.badgeColor, size: 20)
        }
        .tag(item)
    }
}
