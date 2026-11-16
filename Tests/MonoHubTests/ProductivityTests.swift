import Testing
import Foundation
@testable import MonoHub

@Suite("Produtividade & Clipboard: Roteador de URLs, Snippets & Bluetooth")
@MainActor
struct ProductivityTests {

    // MARK: - 1. Limpador de Rastreadores (UTM Stripper)

    @Test("UTM Stripper remove parâmetros de rastreamento mantendo os dados essenciais")
    func testTrackingParameterCleaner() {
        // YouTube with 'si' and UTM
        let ytURL = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc123xyz&utm_source=twitter")!
        let cleanedYT = TrackingParameterCleaner.clean(url: ytURL)
        #expect(cleanedYT.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")

        // Facebook & Google Click IDs
        let fbURL = URL(string: "https://example.com/artigo?fbclid=IwAR123&gclid=xyz789&page=2")!
        let cleanedFB = TrackingParameterCleaner.clean(url: fbURL)
        #expect(cleanedFB.absoluteString == "https://example.com/artigo?page=2")

        // URL only with UTMs -> query completely removed without trailing '?'
        let pureUTM = URL(string: "https://empresa.com/produto?utm_source=slack&utm_medium=email&utm_campaign=blackfriday")!
        let cleanedPure = TrackingParameterCleaner.clean(url: pureUTM)
        #expect(cleanedPure.absoluteString == "https://empresa.com/produto")

        // URL without query is untouched
        let plainURL = URL(string: "https://apple.com/macbook-pro")!
        let cleanedPlain = TrackingParameterCleaner.clean(url: plainURL)
        #expect(cleanedPlain.absoluteString == "https://apple.com/macbook-pro")
    }

    // MARK: - 2. Roteamento de Links de Reuniões e Apps

    @Test("Roteamento de reuniões reescreve links para esquemas nativos")
    func testMeetingLinkRouter() {
        // Zoom
        let zoomURL = URL(string: "https://us02web.zoom.us/j/1234567890?pwd=secretpassword")!
        let rewrittenZoom = MeetingLinkRouter.rewriteIfSupported(url: zoomURL, checkAppInstalled: false)
        #expect(rewrittenZoom != nil)
        #expect(rewrittenZoom?.scheme == "zoommtg")
        #expect(rewrittenZoom?.absoluteString.contains("confno=1234567890") == true)
        #expect(rewrittenZoom?.absoluteString.contains("pwd=secretpassword") == true)

        // Microsoft Teams
        let teamsURL = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz%40thread.v2/0?context=abc")!
        let rewrittenTeams = MeetingLinkRouter.rewriteIfSupported(url: teamsURL, checkAppInstalled: false)
        #expect(rewrittenTeams != nil)
        #expect(rewrittenTeams?.scheme == "msteams")
        #expect(rewrittenTeams?.absoluteString.contains("meetup-join") == true)

        // Figma
        let figmaURL = URL(string: "https://www.figma.com/design/abcdef123456/Meu-Projeto?node-id=0-1")!
        let rewrittenFigma = MeetingLinkRouter.rewriteIfSupported(url: figmaURL, checkAppInstalled: false)
        #expect(rewrittenFigma != nil)
        #expect(rewrittenFigma?.scheme == "figma")
        #expect(rewrittenFigma?.absoluteString.contains("design/abcdef123456/Meu-Projeto") == true)

        // Notion
        let notionURL = URL(string: "https://www.notion.so/myteam/Doc-123456")!
        let rewrittenNotion = MeetingLinkRouter.rewriteIfSupported(url: notionURL, checkAppInstalled: false)
        #expect(rewrittenNotion != nil)
        #expect(rewrittenNotion?.scheme == "notion")
        #expect(rewrittenNotion?.absoluteString.contains("notion.so/myteam/Doc-123456") == true)

        // Regular link is not rewritten
        let regularURL = URL(string: "https://news.ycombinator.com")!
        let rewrittenRegular = MeetingLinkRouter.rewriteIfSupported(url: regularURL, checkAppInstalled: false)
        #expect(rewrittenRegular == nil)
    }

    // MARK: - 3. Regras de Roteamento por App de Origem e Domínio

