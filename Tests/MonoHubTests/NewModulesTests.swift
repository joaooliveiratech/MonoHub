import Foundation
import Testing
@testable import MonoHub

@MainActor
@Suite("Novas Funcionalidades: MonoBattery, MonoPorts, MonoStartup, MonoDupes, MonoEnv")
struct NewModulesTests {

    // MARK: - MonoBattery Tests

    @Test("MonoBattery: Cálculo de Saúde, Condição e Degradação")
    func batteryHealthCalculations() {
        var data = BatteryData()
        data.hasBattery = true
        data.designCapacityMah = 5000
        data.fullChargeCapacityMah = 4800
        data.cycleCount = 120
        data.designCycleCount = 1000

        #expect(data.healthPercent == 96)
        #expect(data.conditionDescription == "Normal")

        // Degraded scenario
        data.fullChargeCapacityMah = 3800
        #expect(data.healthPercent == 76)
        #expect(data.conditionDescription == localized("Service Recommended"))
    }

    @Test("MonoBattery: Gravação de Amostras e Limite de Histórico")
    func batteryHealthSampling() {
        let engine = BatteryHealthEngine.shared
        var battery = BatteryData()
        battery.hasBattery = true
        battery.level = 0.75
        battery.batteryPowerWatts = 15.0
        battery.temperatureCelsius = 31.5

        for i in 1...70 {
            battery.level = Double(i) / 100.0
            engine.recordSample(from: battery)
        }

        #expect(engine.history.count <= 60)
        #expect(engine.history.last?.levelPercent == 70)
    }

    // MARK: - MonoPorts Tests

    @Test("MonoPorts: Parser de Sockets do lsof (LISTEN, ESTABLISHED, UDP)")
    func portsParsing() {
        let sampleLsofOutput = """
        COMMAND     PID         USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        rapportd    971 devuser   12u  IPv4    0xfce6f5790cd01      0t0  TCP *:56156 (LISTEN)
        com.docke 21614 devuser  178u  IPv6 0xb273b147d9b42107      0t0  TCP *:8080 (LISTEN)
        Antigravi 23951 devuser   32u  IPv4 0x290adcfa01a1ec9d      0t0  TCP 127.0.0.1:3000 (LISTEN)
        node      12345 devuser   40u  IPv4 0x1111111111111111      0t0  TCP 192.168.1.10:54321->142.250.190.46:443 (ESTABLISHED)
        mDNSRespo   105 _mdnsresponder 10u  IPv4 0x2222222222222222      0t0  UDP *:5353
        """

        let parsed = PortsEngine.parseLsofOutput(sampleLsofOutput)
        #expect(parsed.count == 5)

        // Web port detection
        let port3000 = parsed.first(where: { $0.port == 3000 })
        #expect(port3000 != nil)
        #expect(port3000?.isListening == true)
        #expect(port3000?.isWebPort == true)
        #expect(port3000?.webURL?.absoluteString == "http://127.0.0.1:3000")

        let port8080 = parsed.first(where: { $0.port == 8080 })
        #expect(port8080 != nil)
        #expect(port8080?.isWebPort == true)

        let established = parsed.first(where: { $0.state == "ESTABLISHED" })
        #expect(established != nil)
        #expect(established?.port == 54321)
        #expect(established?.remoteAddress?.contains("443") == true)

        let udp = parsed.first(where: { $0.state == "UDP" })
        #expect(udp != nil)
        #expect(udp?.port == 5353)
    }

