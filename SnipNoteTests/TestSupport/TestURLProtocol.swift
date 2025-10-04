import Foundation

/// URLProtocol subclass that supplies deterministic responses for unit tests.
final class TestURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        let error: Error?

        static func success(statusCode: Int = 200, headers: [String: String] = [:], body: Data = Data()) -> Response {
            Response(statusCode: statusCode, headers: headers, body: body, error: nil)
        }

        static func failure(_ error: Error) -> Response {
            Response(statusCode: 0, headers: [:], body: Data(), error: error)
        }
    }

    struct RecordedRequest {
        let request: URLRequest
        let body: Data?
    }

    private struct Stub {
        let matcher: (@Sendable (URLRequest) -> Bool)?
        let response: Response
    }

    private static let queue = DispatchQueue(label: "TestURLProtocol.queue")
    private static var stubs: [Stub] = []
    private static var recordedRequests: [RecordedRequest] = []

    // MARK: - Registration

    static func register() {
        URLProtocol.registerClass(TestURLProtocol.self)
    }

    static func reset() {
        queue.sync {
            stubs.removeAll()
            recordedRequests.removeAll()
        }
    }

    static func addStub(matcher: (@Sendable (URLRequest) -> Bool)? = nil, response: Response) {
        queue.sync {
            stubs.append(Stub(matcher: matcher, response: response))
        }
    }

    static func recordedRequests(matching predicate: (@Sendable (URLRequest) -> Bool)? = nil) -> [RecordedRequest] {
        queue.sync {
            guard let predicate else { return recordedRequests }
            return recordedRequests.filter { predicate($0.request) }
        }
    }

    static func requests(matching predicate: (@Sendable (URLRequest) -> Bool)? = nil) -> [URLRequest] {
        recordedRequests(matching: predicate).map { $0.request }
    }

    // MARK: - URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let (stub, index) = Self.dequeueStub(for: request) else {
            fatalError("No stub available for request: \(request.url?.absoluteString ?? "<unknown>")")
        }

        Self.record(request)

        if let error = stub.response.error {
            client?.urlProtocol(self, didFailWithError: error)
            Self.removeStub(at: index)
            return
        }

        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.response.headers
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !stub.response.body.isEmpty {
            client?.urlProtocol(self, didLoad: stub.response.body)
        }
        client?.urlProtocolDidFinishLoading(self)

        Self.removeStub(at: index)
    }

    override func stopLoading() {
        // No-op
    }

    // MARK: - Internal helpers

    private static func dequeueStub(for request: URLRequest) -> (Stub, Int)? {
        queue.sync {
            if let idx = stubs.firstIndex(where: { stub in
                guard let matcher = stub.matcher else { return true }
                return matcher(request)
            }) {
                return (stubs[idx], idx)
            }
            return nil
        }
    }

    private static func removeStub(at index: Int) {
        queue.sync {
            stubs.remove(at: index)
        }
    }

    private static func record(_ request: URLRequest) {
        let body: Data?
        if let data = request.httpBody {
            body = data
        } else if let stream = request.httpBodyStream {
            body = read(from: stream)
        } else {
            body = nil
        }

        queue.sync {
            recordedRequests.append(RecordedRequest(request: request, body: body))
        }
    }

    private static func read(from stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }

        let bufferSize = 16_384
        var data = Data()
        while stream.hasBytesAvailable {
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read < 0 {
                return nil
            }
            if read == 0 { break }
            data.append(buffer, count: read)
        }

        return data
    }
}
