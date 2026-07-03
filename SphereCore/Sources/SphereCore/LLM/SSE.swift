import Foundation

public enum SSE {
    /// Splits a Server-Sent Events byte stream into the payloads of its
    /// `data:` lines.
    ///
    /// Lines are assembled at the byte level (split on `\n`, trailing `\r`
    /// stripped) and only then UTF-8 decoded, so multi-byte characters and
    /// SSE lines that straddle network-chunk boundaries can never be torn.
    /// Non-data lines (`event:`, comments, heartbeats) and empty payloads are
    /// skipped. Callers parse the payload (JSON, `[DONE]`, etc.).
    public static func dataLines(
        from bytes: AsyncThrowingStream<UInt8, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var line: [UInt8] = []
                do {
                    for try await byte in bytes {
                        if byte == 0x0A {
                            if let payload = payload(fromLine: line) {
                                continuation.yield(payload)
                            }
                            line.removeAll(keepingCapacity: true)
                        } else {
                            line.append(byte)
                        }
                    }
                    if let payload = payload(fromLine: line) {
                        continuation.yield(payload)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func payload(fromLine rawLine: [UInt8]) -> String? {
        var line = rawLine
        if line.last == 0x0D { line.removeLast() }
        guard let text = String(bytes: line, encoding: .utf8),
              text.hasPrefix("data:")
        else { return nil }
        let payload = text.dropFirst(5).trimmingCharacters(in: .whitespaces)
        return payload.isEmpty ? nil : payload
    }
}
