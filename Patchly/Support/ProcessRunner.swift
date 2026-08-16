import Foundation

struct ProcessResult: Sendable {
    let standardOutput: String
    let standardError: String
    let terminationStatus: Int32

    var succeeded: Bool { terminationStatus == 0 }
}

enum ProcessRunnerError: Error {
    case launchFailed(String)
}

protocol ProcessRunning: Sendable {
    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult
}

/// Async wrapper over `Process`. Drains stdout/stderr concurrently with execution
/// (never after `waitUntilExit`) so a chatty child process can't deadlock on a full pipe.
struct ProcessRunner: ProcessRunning {
    func run(executablePath: String, arguments: [String], timeout: TimeInterval = 15) async throws -> ProcessResult {
        try await Task.detached(priority: .utility) {
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

            let outputHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading

            async let outputData = Task.detached(priority: .utility) {
                outputHandle.readDataToEndOfFile()
            }.value
            async let errorData = Task.detached(priority: .utility) {
                errorHandle.readDataToEndOfFile()
            }.value

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if Date() > deadline {
                    process.terminate()
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            process.waitUntilExit()

            let (outData, errData) = await (outputData, errorData)
            return ProcessResult(
                standardOutput: String(data: outData, encoding: .utf8) ?? "",
                standardError: String(data: errData, encoding: .utf8) ?? "",
                terminationStatus: process.terminationStatus
            )
        }.value
    }
}