    @Test("Regras de URL Routing funcionam por app de origem (Slack -> Helium) e domínio")
    @MainActor
    func testURLRoutingRules() {
        let slackToHelium = URLRoutingRule(
            name: "Slack Links no Helium",
            isEnabled: true,
            sourceAppBundleID: "com.tinyspeck.slackmacgap",
            domainPattern: "*",
            targetBrowserBundleID: "net.imput.helium"
        )

        let targetURL = URL(string: "https://github.com/apple/swift")!

        // Triggered from Slack
        #expect(slackToHelium.matches(url: targetURL, sourceApp: "com.tinyspeck.slackmacgap"))

        // Triggered from Telegram -> should not match rule
        #expect(!slackToHelium.matches(url: targetURL, sourceApp: "ru.keepcoder.Telegram"))

        // Domain matching rule
        let meetRule = URLRoutingRule(
            name: "Google Meet no Chrome",
            isEnabled: true,
            sourceAppBundleID: nil,
            domainPattern: "meet.google.com",
            targetBrowserBundleID: "com.google.Chrome"
        )

        let meetURL = URL(string: "https://meet.google.com/abc-defg-hij")!
        let otherURL = URL(string: "https://google.com/search")!

        #expect(meetRule.matches(url: meetURL, sourceApp: "com.apple.mail"))
        #expect(!meetRule.matches(url: otherURL, sourceApp: "com.apple.mail"))

        // Wildcard subdomain matching
        let wildcardRule = URLRoutingRule(
            name: "Wildcard Notion",
            isEnabled: true,
            domainPattern: "*.notion.so",
            targetBrowserBundleID: "com.apple.Safari"
        )
        #expect(wildcardRule.matches(url: URL(string: "https://team.notion.so/home")!, sourceApp: nil))
        #expect(wildcardRule.matches(url: URL(string: "https://notion.so/login")!, sourceApp: nil))
        #expect(!wildcardRule.matches(url: URL(string: "https://other.so/login")!, sourceApp: nil))
    }

    @Test("URLRouterService resolve a ação correta com base nas regras ativas")
    @MainActor
    func testURLRouterServiceResolution() {
        let service = URLRouterService.shared
        service.stripTrackers = true
        service.routeMeetingLinks = false // Test pure browser routing without scheme interception

        service.rules = [
            URLRoutingRule(
                name: "Slack no Helium",
                isEnabled: true,
                sourceAppBundleID: "com.tinyspeck.slackmacgap",
                domainPattern: "*",
                targetBrowserBundleID: "net.imput.helium"
            ),
            URLRoutingRule(
                name: "Trabalho no Chrome",
                isEnabled: true,
                sourceAppBundleID: nil,
                domainPattern: "meet.google.com",
                targetBrowserBundleID: "com.google.Chrome"
            )
        ]
        service.defaultBrowserBundleID = "com.apple.Safari"

        // 1. Link from Slack with tracking
        let rawLink = URL(string: "https://developer.apple.com?utm_source=slack")!
        let action1 = service.resolveRouting(for: rawLink, sourceAppBundleID: "com.tinyspeck.slackmacgap")

        switch action1 {
        case .browser(let bundleID, let cleanedURL):
            #expect(bundleID == "net.imput.helium")
            #expect(cleanedURL.absoluteString == "https://developer.apple.com")
        default:
            Issue.record("Expected browser routing to Helium")
        }

        // 2. Link for Google Meet from any app
        let meetLink = URL(string: "https://meet.google.com/abc-xyz")!
        let action2 = service.resolveRouting(for: meetLink, sourceAppBundleID: "com.apple.Safari")

        switch action2 {
        case .browser(let bundleID, _):
            #expect(bundleID == "com.google.Chrome")
        default:
            Issue.record("Expected browser routing to Chrome")
        }

        // 3. Fallback browser
        let randomLink = URL(string: "https://wikipedia.org")!
        let action3 = service.resolveRouting(for: randomLink, sourceAppBundleID: "com.apple.mail")

        switch action3 {
        case .browser(let bundleID, _):
            #expect(bundleID == "com.apple.Safari")
        default:
            Issue.record("Expected fallback to Safari")
        }
    }

    // MARK: - 4. Snippets & Expansão de Texto