    @Test("MonoPorts: Cálculo de Banda em Tempo Real por Processo (Darwin Sockets)")
    func processBandwidthDeltaComputation() {
        let prev: [pid_t: (rx: UInt64, tx: UInt64)] = [
            100: (rx: 1_000_000, tx: 500_000),
            200: (rx: 10_000, tx: 20_000),
            300: (rx: 50_000, tx: 50_000)
        ]

        let curr: [pid_t: (name: String, rx: UInt64, tx: UInt64, sockets: Int)] = [
            100: (name: "Helium Helper", rx: 2_048_000, tx: 551_200, sockets: 4),  // +1,048,000 rx, +51,200 tx in 2s
            200: (name: "Slack Helper", rx: 210_000, tx: 30_000, sockets: 2),     // +200,000 rx, +10,000 tx in 2s
            300: (name: "rapportd", rx: 50_000, tx: 50_000, sockets: 1),          // idle (0 rx, 0 tx)
            400: (name: "curl", rx: 500_000, tx: 10_000, sockets: 1)              // brand new process (no prev) -> 0 rate
        ]

        let snapshot = ProcessBandwidthEngine.computeSnapshot(
            previous: prev,
            current: curr,
            elapsedSeconds: 2.0,
            timestamp: 123456789
        )

        // Process 100: rxRate = 1,048,000 / 2 = 524,000 B/s; txRate = 51,200 / 2 = 25,600 B/s
        let p100 = snapshot.processes[100]
        #expect(p100 != nil)
        #expect(p100?.downloadBytesPerSec == 524_000)
        #expect(p100?.uploadBytesPerSec == 25_600)
        #expect(p100?.totalDownloaded == 2_048_000)
        #expect(p100?.totalUploaded == 551_200)
        #expect(p100?.hasTraffic == true)
        #expect(p100?.totalSpeed == 549_600)

        // Process 200: rxRate = 200,000 / 2 = 100,000 B/s; txRate = 10,000 / 2 = 5,000 B/s
        let p200 = snapshot.processes[200]
        #expect(p200 != nil)
        #expect(p200?.downloadBytesPerSec == 100_000)
        #expect(p200?.uploadBytesPerSec == 5_000)

        // Process 300: idle
        let p300 = snapshot.processes[300]
        #expect(p300 != nil)
        #expect(p300?.downloadBytesPerSec == 0)
        #expect(p300?.uploadBytesPerSec == 0)
        #expect(p300?.hasTraffic == false)

        // Top consumer verification
        #expect(snapshot.topConsumerPID == 100)
        #expect(snapshot.topConsumerName == "Helium Helper")
        #expect(snapshot.topConsumerSpeed == 549_600)

        // Total speed verification
        #expect(snapshot.totalDownloadSpeed == 624_000)
        #expect(snapshot.totalUploadSpeed == 30_600)

        // Zero elapsed time edge case
        let emptySnapshot = ProcessBandwidthEngine.computeSnapshot(
            previous: prev,
            current: curr,
            elapsedSeconds: 0.0,
            timestamp: 0
        )
        #expect(emptySnapshot == .empty)
    }

    @Test("MonoPorts: Enriquecimento de NetworkPortItem e Filtros de Tráfego")
    func networkPortItemBandwidthEnrichment() {
        let baseItem = NetworkPortItem(
            id: "100-TCP-8080-127.0.0.1-LISTEN",
            pid: 100,
            processName: "NodeApp",
            processPath: "/usr/local/bin/node",
            user: "devuser",
            port: 8080,
            networkProtocol: "TCP",
            ipVersion: "IPv4",
            state: "LISTEN",
            localAddress: "127.0.0.1:8080",
            remoteAddress: nil,
            isWebPort: true
        )

        #expect(baseItem.hasTraffic == false)
        #expect(baseItem.totalSpeed == 0)

        let bandwidth = ProcessBandwidth(
            pid: 100,
            processName: "NodeApp",
            downloadBytesPerSec: 150_000,
            uploadBytesPerSec: 50_000,
            totalDownloaded: 3_000_000,
            totalUploaded: 1_000_000,
            activeSocketCount: 3,
            lastActiveTimestamp: 1000
        )

        let enriched = baseItem.applyingBandwidth(bandwidth)
        #expect(enriched.hasTraffic == true)
        #expect(enriched.downloadBytesPerSec == 150_000)
        #expect(enriched.uploadBytesPerSec == 50_000)
        #expect(enriched.totalSpeed == 200_000)
        #expect(enriched.totalBytesDownloaded == 3_000_000)
        #expect(enriched.totalBytesUploaded == 1_000_000)

        // Sorting check: highest bandwidth first
        let idleItem = NetworkPortItem(
            id: "200-TCP-3000-127.0.0.1-LISTEN",
            pid: 200,
            processName: "IdleApp",
            processPath: nil,
            user: "devuser",
            port: 3000,
            networkProtocol: "TCP",
            ipVersion: "IPv4",
            state: "LISTEN",
            localAddress: "127.0.0.1:3000",
            remoteAddress: nil,
            isWebPort: true
        )

        var list = [idleItem, enriched]
        list.sort { $0.totalSpeed > $1.totalSpeed }
        #expect(list.first?.pid == 100)
        #expect(list.last?.pid == 200)
    }

    // MARK: - MonoStartup Tests

