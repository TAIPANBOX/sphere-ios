import Foundation
@testable import SphereCore

/// Canned-response transport. `chunkSize` slices the response into small
/// byte chunks to simulate network fragmentation (including splits in the
/// middle of UTF-8 sequences and SSE lines).
final class StubTransport: LLMTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    let status: Int
    let responseBody: Data
    let chunkSize: Int

    init(status: Int = 200, body: String, chunkSize: Int = 7) {
        self.status = status
        self.responseBody = Data(body.utf8)
        self.chunkSize = chunkSize
    }

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    var lastRequestBody: JSONValue? {
        requests.last?.httpBody.flatMap(JSONValue.decoded(from:))
    }

    func stream(_ request: URLRequest) async throws -> (status: Int, bytes: AsyncThrowingStream<UInt8, Error>) {
        lock.withLock { _requests.append(request) }
        let body = responseBody
        let chunkSize = chunkSize
        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            var offset = 0
            while offset < body.count {
                let end = min(offset + chunkSize, body.count)
                for byte in body[offset..<end] {
                    continuation.yield(byte)
                }
                offset = end
            }
            continuation.finish()
        }
        return (status, stream)
    }

    func post(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { _requests.append(request) }
        return (status, responseBody)
    }
}

func collectEvents(_ stream: AsyncThrowingStream<LLMEvent, Error>) async throws -> [LLMEvent] {
    var events: [LLMEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}
