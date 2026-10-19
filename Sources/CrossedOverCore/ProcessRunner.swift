import Foundation

public struct ProcessResult: Sendable {
    public var status: Int32
    public var output: String
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()
    let lock = NSLock()
    private var cancelled = false
    func start() throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
            try process.run()
        }
    }
    func cancel() { lock.withLock { cancelled = true; if process.isRunning { process.terminate() } } }
}

public enum ProcessRunner {
    public static func run(_ executable: URL, arguments: [String] = [], workingDirectory: URL? = nil, environment: [String: String]? = nil,
                           input: Data? = nil, timeout: TimeInterval = 120) async throws -> ProcessResult {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            let result = try await Task.detached {
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                FileManager.default.createFile(atPath: temporary.path, contents: nil)
                let output = try FileHandle(forWritingTo: temporary)
                defer { try? output.close(); try? FileManager.default.removeItem(at: temporary) }
                box.process.executableURL = executable; box.process.arguments = arguments
                box.process.currentDirectoryURL = workingDirectory
                box.process.environment = environment ?? ProcessInfo.processInfo.environment
                box.process.standardOutput = output; box.process.standardError = output
                var inputHandle: FileHandle?
                var inputURL: URL?
                if let input {
                    let url = temporary.appendingPathExtension("input")
                    try input.write(to: url); inputURL = url
                    inputHandle = try FileHandle(forReadingFrom: url); box.process.standardInput = inputHandle
                } else { box.process.standardInput = FileHandle.nullDevice }
                defer { try? inputHandle?.close(); if let inputURL { try? FileManager.default.removeItem(at: inputURL) } }
                try box.start()
                let deadline = Date().addingTimeInterval(timeout)
                while box.process.isRunning {
                    if Date() > deadline { box.cancel(); throw CrossedOverError.message("The command timed out. Stop the environment before retrying.") }
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(50))
                }
                try output.synchronize()
                let reader = try FileHandle(forReadingFrom: temporary)
                defer { try? reader.close() }
                let data = try reader.read(upToCount: 2 * 1024 * 1024) ?? Data()
                return ProcessResult(status: box.process.terminationStatus, output: String(decoding: data, as: UTF8.self))
            }.value
            try Task.checkCancellation()
            return result
        } onCancel: { box.cancel() }
    }
}
