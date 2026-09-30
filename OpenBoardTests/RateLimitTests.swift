import Testing
import Foundation
@testable import OpenBoard

/// Answers every request from a queue of status codes (200 once it's empty),
/// counting requests. Only `RateLimitTests` uses it, one test at a time.
final class StatusQueueProtocol: URLProtocol {
    nonisolated(unsafe) static var statuses: [Int] = []
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let status = Self.statuses.isEmpty ? 200 : Self.statuses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: status == 200 ? Self.body : Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Rate limiting", .serialized)
struct RateLimitTests {
    /// US Chess answers 429 for a while after ~100 requests a minute; a request
    /// waits and retries instead of failing the screen.
    @Test func retriesAfterTooManyRequests() async throws {
        StatusQueueProtocol.statuses = [429, 429]
        StatusQueueProtocol.body = try fixture("sample_member")
        StatusQueueProtocol.requestCount = 0
        let service = LiveRatingsService(protocolClasses: [StatusQueueProtocol.self],
                                         rateLimitBackoff: [0, 0, 0, 0])

        let results = try await service.search("90000001")

        #expect(results.first?.id == "90000001")
        #expect(StatusQueueProtocol.requestCount == 3)
    }

    @Test func givesUpWithAClearMessage() async throws {
        StatusQueueProtocol.statuses = Array(repeating: 429, count: 10)
        StatusQueueProtocol.requestCount = 0
        let service = LiveRatingsService(protocolClasses: [StatusQueueProtocol.self],
                                         rateLimitBackoff: [0, 0, 0])

        do {
            _ = try await service.search("90000001")
            Issue.record("Expected RatingsError.rateLimited")
        } catch RatingsError.rateLimited {
            #expect(RatingsError.rateLimited.errorDescription?.contains("too many requests") == true)
        }
        #expect(StatusQueueProtocol.requestCount == 3) // one try per backoff entry
    }
}
