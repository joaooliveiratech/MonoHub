import AppKit

@main
struct MonoHubApp {
    private static var strongAppDelegate: AppDelegate?

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if TileCLI.handles(arguments) {
            exit(TileCLI.run(arguments))
        }

        if let running = TileCLI.runningInstance {
            if let openURL = URL(string: "monohub://open") {
                _ = TileCLI.open([openURL], activates: true)
            }
            running.activate(options: [.activateAllWindows])
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        self.strongAppDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}
