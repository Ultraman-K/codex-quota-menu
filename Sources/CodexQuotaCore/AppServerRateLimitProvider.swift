import Foundation

public actor AppServerRateLimitProvider: RateLimitProvider {
    public nonisolated let source: QuotaSource = .appServer

    private let transport: any LineTransport
    private let now: @Sendable () -> Date
    private let logger: DiagnosticsLogger?
    private let startupTimeout: Duration
    private let requestTimeout: Duration
    private var started = false
    private var nextRequestID = 1
    private var readerTask: Task<Void, Never>?
    private var pending: [Int: CheckedContinuation<AppServerDecodedMessage, Error>] = [:]
    private var completed: [Int: AppServerDecodedMessage] = [:]
    private var terminalError: Error?
    private var latestWireSnapshot: AppServerWireSnapshot?
    private var updateContinuation: AsyncThrowingStream<RawQuotaSnapshot, Error>.Continuation?
    private var requestDidTimeout = false

    public init(
        transport: any LineTransport,
        now: @escaping @Sendable () -> Date = Date.init,
        startupTimeout: Duration = .seconds(30),
        requestTimeout: Duration = .seconds(30),
        logger: DiagnosticsLogger? = nil
    ) {
        self.transport = transport
        self.now = now
        self.logger = logger
        self.startupTimeout = startupTimeout
        self.requestTimeout = requestTimeout
    }

    public init(
        locator: CodexExecutableLocator = .init(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        logger: DiagnosticsLogger? = nil
    ) throws {
        guard let executableURL = locator.resolve() else {
            throw RateLimitProviderError.codexNotFound
        }
        let command = CodexAppServerCommand(codexURL: executableURL)
        transport = LineProcessTransport(executableURL: command.executableURL, arguments: command.arguments, environment: environment, logger: logger)
        now = Date.init
        self.logger = logger
        startupTimeout = .seconds(30)
        requestTimeout = .seconds(30)
    }

    public func fetch() async throws -> RawQuotaSnapshot {
        requestDidTimeout = false
        do {
            try await withTimeout(startupTimeout) { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.startIfNeeded()
            }
            return try await withTimeout(requestTimeout) { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.readQuotaWithRetry()
            }
        } catch {
            if requestDidTimeout { throw RateLimitProviderError.timedOut }
            throw error
        }
    }

    private func readQuota() async throws -> RawQuotaSnapshot {
        let message = try await request(method: "account/rateLimits/read", params: nil)
        try throwForMessageError(message)
        guard let snapshot = message.snapshot else { throw RateLimitProviderError.noQuotaData }
        latestWireSnapshot = snapshot
        return snapshot.toRaw(capturedAt: now())
    }

    private func readQuotaWithRetry() async throws -> RawQuotaSnapshot {
        for attempt in 0..<3 {
            do {
                return try await readQuota()
            } catch let error as RateLimitProviderError where error == .networkUnavailable && attempt < 2 {
                guard terminalError == nil else { throw error }
                let delay: Duration = attempt == 0 ? .seconds(1) : .seconds(3)
                await logger?.log(level: .warning, component: "refresh", message: "quota request network retry attempt=\(attempt + 1) delay=\(delay.components.seconds)s")
                try await Task.sleep(for: delay)
            } catch {
                throw error
            }
        }
        throw RateLimitProviderError.networkUnavailable
    }

    private func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let timeoutTask = Task.detached { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.timeoutCurrentRequest()
        }
        defer { timeoutTask.cancel() }
        return try await operation()
    }

    private func timeoutCurrentRequest() async {
        requestDidTimeout = true
        await stop()
    }

    public func updates() async -> AsyncThrowingStream<RawQuotaSnapshot, Error> {
        let pair = AsyncThrowingStream<RawQuotaSnapshot, Error>.makeStream()
        updateContinuation = pair.continuation
        return pair.stream
    }

    public func stop() async {
        readerTask?.cancel()
        readerTask = nil
        for continuation in pending.values {
            continuation.resume(throwing: CancellationError())
        }
        pending.removeAll()
        completed.removeAll()
        updateContinuation?.finish()
        updateContinuation = nil
        latestWireSnapshot = nil
        terminalError = nil
        started = false
        await transport.stop()
    }

    private func startIfNeeded() async throws {
        if started, terminalError == nil { return }
        if started { await stop() }
        try await transport.start()
        started = true
        readerTask = Task { [weak self] in
            await self?.consumeLines()
        }

        let initialize = try await request(
            method: "initialize",
            params: [
                "clientInfo": ["name": "codex-quota-menu", "version": "0.1.0"],
                "capabilities": ["experimentalApi": false]
            ]
        )
        try throwForMessageError(initialize)
        try await sendNotification(method: "initialized", params: NSNull())
    }

    private func request(method: String, params: Any?) async throws -> AppServerDecodedMessage {
        let identifier = nextRequestID
        nextRequestID += 1
        var object: [String: Any] = ["id": identifier, "method": method]
        if let params { object["params"] = params }
        let data = try JSONSerialization.data(withJSONObject: object)
        try await transport.send(data)

        if let message = completed.removeValue(forKey: identifier) { return message }
        if let terminalError { throw terminalError }
        return try await withCheckedThrowingContinuation { continuation in
            pending[identifier] = continuation
        }
    }

    private func sendNotification(method: String, params: Any) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["method": method, "params": params])
        try await transport.send(data)
    }

    private func consumeLines() async {
        let lines = await transport.lines()
        do {
            for try await line in lines {
                let message = try AppServerMessageDecoder.decode(line)
                receive(message)
            }
            if !Task.isCancelled {
                failPending(with: RateLimitProviderError.processExited(0))
            }
        } catch {
            failPending(with: error)
        }
    }

    private func receive(_ message: AppServerDecodedMessage) {
        if let identifier = message.id {
            if let continuation = pending.removeValue(forKey: identifier) {
                continuation.resume(returning: message)
            } else {
                completed[identifier] = message
            }
        }

        guard message.method == "account/rateLimits/updated", let update = message.snapshot else { return }
        let merged = latestWireSnapshot.map { $0.mergingSparse(update) } ?? update
        latestWireSnapshot = merged
        updateContinuation?.yield(merged.toRaw(capturedAt: now()))
    }

    private func failPending(with error: Error) {
        terminalError = error
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
        updateContinuation?.finish(throwing: error)
    }

    private func throwForMessageError(_ message: AppServerDecodedMessage) throws {
        guard let errorMessage = message.errorMessage else { return }
        let normalized = errorMessage.lowercased()
        if normalized.contains("login") || normalized.contains("authentication") || normalized.contains("401") {
            throw RateLimitProviderError.notAuthenticated
        }
        if normalized.contains("failed to fetch codex rate limits") || normalized.contains("error sending request") {
            throw RateLimitProviderError.networkUnavailable
        }
        throw RateLimitProviderError.protocolViolation(errorMessage)
    }
}
