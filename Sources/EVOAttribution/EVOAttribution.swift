import Foundation
import os.log

#if canImport(UIKit)
import UIKit
#endif

#if canImport(StoreKit)
import StoreKit
#endif

/// A dependency-free client for EVO app-install and purchase attribution.
/// Example: `EVOAttribution.configure(pixelKey: "pk_your_brand_key")`
@available(macOS 10.15, *)
public enum EVOAttribution {
    /// A creator attribution link returned for an install.
    /// Example: `result.install.link?.slug`
    public struct Link: Decodable {
        /// The EVO link identifier.
        /// Example: `let linkId = result.install.link?.id`
        public let id: Int

        /// The attribution link's domain.
        /// Example: `let domain = result.install.link?.domain`
        public let domain: String

        /// The attribution link's path slug.
        /// Example: `let slug = result.install.link?.slug`
        public let slug: String
    }

    /// The attributed creator returned for an install.
    /// Example: `result.install.creator?.name`
    public struct Creator: Decodable {
        /// The creator's EVO identifier.
        /// Example: `let creatorId = result.install.creator?.id`
        public let id: String

        /// The creator's display name, when available.
        /// Example: `let creatorName = result.install.creator?.name`
        public let name: String?
    }

    /// The install record returned by EVO.
    /// Example: `let install = result.install`
    public struct Install: Decodable {
        /// The persistent installation identifier submitted by this SDK.
        /// Example: `let installId = result.install.installId`
        public let installId: String

        /// The recorded mobile platform.
        /// Example: `let platform = result.install.platform`
        public let platform: String

        /// Whether EVO attributed the installation.
        /// Example: `if result.install.attributed { /* attributed */ }`
        public let attributed: Bool

        /// The method EVO used to resolve attribution.
        /// Example: `let method = result.install.resolutionMethod`
        public let resolutionMethod: String

        /// EVO's confidence score for the resolution.
        /// Example: `let confidence = result.install.confidence`
        public let confidence: Double

        /// The matched attribution link, when available.
        /// Example: `let link = result.install.link`
        public let link: Link?

        /// The matched creator code, when available.
        /// Example: `let code = result.install.code`
        public let code: String?

        /// The matched creator, when available.
        /// Example: `let creator = result.install.creator`
        public let creator: Creator?

        private enum CodingKeys: String, CodingKey {
            case installId = "install_id"
            case platform, attributed
            case resolutionMethod = "resolution_method"
            case confidence, link, code, creator
        }
    }

    /// The response returned after EVO accepts an installation.
    /// Example: `let result = await EVOAttribution.trackInstall()`
    public struct InstallResult: Decodable {
        /// Whether EVO accepted the request.
        /// Example: `if result.ok { /* accepted */ }`
        public let ok: Bool

        /// Whether this installation had already been reported.
        /// Example: `let wasAlreadyReported = result.duplicate`
        public let duplicate: Bool

        /// The stored installation and its attribution details.
        /// Example: `let install = result.install`
        public let install: Install
    }

    private enum Metadata {
        static let version = "0.1.0"
    }

    private static let installIdKey = "evo_install_id"
    private static let installReportedKey = "evo_install_reported"
    private static let log = OSLog(subsystem: "co.evomarketing.attribution", category: "sdk")
    private static let defaultEndpoint = URL(string: "https://dialedapi.evomarketing.co")!

    private static var pixelKey: String?
    private static var endpoint = defaultEndpoint
    private static var session = URLSession.shared
    private static var userDefaults = UserDefaults.standard

    /// The SDK version sent with attribution payloads.
    /// Example: `print(EVOAttribution.version)`
    public static let version = Metadata.version

    /// The persistent installation UUID used by EVO and billing connectors.
    /// Example: `Purchases.shared.attribution.setAttributes(["evo_install_id": EVOAttribution.installId])`
    public static var installId: String { persistentInstallId() }

    /// Configures EVO attribution during app startup.
    /// Example: `EVOAttribution.configure(pixelKey: "pk_your_brand_key")`
    public static func configure(
        pixelKey: String,
        endpoint: URL = URL(string: "https://dialedapi.evomarketing.co")!
    ) {
        self.pixelKey = pixelKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
    }

