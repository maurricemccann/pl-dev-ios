import Foundation
import Security

/// An error that already is one plain sentence.
struct PlainError: Error, Sendable {
    let message: String
}

/// Server name matching: checks the certificate against the configured NAME, whatever host the request used,
/// so a fallback address still validates. The chain is still checked against the system roots. This is not pinning.
final class NameTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let certName: String

    init(certName: String) {
        self.certName = certName
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let policy = SecPolicyCreateSSL(true, certName as CFString)
        guard SecTrustSetPolicies(trust, policy) == errSecSuccess, SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

/// The one network client. It only ever runs a `RequestPlan`, so every address and key comes from the loaded config.
actor HTTPClient {
    enum Failure: Error, Equatable, Sendable {
        case unauthorized, badAddress, http(Int)

        var message: String {
            switch self {
            case .unauthorized: return "The key was refused. Load your config again."
            case .badAddress: return "The config has no usable address for this."
            case .http(let code): return "The server answered with an error (\(code))."
            }
        }
    }

    private static let maxAttempts = 4   // a ceiling of our own, whatever the retry table says

    private let config: PLDevConfig
    private var sessions: [String: URLSession] = [:]   // one per certificate name; "" is the plain session
    private var answered: [String: Int] = [:]          // per origin: which planned address answered last

    init(config: PLDevConfig) {
        self.config = config
    }

    deinit {
        for session in sessions.values { session.invalidateAndCancel() }
    }

    /// Runs the plan and returns the body. Throws on anything but a 2xx, as one of `Failure` or a `URLError`.
    func send(_ plan: RequestPlan, idempotent: Bool? = nil, extraHeaders: [String: String] = [:], timeout: TimeInterval = 20) async throws -> Data {
        let (status, data) = try await exchange(plan, idempotent: idempotent, extraHeaders: extraHeaders, timeout: timeout, attempts: Self.maxAttempts)
        if status == 401 { throw Failure.unauthorized }
        guard (200..<300).contains(status) else { throw Failure.http(status) }
        return data
    }

    /// One try, no retry: the status code whatever it is. For reachability checks, where any answer means "reachable".
    func status(_ plan: RequestPlan, timeout: TimeInterval = 10) async throws -> Int {
        try await exchange(plan, idempotent: true, extraHeaders: [:], timeout: timeout, attempts: 1).0
    }

    /// Server-sent events from the plan's address, one message at a time. Ends when the server closes or the caller stops reading.
    /// shortcut: one connection on the address that answered last, no reconnect; a section that needs a standing line adds its own loop.
    nonisolated func stream(_ plan: RequestPlan) -> AsyncThrowingStream<SSEParser.Message, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (request, session) = try await self.streamRequest(plan)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw Failure.http(0) }
                    if http.statusCode == 401 { throw Failure.unauthorized }
                    guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
                    var parser = SSEParser()
                    var line: [UInt8] = []
                    // Byte by byte: a line reader can drop the blank lines that end each event.
                    for try await byte in bytes {
                        if byte != 0x0A {
                            line.append(byte)
                            continue
                        }
                        let text = String(decoding: line, as: UTF8.self)
                        line.removeAll(keepingCapacity: true)
                        if let message = parser.feed(text) { continuation.yield(message) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: inside

    /// Errors that mean "this address did not answer at all", so the other address is worth a try.
    private static func unreachable(_ code: URLError.Code) -> Bool {
        code == .cannotFindHost || code == .dnsLookupFailed || code == .cannotConnectToHost
    }

    private static func wasCancelled(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func session(certName: String?) -> URLSession {
        let name = certName ?? ""
        if let ready = sessions[name] { return ready }
        let setup = URLSessionConfiguration.ephemeral
        setup.timeoutIntervalForRequest = 20
        setup.waitsForConnectivity = false
        let made = name.isEmpty ? URLSession(configuration: setup)
                                : URLSession(configuration: setup, delegate: NameTrust(certName: name), delegateQueue: nil)
        sessions[name] = made
        return made
    }

    private func request(_ planned: PlannedRequest, extraHeaders: [String: String], timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: planned.url)
        request.httpMethod = planned.method
        request.timeoutInterval = timeout
        for (name, value) in planned.headers { request.setValue(value, forHTTPHeaderField: name) }
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = planned.body
        return request
    }

    private func streamRequest(_ plan: RequestPlan) throws -> (URLRequest, URLSession) {
        let planned = try plan.urlRequests(config: config)
        guard !planned.isEmpty else { throw Failure.badAddress }
        let pick = planned[min(answered[plan.origin] ?? 0, planned.count - 1)]
        var made = request(pick, extraHeaders: ["Accept": "text/event-stream"], timeout: 120)   // 120 s without a byte ends the read
        made.cachePolicy = .reloadIgnoringLocalCacheData
        return (made, session(certName: pick.certName))
    }

    /// Each planned address in turn, starting with the one that answered last; moves on only when an address is unreachable.
    private func once(_ planned: [PlannedRequest], origin: String, extraHeaders: [String: String], timeout: TimeInterval) async throws -> (Int, Data) {
        var last: any Error = Failure.badAddress
        let start = min(answered[origin] ?? 0, planned.count - 1)
        for step in planned.indices {
            let index = (start + step) % planned.count
            do {
                let made = request(planned[index], extraHeaders: extraHeaders, timeout: timeout)
                let (data, response) = try await session(certName: planned[index].certName).data(for: made)
                guard let http = response as? HTTPURLResponse else { throw Failure.http(0) }
                answered[origin] = index
                return (http.statusCode, data)
            } catch let error as URLError where Self.unreachable(error.code) {
                last = error
            }
        }
        throw last
    }

    private func exchange(_ plan: RequestPlan, idempotent: Bool?, extraHeaders: [String: String], timeout: TimeInterval, attempts: Int) async throws -> (Int, Data) {
        let planned = try plan.urlRequests(config: config)
        guard !planned.isEmpty else { throw Failure.badAddress }
        let safe = idempotent ?? ["GET", "HEAD", "PUT", "DELETE"].contains(plan.method.uppercased())
        var attempt = 1
        while true {
            let outcome: Result<(Int, Data), any Error>
            do {
                outcome = .success(try await once(planned, origin: plan.origin, extraHeaders: extraHeaders, timeout: timeout))
            } catch {
                outcome = .failure(error)
            }
            let status: Int?
            switch outcome {
            case .success(let answer):
                if (200..<300).contains(answer.0) { return answer }
                status = answer.0
            case .failure(let error):
                if Self.wasCancelled(error) { throw error }
                status = nil
            }
            guard attempt < attempts, RetryPolicy.shouldRetry(status: status, attempt: attempt, idempotent: safe) else {
                return try outcome.get()
            }
            try await Task.sleep(for: .seconds(RetryPolicy.delay(attempt: attempt)))
            attempt += 1
        }
    }
}

/// Any error as one plain sentence for a status line. Never contains an address or a key.
func plainSentence(_ error: any Error) -> String {
    if let plain = error as? PlainError { return plain.message }
    if let failure = error as? HTTPClient.Failure { return failure.message }
    if let problem = error as? ConfigError { return problem.description }
    if let problem = error as? RequestPlanError { return problem.description }
    if let failure = error as? KeyStore.Failure { return "The Keychain refused the config (status \(failure.status))." }
    if let network = error as? URLError {
        switch network.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return "This iPhone is offline."
        case .timedOut: return "No answer in time."
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .secureConnectionFailed, .cancelled:   // a refused name check ends the request as cancelled
            return "The server's certificate did not match the name in the config."
        default: return "Not answering. Check the connection."
        }
    }
    if error is DecodingError { return "The answer was not in the expected form." }
    return "Something went wrong: \(Scrub.clean(error.localizedDescription))"
}
