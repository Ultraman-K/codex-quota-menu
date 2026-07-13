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
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var stderr: FileHandle?
    private var streamPair: (stream: AsyncThrowingStream<Data, Error>, continuation: AsyncThrowingStream<Data, Error>.Continuation)?
    private var buffer = Data()
    private var terminationStatus: Int32?
    private var outputReachedEOF = false
    private var didFinish = false

    public init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }

    public func start() async throws {
        guard process == nil else { return }

        let child = Process()
        let input = Pipe()
        let output = Pipe()
        let errorPipe = Pipe()
        let pair = AsyncThrowingStream<Data, Error>.makeStream()

        child.executableURL = executableURL
        child.arguments = arguments
        child.standardInput = input
        child.standardOutput = output
        child.standardError = errorPipe
        child.terminationHandler = { [weak self] process in
            Task { await self?.recordTermination(process.terminationStatus) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
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
        readOutputUntilEOF(from: output.fileHandleForReading)
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
        stdout?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        if let process, process.isRunning { process.terminate() }
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

    private func appendOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if !line.isEmpty { streamPair?.continuation.yield(Data(line)) }
        }
    }

    private func readOutputUntilEOF(from handle: FileHandle) {
        Task.detached { [weak self] in
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { break }
                await self?.appendOutput(data)
            }
            await self?.recordOutputEOF()
        }
    }

    private func recordTermination(_ status: Int32) {
        terminationStatus = status
        finishIfReady()
    }

    private func recordOutputEOF() {
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