    @Test("MonoStartup: Validação de Itens e Proteção Apple")
    func startupItemsProtection() {
        let appleItem = StartupItem(
            id: "/System/Library/LaunchDaemons/com.apple.syslogd.plist",
            name: "syslogd",
            label: "com.apple.syslogd",
            type: .systemDaemon,
            plistURL: URL(fileURLWithPath: "/System/Library/LaunchDaemons/com.apple.syslogd.plist"),
            executablePath: "/usr/sbin/syslogd",
            arguments: [],
            isEnabled: true,
            runAtLoad: true,
            isApple: true,
            sizeBytes: 1024,
            bundleIdentifier: nil
        )

        let thirdPartyItem = StartupItem(
            id: "/Users/user/Library/LaunchAgents/com.docker.helper.plist",
            name: "docker.helper",
            label: "com.docker.helper",
            type: .userAgent,
            plistURL: URL(fileURLWithPath: "/Users/user/Library/LaunchAgents/com.docker.helper.plist"),
            executablePath: "/Applications/Docker.app/Contents/MacOS/Docker",
            arguments: [],
            isEnabled: true,
            runAtLoad: true,
            isApple: false,
            sizeBytes: 2048,
            bundleIdentifier: "com.docker.docker"
        )

        let orphanedItem = StartupItem(
            id: "/Users/user/Library/LaunchAgents/com.legacy.app.plist",
            name: "legacy.app",
            label: "com.legacy.app",
            type: .userAgent,
            plistURL: URL(fileURLWithPath: "/Users/user/Library/LaunchAgents/com.legacy.app.plist"),
            executablePath: "/Applications/Legacy.app/Contents/MacOS/Legacy",
            arguments: [],
            isEnabled: true,
            runAtLoad: true,
            isApple: false,
            isOrphaned: true,
            sizeBytes: 512,
            bundleIdentifier: "com.legacy.app"
        )

        #expect(appleItem.isApple)
        #expect(!thirdPartyItem.isApple)
        #expect(thirdPartyItem.type == .userAgent)
        #expect(orphanedItem.isOrphaned)
        #expect(!appleItem.isOrphaned)
    }

    @Test("MonoStartup: Login Items e Prioridades de Ordenação")
    func startupLoginItemsAndPriorities() {
        let loginItem = StartupItem(
            id: "loginitem:Spotify",
            name: "Spotify",
            label: "com.apple.loginitem.Spotify",
            type: .loginItem,
            plistURL: nil,
            executablePath: "/Applications/Spotify.app",
            arguments: [],
            isEnabled: true,
            runAtLoad: true,
            isApple: false,
            isOrphaned: false,
            sizeBytes: 150_000_000,
            bundleIdentifier: nil
        )

        #expect(loginItem.type == .loginItem)
        #expect(loginItem.type.icon == "macwindow.badge.plus")
        #expect(loginItem.type.sortPriority == 0)
        #expect(StartupItemType.userAgent.sortPriority == 1)
        #expect(StartupItemType.systemAgent.sortPriority == 2)
        #expect(StartupItemType.systemDaemon.sortPriority == 3)
        #expect(StartupItemType.loginItem.sortPriority < StartupItemType.userAgent.sortPriority)
        #expect(!loginItem.isOrphaned)
        #expect(!loginItem.isApple)
    }

    // MARK: - MonoDupes Tests

    @Test("MonoDupes: Agrupamento e Cálculo de Espaço Recuperável")
    func duplicatesGroupCalculation() {
        let item1 = DuplicateItem(
            url: URL(fileURLWithPath: "/Users/user/Downloads/video.mp4"),
            name: "video.mp4",
            path: "/Users/user/Downloads",
            size: 50_000_000,
            modifiedDate: Date().addingTimeInterval(-3600),
            hash: "abc123hash",
            isSelected: false
        )
        let item2 = DuplicateItem(
            url: URL(fileURLWithPath: "/Users/user/Documents/video_copy.mp4"),
            name: "video_copy.mp4",
            path: "/Users/user/Documents",
            size: 50_000_000,
            modifiedDate: Date(),
            hash: "abc123hash",
            isSelected: true
        )

        let group = DuplicateGroup(
            id: "abc123hash",
            hash: "abc123hash",
            items: [item1, item2],
            sizePerItem: 50_000_000,
            isVisualSimilarity: false
        )

        #expect(group.totalSize == 100_000_000)
        #expect(group.recoverableSize == 50_000_000)
        #expect(group.selectedCount == 1)
        #expect(group.selectedBytes == 50_000_000)
    }