    /// Reports this installation once and retries a failed request on a later call or launch.
    /// Example: `let result = await EVOAttribution.trackInstall(readClipboard: true, code: "JANE10")`
    public static func trackInstall(
        readClipboard: Bool = false,
        code: String? = nil
    ) async -> InstallResult? {
        guard let pixelKey, !pixelKey.isEmpty else {
            report("configure(pixelKey:) must be called before trackInstall")
            return nil
        }
        guard !userDefaults.bool(forKey: installReportedKey) else { return nil }

        let installId = persistentInstallId()
        var payload: [String: Any] = [
            "pixel_key": pixelKey,
            "install_id": installId,
            "platform": "ios",
            "app_version": appVersion(),
            "sdk_version": version,
            "occurred_at": ISO8601DateFormatter().string(from: Date()),
        ]

        if readClipboard, let token = await clipboardToken() {
            payload["clipboard_token"] = token
        }

        if let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            payload["code"] = code
        }

        guard let response = await post(
            path: "api/public/attribution/installs",
            payload: payload
        ) else {
            return nil
        }

        // A 2xx response means the server owns the install. Keep the original
        // behavior and mark it reported even when this SDK cannot decode a
        // future response shape.
        userDefaults.set(true, forKey: installReportedKey)
        do {
            return try JSONDecoder().decode(InstallResult.self, from: response)
        } catch {
            report("Install response decode failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reports a purchase using the persistent install ID without throwing into the host app.
    /// Example: `await EVOAttribution.trackPurchase(transactionId: "order-1", amount: 49.99, sandbox: true)`
    public static func trackPurchase(
        transactionId: String,
        amount: Decimal,
        currency: String = "USD",
        code: String? = nil,
        sandbox: Bool = false
    ) async {
        guard let pixelKey, !pixelKey.isEmpty else {
            report("configure(pixelKey:) must be called before trackPurchase")
            return
        }

        var payload: [String: Any] = [
            "pixel_key": pixelKey,
            "event_type": "purchase",
            "source": "sdk",
            "external_user_id": persistentInstallId(),
            "transaction_id": transactionId,
            "amount": NSDecimalNumber(decimal: amount),
            "currency": currency,
            "sandbox": sandbox,
            "sdk_version": version,
            "occurred_at": ISO8601DateFormatter().string(from: Date()),
        ]

        if let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            payload["code"] = code
        }

        _ = await post(path: "api/public/attribution/events", payload: payload)
    }

    #if canImport(StoreKit)
    /// Reports a StoreKit 2 transaction, automatically identifying App Store sandbox transactions.
    /// Example: `await EVOAttribution.trackPurchase(transaction: transaction, amount: 49.99, currency: "USD")`
    @available(iOS 15.0, macOS 12.0, *)
    public static func trackPurchase(
        transaction: StoreKit.Transaction,
        amount: Decimal,
        currency: String = "USD",
        code: String? = nil
    ) async {
        let sandbox: Bool
        if #available(iOS 16.0, macOS 13.0, *) {
            sandbox = transaction.environment == .sandbox
        } else {
            sandbox = isSandboxEnvironment(transaction.environmentStringRepresentation)
        }

        await trackPurchase(
            transactionId: String(transaction.id),
            amount: amount,
            currency: currency,
            code: code,
            sandbox: sandbox
        )
    }
    #endif

    private static func persistentInstallId() -> String {
        if let existing = userDefaults.string(forKey: installIdKey), !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString.lowercased()
        userDefaults.set(created, forKey: installIdKey)
        return created
    }

    private static func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static func isSandboxEnvironment(_ value: String) -> Bool {
        value.caseInsensitiveCompare("sandbox") == .orderedSame
    }

    private static func clipboardToken() async -> String? {
        #if canImport(UIKit)
        return await MainActor.run {
            let pasteboard = UIPasteboard.general
            guard pasteboard.hasStrings,
                  let value = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  value.hasPrefix("evc_") else {
                return nil
            }
            return value
        }
        #else
        return nil
        #endif
    }

    private static func post(path: String, payload: [String: Any]) async -> Data? {
        do {
            var request = URLRequest(url: endpoint.appendingPathComponent(path))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                report("Attribution request failed with a non-2xx response")
                return nil
            }
            return data
        } catch {
            report("Attribution request failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }.resume()
        }
    }

    private static func report(_ message: String) {
        os_log("%{public}@", log: log, type: .error, message)
    }
}

@available(macOS 10.15, *)
extension EVOAttribution {
    static func configureForTesting(
        pixelKey: String?,
        endpoint: URL,
        session: URLSession,
        userDefaults: UserDefaults
    ) {
        self.pixelKey = pixelKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
        self.session = session
        self.userDefaults = userDefaults
    }

    static func resetForTesting() {
        pixelKey = nil
        endpoint = defaultEndpoint
        session = .shared
        userDefaults = .standard
    }
}
