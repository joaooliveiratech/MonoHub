import Foundation
import Synchronization

nonisolated enum CommandRunner {
    enum Failure: Error {
        case untrustedExecutable
        case timedOut
        case outputTooLarge
        case exitStatus(Int32)
    }

    static func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> Data {
        let resolved = executable.resolvingSymlinksInPath()
        guard isTrustedExecutable(resolved) else { throw Failure.untrustedExecutable }

        let process = Process()
        process.executableURL = resolved
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let output = Pipe()
        process.standardOutput = output

        let (terminations, terminated) = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { finished in
            terminated.yield(finished.terminationStatus)
            terminated.finish()
        }

        try process.run()

        let handle = SpawnedProcess(process)
        let watchdog = Task {
            try await Task.sleep(for: timeout)
            handle.terminate()
        }

        let data = await withTaskCancellationHandler {
            await readToEnd(output.fileHandleForReading)
        } onCancel: {
            handle.terminate()
        }

        var status: Int32 = -1
        for await exitStatus in terminations {
            status = exitStatus
        }
        watchdog.cancel()

        if handle.wasTerminated { throw Failure.timedOut }
        guard data.count <= maximumOutputBytes else { throw Failure.outputTooLarge }
        guard status == 0 else { throw Failure.exitStatus(status) }
        return data
    }

    static func isTrustedExecutable(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
        var info = stat()
        guard stat(path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid() || info.st_uid == 0,
              info.st_mode & (S_IWGRP | S_IWOTH) == 0 else { return false }
        return access(path, X_OK) == 0
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = (try? handle.readToEnd()) ?? Data()
                continuation.resume(returning: data)
            }
        }
    }
}

nonisolated private final class SpawnedProcess: Sendable {
    private let state: Mutex<(process: Process?, terminated: Bool)>

    init(_ process: Process) {
        state = Mutex((process: process, terminated: false))
    }

    var wasTerminated: Bool {
        state.withLock { $0.terminated }
    }

    func terminate() {
        state.withLock { current in
            guard let process = current.process, process.isRunning else { return }
            current.terminated = true
            process.terminate()
        }
    }
}
