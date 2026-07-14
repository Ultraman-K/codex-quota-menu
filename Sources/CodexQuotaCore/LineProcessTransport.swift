import Foundation

public protocol LineTransport: Sendable {
    func start() async throws
    func send(_ line: Data) async throws
    func lines() async -> AsyncThrowingStream<Data, Error>
    func stop() async
}

public actor LineProcessTransport: LineTransport {
    private let executableURL: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let logger: DiagnosticsLogger?
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var stderr: FileHandle?
    private var streamPair: (stream: AsyncThrowingStream<Data, Error>, continuation: AsyncThrowingStream<Data, Error>.Continuation)?
    private var buffer = Data()
    private var terminationStatus: Int32?
    private var outputReachedEOF = false
    private var didFinish = false
    private var outputTask: Task<Void, Never>?
    private var generation = 0

    public init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        logger: DiagnosticsLogger? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.logger = logger
    }

    public func start() async throws {
        guard process == nil else { return }
        generation += 1
        let processGeneration = generation
        buffer.removeAll(keepingCapacity: false)
        terminationStatus = nil
        outputReachedEOF = false
        didFinish = false

        let child = Process()
        let input = Pipe()
        let output = Pipe()
        let errorPipe = Pipe()
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        let logger = logger

        child.executableURL = executableURL
        child.arguments = arguments
        child.environment = environment
        child.standardInput = input
        child.standardOutput = output
        child.standardError = errorPipe
        child.terminationHandler = { [weak self] process in
            if let logger {
                Task { await logger.log(level: process.terminationStatus == 0 ? .info : .error, component: "codex", message: "process exited with status \(process.terminationStatus)") }
            }
            Task { await self?.recordTermination(process.terminationStatus, generation: processGeneration) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let logger else { return }
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }
            Task { await logger.log(level: .error, component: "codex", message: message) }
        }

        do {
            try child.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            pair.continuation.finish(throwing: error)
            throw error
        }

        process = child
        stdin = input.fileHandleForWriting
        stdout = output.fileHandleForReading
        stderr = errorPipe.fileHandleForReading
        streamPair = pair
        if let logger {
            Task { await logger.log(level: .info, component: "codex", message: "started \(executableURL.path) \(arguments.joined(separator: " "))") }
        }
        readOutputUntilEOF(from: output.fileHandleForReading, generation: processGeneration)
    }

    public func send(_ line: Data) async throws {
        guard let stdin else { throw RateLimitProviderError.processExited(-1) }
        var terminated = line
        terminated.append(0x0A)
        try stdin.write(contentsOf: terminated)
    }

    public func lines() async -> AsyncThrowingStream<Data, Error> {
        if let streamPair { return streamPair.stream }
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: RateLimitProviderError.processExited(-1))
        }
    }

    public func stop() async {
        outputTask?.cancel()
        outputTask = nil
        stdout?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminate()
            if let logger {
                Task { await logger.log(level: .info, component: "codex", message: "terminated process") }
            }
        }
        stdin?.closeFile()
        stdout?.closeFile()
        stderr?.closeFile()
        streamPair?.continuation.finish()
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        streamPair = nil
        buffer.removeAll(keepingCapacity: false)
        terminationStatus = nil
        outputReachedEOF = false
        didFinish = true
    }

    private func appendOutput(_ data: Data, generation: Int) {
        guard generation == self.generation else { return }
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if !line.isEmpty { streamPair?.continuation.yield(Data(line)) }
        }
    }

    private func readOutputUntilEOF(from handle: FileHandle, generation: Int) {
        outputTask = Task.detached { [weak self] in
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { break }
                await self?.appendOutput(data, generation: generation)
            }
            await self?.recordOutputEOF(generation: generation)
        }
    }

    private func recordTermination(_ status: Int32, generation: Int) {
        guard generation == self.generation else { return }
        terminationStatus = status
        finishIfReady()
    }

    private func recordOutputEOF(generation: Int) {
        guard generation == self.generation else { return }
        outputReachedEOF = true
        finishIfReady()
    }

    private func finishIfReady() {
        guard !didFinish, outputReachedEOF, let terminationStatus else { return }
        didFinish = true
        if !buffer.isEmpty {
            streamPair?.continuation.yield(buffer)
            buffer.removeAll(keepingCapacity: false)
        }
        if terminationStatus == 0 {
            streamPair?.continuation.finish()
        } else {
            streamPair?.continuation.finish(throwing: RateLimitProviderError.processExited(terminationStatus))
        }
    }
}
