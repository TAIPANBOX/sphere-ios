import Foundation

/// Thin HTTP abstraction so engines can be tested against canned byte
/// streams without touching the network.
public protocol LLMTransport: Sendable {
    /// POSTs `request` and returns the HTTP status plus the response body as
    /// a byte stream (SSE for 2xx, error JSON otherwise).
    func stream(_ request: URLRequest) async throws -> (status: Int, bytes: AsyncThrowingStream<UInt8, Error>)

    /// POSTs `request` and returns the HTTP status plus the full body.
    func post(_ request: URLRequest) async throws -> (status: Int, body: Data)
}

public struct URLSessionTransport: LLMTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func stream(_ request: URLRequest) async throws -> (status: Int, bytes: AsyncThrowingStream<UInt8, Error>) {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let stream = AsyncThrowingStream<UInt8, Error> { continuation in
                let task = Task {
                    do {
                        for try await byte in bytes {
                            continuation.yield(byte)
                        }
                        continuation.finish()
                    } catch let error as URLError where error.isConnectionFailure {
                        continuation.finish(throwing: LLMError.backendUnavailable)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            return (status, stream)
        } catch let error as URLError where error.isConnectionFailure {
            throw LLMError.backendUnavailable
        }
    }

    public func post(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        do {
            let (data, response) = try await session.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch let error as URLError where error.isConnectionFailure {
            throw LLMError.backendUnavailable
        }
    }
}

extension URLError {
    var isConnectionFailure: Bool {
        switch code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .networkConnectionLost, .timedOut:
            true
        default:
            false
        }
    }
}

enum LLMHTTP {
    /// Drains a non-2xx body stream and extracts `error.message` from the
    /// provider's error JSON, falling back to a generic HTTP message.
    static func errorMessage(status: Int, bytes: AsyncThrowingStream<UInt8, Error>) async -> String {
        var data = Data()
        do {
            for try await byte in bytes { data.append(byte) }
        } catch {}
        return errorMessage(status: status, body: data)
    }

    static func errorMessage(status: Int, body: Data) -> String {
        if let json = JSONValue.decoded(from: body),
           let message = json["error"]?["message"]?.stringValue {
            return message
        }
        return "HTTP \(status)"
    }

    static func makeRequest(url: URL, headers: [String: String], body: JSONValue) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try body.encodedData()
        return request
    }
}
