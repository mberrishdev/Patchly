import Foundation

struct ProcessResult: Sendable {
    let standardOutput: String
    let standardError: String
    let terminationStatus: Int32

    var succeeded: Bool { terminationStatus == 0 }
}

enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): "failed to launch: \(reason)"
        case .timedOut: "timed out"
        }
    }
}

protocol ProcessRunning: Sendable {
    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult
}

/// Async wrapper over `Process`. Cooperatively cancellable: if the calling
/// Task is cancelled, or `timeout` elapses first, the child is terminated and
/// this function throws rather than returning a result — callers already
/// treat a thrown error as a failed check. Pipe reads run on a GCD queue
/// (never the Swift concurrency pool, so they can't starve it), start as
/// soon as the process launches (not after it exits — a command whose
/// output exceeds the OS pipe buffer, roughly 64KB, would otherwise block
/// the child on `write()` forever, since nothing would be reading from the
/// pipe until `waitUntilExit()` returns, which itself never would), and are
/// force-closed a few seconds after the process exits if a read is still
/// pending, so a lingering grandchild process still holding a pipe open
/// (e.g. a `curl` spawned by `brew`) can't hang the read past the requested
/// timeout.
struct ProcessRunner: ProcessRunning {
    func run(executablePath: String, arguments: [String], timeout: TimeInterval = 15) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        // Started now, before the exit-wait below — not after — so a
        // large-output command can't deadlock the child on a full pipe.
        // Plain `Task` handles, not `async let` — the grace-period race
        // below needs to capture them inside a `withTaskGroup` child task,
        // which `async let` bindings can't be.
        let outputTask = Task { await Self.readAllData(from: outputPipe.fileHandleForReading) }
        let errorTask = Task { await Self.readAllData(from: errorPipe.fileHandleForReading) }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                break
            }
            if Date() > deadline {
                timedOut = true
                process.terminate()
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        // SIGTERM above is a request, not a guarantee — a child stuck in an
        // uninterruptible wait (or one that just ignores it) would otherwise
        // leave `waitUntilExit()` below blocking forever, defeating the
        // timeout entirely. Escalate to SIGKILL after a bounded grace period.
        if process.isRunning {
            let killDeadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < killDeadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()

        // The reads above are already in flight (and likely already done,
        // since the process just exited/was terminated) — this only races
        // them against a grace period in case a grandchild is still holding
        // a pipe's write end open.
        let (outData, errData) = await withTaskGroup(of: PipeReadOutcome.self) { group in
            group.addTask { .output(await outputTask.value) }
            group.addTask { .error(await errorTask.value) }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return .gracePeriodExpired
            }

            var outputResult = Data()
            var errorResult = Data()
            var pendingReads = 2

            for await outcome in group {
                switch outcome {
                case .output(let data):
                    outputResult = data
                    pendingReads -= 1
                case .error(let data):
                    errorResult = data
                    pendingReads -= 1
                case .gracePeriodExpired:
                    outputPipe.fileHandleForReading.closeFile()
                    errorPipe.fileHandleForReading.closeFile()
                }
                if pendingReads == 0 { break }
            }
            group.cancelAll()
            return (outputResult, errorResult)
        }

        if Task.isCancelled {
            throw CancellationError()
        }
        if timedOut {
            throw ProcessRunnerError.timedOut
        }

        return ProcessResult(
            standardOutput: String(data: outData, encoding: .utf8) ?? "",
            standardError: String(data: errData, encoding: .utf8) ?? "",
            terminationStatus: process.terminationStatus
        )
    }

    private static func readAllData(from handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }

    private enum PipeReadOutcome: Sendable {
        case output(Data)
        case error(Data)
        case gracePeriodExpired
    }
}