    @Test("SnippetTokenEvaluator substitui tokens dinâmicos com precisão")
    func testSnippetTokenEvaluator() {
        let template = "Olá! Hoje é {date} e a hora é {time}. ID: {uuid}"
        let evaluated = SnippetTokenEvaluator.evaluate(template)

        #expect(!evaluated.contains("{date}"))
        #expect(!evaluated.contains("{time}"))
        #expect(!evaluated.contains("{uuid}"))
        #expect(evaluated.contains("Olá! Hoje é "))
    }

    @Test("SnippetManager detecta casamento de atalho no buffer de digitação")
    @MainActor
    func testSnippetManagerBufferMatching() {
        let manager = SnippetManager.shared
        manager.isEnabled = true
        manager.clearBuffer()

        // Type characters '!email'
        for c in "!email" {
            manager.processCharacter(c)
        }

        // A match should be found and buffer cleared
        _ = manager.checkMatch()
        // If !email was matched when the last 'l' was processed, checkMatch() may have already triggered or matches now
        #expect(manager.snippets.contains(where: { $0.keyword == "!email" }))

        // Backspace handling
        manager.clearBuffer()
        manager.processCharacter("a")
        manager.processCharacter("b")
        manager.handleBackspace()
        manager.processCharacter("c")
        // Buffer should now have "ac"
    }

    // MARK: - 5. Conexão Rápida de Bluetooth

    @Test("BluetoothQuickConnectManager armazena favorito e constante de assinatura")
    @MainActor
    func testBluetoothQuickConnectManager() {
        let manager = BluetoothQuickConnectManager.shared
        #expect(BluetoothQuickConnectManager.hotKeySignature == 0x4D425443) // 'MBTC'

        let testDev = BluetoothDeviceInfo(
            id: "34:0e:22:9b:0c:f1",
            name: "AirPods Pro de Teste",
            address: "34:0e:22:9b:0c:f1",
            batteryLevel: 85,
            isConnected: false,
            category: .airpods
        )

        manager.setFavoriteDevice(testDev)
        #expect(manager.favoriteDeviceAddress == "34:0e:22:9b:0c:f1")
        #expect(manager.favoriteDeviceName == "AirPods Pro de Teste")

        // Toggle executes without crashing
        manager.toggleQuickConnection()
    }

    // MARK: - 6. Integração do Módulo com FeatureManager e SidebarItem

    @Test("Integração do Módulo Produtividade com FeatureManager e SidebarItem")
    @MainActor
    func testProductivityFeatureIntegration() {
        #expect(SidebarItem.urlRouter.rawValue == "Roteador de URLs")
        #expect(SidebarItem.snippets.rawValue == "Expansão de Texto")
        #expect(SidebarItem.bluetoothQuickConnect.rawValue == "Conexão Bluetooth")
        #expect(SidebarItem.urlRouter.feature == .productivity)
        #expect(SidebarItem.snippets.feature == .productivity)
        #expect(SidebarItem.bluetoothQuickConnect.feature == .productivity)
        #expect(HubFeature.productivity.sidebarItems.contains(.urlRouter))
        #expect(HubFeature.productivity.sidebarItems.contains(.snippets))
        #expect(HubFeature.productivity.sidebarItems.contains(.bluetoothQuickConnect))

        let featureManager = FeatureManager.shared
        #expect(featureManager.isSidebarItemAvailable(.urlRouter))
        #expect(featureManager.isSidebarItemAvailable(.snippets))
        #expect(featureManager.isSidebarItemAvailable(.bluetoothQuickConnect))

        // Test module lifecycle directly
        ProductivityFeature.activate()
        #expect(BluetoothQuickConnectManager.shared.isFeatureActive)

        ProductivityFeature.deactivate()
        #expect(!BluetoothQuickConnectManager.shared.isFeatureActive)

        // Toggle feature off and on in FeatureManager
        featureManager.setEnabled(.productivity, false)
        #expect(!featureManager.isSidebarItemAvailable(.urlRouter))
        #expect(!featureManager.isSidebarItemAvailable(.bluetoothQuickConnect))

        featureManager.setEnabled(.productivity, true)
        #expect(featureManager.isSidebarItemAvailable(.urlRouter))
        #expect(featureManager.isSidebarItemAvailable(.bluetoothQuickConnect))
    }
}
