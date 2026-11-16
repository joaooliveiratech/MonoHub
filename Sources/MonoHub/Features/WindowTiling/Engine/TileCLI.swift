import AppKit
import Foundation

enum TileCLI {
    nonisolated private final class OpenResult: @unchecked Sendable {
        var error: (any Error)?
    }

    private static let informationalFlags: Set<String> = ["-h", "--help", "-v", "--version", "help", "version"]

    static func handles(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        return !first.hasPrefix("-psn") && (!first.hasPrefix("-") || informationalFlags.contains(first))
    }

    static var runningInstance: NSRunningApplication? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.bundleId)
            .first { $0.processIdentifier != ownPID && !$0.isTerminated }
    }

    private static var isInvokedAsScreenshotTool: Bool {
        URL(fileURLWithPath: CommandLine.arguments.first ?? "").lastPathComponent.lowercased() == "monoshot"
    }

    static func run(_ arguments: [String]) -> Int32 {
        guard var command = arguments.first?.lowercased() else { return 0 }
        var arguments = arguments
        if isInvokedAsScreenshotTool, CaptureRequest.allCases.contains(where: { $0.urlCommand == command }) {
            arguments.insert("shot", at: 0)
            command = "shot"
        }

        switch command {
        case "-h", "--help", "help":
            print(usage)
            return 0
        case "-v", "--version", "version":
            print("\(AppInfo.name) v\(AppInfo.version) (Build \(AppInfo.build))")
            return 0
        case "list":
            print("Ações disponíveis de organização de janelas:")
            WindowAction.allCases.forEach { print("  \($0.commandName.padding(toLength: 22, withPad: " ", startingAt: 0)) - \($0.displayName)") }
            return 0
        case "shot", "screenshot":
            let argument = arguments.dropFirst().first?.lowercased() ?? "area"
            guard let request = CaptureRequest.allCases.first(where: { $0.urlCommand == argument }),
                  let url = URL(string: "monoshot://\(request.urlCommand)") else {
                printError("Captura desconhecida “\(argument)”. Use area, fullscreen, window, ocr, scrolling ou record.")
                return 64
            }
            return open([url], activates: false)
        default:
            let imageFiles = ImageFileLoader.fileURLs(fromArguments: arguments)
            if !imageFiles.isEmpty {
                return open(imageFiles, activates: true)
            }
            var actionName = command
            if actionName == "tile" || actionName == "tiling", arguments.count > 1 {
                actionName = arguments[1].lowercased()
            }
            guard let urlCommand = TileURLCommand(name: actionName) else {
                printError("Comando desconhecido “\(command)”. Execute “monohub list” para ver todas as ações disponíveis.")
                return 64
            }
            return send(urlCommand)
        }
    }

    @discardableResult
    static func send(_ command: TileURLCommand) -> Int32 {
        open([command.url], activates: command == .settings)
    }

    @discardableResult
    static func open(_ urls: [URL], activates: Bool) -> Int32 {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppInfo.bundleId) else {

            if urls.allSatisfy({ !$0.isFileURL }), urls.allSatisfy({ NSWorkspace.shared.open($0) }) {
                return 0
            }
            printError("MonoHub.app não está instalado em /Applications.")
            return 69
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        configuration.addsToRecentItems = false

        let result = OpenResult()
        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { _, error in
            result.error = error
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 5) == .success else {
            printError("Tempo esgotado aguardando o MonoHub.")
            return 75
        }
        if let error = result.error {
            printError(error.localizedDescription)
            return 70
        }
        return 0
    }

    private static var usage: String {
        """
        Uso: monohub <ação>  ou  monotile <ação>

          <ação>       Executa uma ação na janela em foco (ex: left-half, right-half, maximize)
          settings     Abre a tela de configurações do MonoHub
          shot <tipo>  Captura a tela: area, fullscreen, window ou ocr (padrão: area)
          <imagem>     Abre uma ou mais imagens no editor de capturas
          list         Lista todas as ações disponíveis de organização de janelas
          --version    Exibe a versão instalada
          --help       Exibe esta ajuda

        As ações também podem ser chamadas via URL Scheme:
          monohub://tile/left-half  ou  monotile://left-half
        E as capturas de tela:
          monoshot://area  monoshot://fullscreen  monoshot://window  monoshot://ocr
        """
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data("monohub: \(message)\n".utf8))
    }
}
