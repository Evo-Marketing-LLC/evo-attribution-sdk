import Foundation
import XCTest
@testable import EVOAttribution

@available(macOS 10.15, *)
final class EVOAttributionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var session: URLSession!
    private let endpoint = URL(string: "https://sdk-test.invalid")!

    override func setUp() {
        super.setUp()
        suiteName = "EVOAttributionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        StubURLProtocol.handler = nil

        EVOAttribution.configureForTesting(
            pixelKey: "pk_test",
            endpoint: endpoint,
            session: session,
            userDefaults: defaults
        )
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suiteName)
        EVOAttribution.resetForTesting()
        session = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testInstallIdPersistsAcrossSDKReconfiguration() {
        let first = EVOAttribution.installId

        EVOAttribution.configureForTesting(
            pixelKey: "pk_test",
            endpoint: endpoint,
            session: session,
            userDefaults: defaults
        )
        let second = EVOAttribution.installId

        XCTAssertEqual(second, first)
        XCTAssertEqual(defaults.string(forKey: "evo_install_id"), first)
        XCTAssertNotNil(UUID(uuidString: first))
    }

    func testTrackInstallSendsExpectedPayloadIncludingCodeAndVersion() async throws {
        var capturedRequest: URLRequest?
        var capturedPayload: [String: Any]?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            let payload = try XCTUnwrap(Self.jsonBody(from: request))
            capturedPayload = payload
            let installId = try XCTUnwrap(payload["install_id"] as? String)
            let body = """
            {
              "ok": true,
              "duplicate": false,
              "install": {
                "install_id": "\(installId)",
                "platform": "ios",
                "attributed": true,
                "resolution_method": "code",
                "confidence": 0.9,
                "link": null,
                "code": "jane-10",
                "creator": null
              }
            }
            """.data(using: .utf8)!
            return (Self.response(for: request, statusCode: 201), body)
        }

        let result = await EVOAttribution.trackInstall(code: "  jane-10  ")

        let request = try XCTUnwrap(capturedRequest)
        let payload = try XCTUnwrap(capturedPayload)
        XCTAssertEqual(request.url?.path, "/api/public/attribution/installs")
        XCTAssertEqual(payload["pixel_key"] as? String, "pk_test")
        XCTAssertEqual(payload["install_id"] as? String, EVOAttribution.installId)
        XCTAssertEqual(payload["platform"] as? String, "ios")
        XCTAssertEqual(payload["code"] as? String, "jane-10")
        XCTAssertEqual(payload["sdk_version"] as? String, EVOAttribution.version)
        XCTAssertEqual(result?.install.resolutionMethod, "code")
        XCTAssertTrue(defaults.bool(forKey: "evo_install_reported"))
    }

    func testTrackPurchaseSendsPersistentInstallIdCodeAndVersion() async throws {
        var capturedRequest: URLRequest?
        var capturedPayload: [String: Any]?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            capturedPayload = try XCTUnwrap(Self.jsonBody(from: request))
            return (Self.response(for: request, statusCode: 200), Data("{}".utf8))
        }

        let installId = EVOAttribution.installId
        await EVOAttribution.trackPurchase(
            transactionId: "order-123",
            amount: Decimal(string: "49.99")!,
            currency: "usd",
            code: " JANE10 ",
            sandbox: true
        )

        let request = try XCTUnwrap(capturedRequest)
        let payload = try XCTUnwrap(capturedPayload)
        XCTAssertEqual(request.url?.path, "/api/public/attribution/events")
        XCTAssertEqual(payload["pixel_key"] as? String, "pk_test")
        XCTAssertEqual(payload["external_user_id"] as? String, installId)
        XCTAssertEqual(payload["event_type"] as? String, "purchase")
        XCTAssertEqual(payload["source"] as? String, "sdk")
        XCTAssertEqual(payload["transaction_id"] as? String, "order-123")
        XCTAssertEqual(try XCTUnwrap(payload["amount"] as? Double), 49.99, accuracy: 0.001)
        XCTAssertEqual(payload["currency"] as? String, "usd")
        XCTAssertEqual(payload["code"] as? String, "JANE10")
        XCTAssertEqual(payload["sandbox"] as? Bool, true)
        XCTAssertEqual(payload["sdk_version"] as? String, EVOAttribution.version)
    }

    func testTrackPurchaseDefaultsSandboxToFalse() async throws {
        var capturedPayload: [String: Any]?
        StubURLProtocol.handler = { request in
            capturedPayload = try XCTUnwrap(Self.jsonBody(from: request))
            return (Self.response(for: request, statusCode: 200), Data("{}".utf8))
        }

        await EVOAttribution.trackPurchase(transactionId: "production-order", amount: 10)

        let payload = try XCTUnwrap(capturedPayload)
        XCTAssertEqual(payload["sandbox"] as? Bool, false)
    }

    func testStoreKitEnvironmentCompatibilityMapping() {
        XCTAssertTrue(EVOAttribution.isSandboxEnvironment("Sandbox"))
        XCTAssertTrue(EVOAttribution.isSandboxEnvironment("sandbox"))
        XCTAssertFalse(EVOAttribution.isSandboxEnvironment("Production"))
        XCTAssertFalse(EVOAttribution.isSandboxEnvironment("Xcode"))
    }

    func testNetworkFailuresNeverEscapeAndInstallRemainsPending() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let result = await EVOAttribution.trackInstall()
        await EVOAttribution.trackPurchase(transactionId: "offline-order", amount: 1)

        XCTAssertNil(result)
        XCTAssertFalse(defaults.bool(forKey: "evo_install_reported"))
    }

    func testSuccessfulUndecodableInstallIsMarkedReportedAndDoesNotRetry() async {
        var requestCount = 0
        StubURLProtocol.handler = { request in
            requestCount += 1
            return (Self.response(for: request, statusCode: 200), Data("not-json".utf8))
        }

        let firstResult = await EVOAttribution.trackInstall()
        let secondResult = await EVOAttribution.trackInstall()

        XCTAssertNil(firstResult)
        XCTAssertNil(secondResult)
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(defaults.bool(forKey: "evo_install_reported"))
    }

    func testCallsBeforeConfigureNeverThrow() async {
        EVOAttribution.configureForTesting(
            pixelKey: nil,
            endpoint: endpoint,
            session: session,
            userDefaults: defaults
        )

        let result = await EVOAttribution.trackInstall()
        await EVOAttribution.trackPurchase(transactionId: "order", amount: 1)

        XCTAssertNil(result)
    }

    private static func jsonBody(from request: URLRequest) -> [String: Any]? {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }

            var body = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
            defer { buffer.deallocate() }

            while true {
                let count = stream.read(buffer, maxLength: 4_096)
                guard count >= 0 else { return nil }
                guard count > 0 else { break }
                body.append(buffer, count: count)
            }
            data = body
        } else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func response(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
