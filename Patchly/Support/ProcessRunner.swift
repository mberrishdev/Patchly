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
/// (never the Swift concurrency pool, so they can't starve it) and are
/// force-closed after a short grace period past process exit, so a lingering
/// grandchild process still holding a pipe open (e.g. a `curl` spawned by
/// `brew`) can't hang the read past the requested timeout.
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
        process.waitUntilExit()

        let (outData, errData) = await Self.drainPipes(outputPipe: outputPipe, errorPipe: errorPipe)

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

    /// Reads both pipes to completion, but force-closes them a few seconds
    /// after the process has exited if a read is still pending — otherwise a
    /// grandchild process holding a pipe's write end open could block the
    /// read forever, no matter what `timeout` the caller asked for.
    private static func drainPipes(outputPipe: Pipe, errorPipe: Pipe) async -> (Data, Data) {
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        return await withTaskGroup(of: PipeReadOutcome.self) { group in
            group.addTask { .output(await readAllData(from: outputHandle)) }
            group.addTask { .error(await readAllData(from: errorHandle)) }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return .gracePeriodExpired
            }

            var outputData = Data()
            var errorData = Data()
            var pendingReads = 2

            for await outcome in group {
                switch outcome {
                case .output(let data):
                    outputData = data
                    pendingReads -= 1
                case .error(let data):
                    errorData = data
                    pendingReads -= 1
                case .gracePeriodExpired:
                    outputHandle.closeFile()
                    errorHandle.closeFile()
                }
                if pendingReads == 0 { break }
            }
            group.cancelAll()
            return (outputData, errorData)
        }
    }

    private enum PipeReadOutcome: Sendable {
        case output(Data)
        case error(Data)
        case gracePeriodExpired
    }
}