    @Test("MonoDupes: Estratégias de Seleção Inteligente")
    func duplicatesSelectionStrategies() {
        let engine = DuplicatesEngine.shared

        let oldDate = Date().addingTimeInterval(-7200)
        let newDate = Date()

        let itemOld = DuplicateItem(
            url: URL(fileURLWithPath: "/Users/user/Downloads/a.zip"),
            name: "a.zip",
            path: "/Users/user/Downloads",
            size: 10_000,
            modifiedDate: oldDate,
            hash: "hash1"
        )
        let itemNew = DuplicateItem(
            url: URL(fileURLWithPath: "/Users/user/Desktop/a_new.zip"),
            name: "a_new.zip",
            path: "/Users/user/Desktop",
            size: 10_000,
            modifiedDate: newDate,
            hash: "hash1"
        )

        var groups = [
            DuplicateGroup(
                id: "hash1",
                hash: "hash1",
                items: [itemOld, itemNew],
                sizePerItem: 10_000,
                isVisualSimilarity: false
            )
        ]

        // Keep oldest -> newer is selected
        engine.applySelectionStrategy(.keepOldest, to: &groups)
        #expect(groups[0].items.first(where: { $0.modifiedDate == oldDate })?.isSelected == false)
        #expect(groups[0].items.first(where: { $0.modifiedDate == newDate })?.isSelected == true)

        // Keep newest -> older is selected
        engine.applySelectionStrategy(.keepNewest, to: &groups)
        #expect(groups[0].items.first(where: { $0.modifiedDate == oldDate })?.isSelected == true)
        #expect(groups[0].items.first(where: { $0.modifiedDate == newDate })?.isSelected == false)
    }

    // MARK: - MonoEnv Tests

    @Test("MonoEnv: Categorização e Caches Seguros")
    func devEnvCategorization() {
        let derivedData = DevEnvItem(
            id: "/Users/user/Library/Developer/Xcode/DerivedData/App-123",
            name: "DerivedData: App",
            category: .xcode,
            url: URL(fileURLWithPath: "/Users/user/Library/Developer/Xcode/DerivedData/App-123"),
            sizeBytes: 1_200_000_000,
            lastModified: Date(),
            detail: "Xcode build cache",
            isSafeCache: true,
            isSelected: true
        )

        let pythonRuntime = DevEnvItem(
            id: "/Users/user/.pyenv/versions/3.11.4",
            name: "Python 3.11.4",
            category: .python,
            url: URL(fileURLWithPath: "/Users/user/.pyenv/versions/3.11.4"),
            sizeBytes: 300_000_000,
            lastModified: nil,
            detail: "Installed Python runtime",
            isSafeCache: false,
            isSelected: false
        )

        #expect(derivedData.category == .xcode)
        #expect(derivedData.isSafeCache)
        #expect(pythonRuntime.category == .python)
        #expect(!pythonRuntime.isSafeCache)

        let cocoapods = DevEnvItem(
            id: "/Users/user/Library/Caches/CocoaPods",
            name: "CocoaPods Cache",
            category: .xcode,
            url: URL(fileURLWithPath: "/Users/user/Library/Caches/CocoaPods"),
            sizeBytes: 800_000_000,
            detail: "CocoaPods package and spec cache",
            isSafeCache: true,
            isSelected: true
        )

        let gradle = DevEnvItem(
            id: "/Users/user/.gradle/caches",
            name: "Gradle Cache",
            category: .rustGo,
            url: URL(fileURLWithPath: "/Users/user/.gradle/caches"),
            sizeBytes: 2_400_000_000,
            detail: "Gradle dependencies and artifact cache",
            isSafeCache: true,
            isSelected: true
        )

        #expect(cocoapods.isSafeCache)
        #expect(gradle.isSafeCache)
    }

    // MARK: - Sidebar & Feature Integration

    @Test("Integração do Sidebar e Módulos")
    func sidebarIntegration() {
        #expect(SidebarItem.ports.rawValue == "Portas de Rede")
        #expect(SidebarItem.battery.rawValue == "Saúde da Bateria")
        #expect(SidebarItem.startup.rawValue == "Itens de Inicialização")
        #expect(SidebarItem.dupes.rawValue == "Arquivos Duplicados")
        #expect(SidebarItem.env.rawValue == "Ambientes de Dev")

        #expect(SidebarItem.ports.feature == .systemMonitor)
        #expect(SidebarItem.battery.feature == .systemMonitor)
        #expect(SidebarItem.startup.feature == .cleanupTools)
        #expect(SidebarItem.dupes.feature == .cleanupTools)
        #expect(SidebarItem.env.feature == .cleanupTools)
    }
}
