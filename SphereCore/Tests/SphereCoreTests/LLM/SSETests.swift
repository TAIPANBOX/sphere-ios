import Foundation
import Testing
@testable import SphereCore

@Suite("SSE")
struct SSETests {
    private func stream(chunks: [String]) -> AsyncThrowingStream<UInt8, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                for byte in Data(chunk.utf8) {
                    continuation.yield(byte)
                }
            }
            continuation.finish()
        }
    }

    private func collect(_ chunks: [String]) async throws -> [String] {
        var payloads: [String] = []
        for try await payload in SSE.dataLines(from: stream(chunks: chunks)) {
            payloads.append(payload)
        }
        return payloads
    }

    @Test func extractsDataPayloads() async throws {
        let payloads = try await collect([
            "event: message_start\ndata: {\"a\":1}\n\ndata: {\"b\":2}\n\n",
        ])
        #expect(payloads == ["{\"a\":1}", "{\"b\":2}"])
    }

    @Test func survivesLineSplitAcrossChunks() async throws {
        let payloads = try await collect([
            "data: {\"hel", "lo\":true}\n",
        ])
        #expect(payloads == ["{\"hello\":true}"])
    }

    @Test func survivesUtf8SplitAcrossChunks() async throws {
        // "Привіт" — split the byte stream inside a two-byte Cyrillic char.
        let full = "data: {\"text\":\"Привіт\"}\n"
        let bytes = Array(Data(full.utf8))
        let cut = bytes.count - 6
        let first = String(decoding: bytes[0..<cut], as: UTF8.self)  // may be lossy; feed raw bytes instead
        _ = first

        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            for byte in bytes[0..<cut] { continuation.yield(byte) }
            for byte in bytes[cut...] { continuation.yield(byte) }
            continuation.finish()
        }
        var payloads: [String] = []
        for try await payload in SSE.dataLines(from: stream) {
            payloads.append(payload)
        }
        #expect(payloads == ["{\"text\":\"Привіт\"}"])
    }

    @Test func stripsCarriageReturns() async throws {
        let payloads = try await collect(["data: one\r\ndata: two\r\n"])
        #expect(payloads == ["one", "two"])
    }

    @Test func skipsCommentsHeartbeatsAndEmptyData() async throws {
        let payloads = try await collect([
            ": keepalive\n\ndata: \n\nevent: ping\ndata: real\n\n",
        ])
        #expect(payloads == ["real"])
    }

    @Test func flushesTrailingLineWithoutNewline() async throws {
        let payloads = try await collect(["data: [DONE]"])
        #expect(payloads == ["[DONE]"])
    }
}
