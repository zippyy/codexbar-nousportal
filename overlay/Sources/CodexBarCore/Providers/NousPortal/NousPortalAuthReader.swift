import Foundation

public struct NousPortalCredential: Sendable {
    public let accessToken: String
    public let portalBaseURL: URL
    public let sourcePath: String

    public init(accessToken: String, portalBaseURL: URL, sourcePath: String) {
        self.accessToken = accessToken
        self.portalBaseURL = portalBaseURL
        self.sourcePath = sourcePath
    }
}

public enum NousPortalAuthError: LocalizedError, Sendable {
    case authStoreMissing
    case authStoreUnreadable(String)
    case credentialMissing
    case portalURLInvalid(String)

    public var errorDescription: String? {
        switch self {
        case .authStoreMissing:
            "Hermes auth store not found. Log in to Nous with `hermes portal` or `hermes model`."
        case let .authStoreUnreadable(message):
            "Could not read Hermes Nous authentication: \(message)"
        case .credentialMissing:
            "No Nous Portal OAuth token found in Hermes. Log in with `hermes portal` or `hermes model`."
        case let .portalURLInvalid(value):
            "Hermes contains an invalid Nous Portal URL: \(value)"
        }
    }
}

public enum NousPortalAuthReader {
    private static let defaultPortalBaseURL = "https://portal.nousresearch.com"

    public static func hasCredentials(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool
    {
        (try? self.load(environment: environment)) != nil
    }

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment) throws -> NousPortalCredential
    {
        let paths = self.authStorePaths(environment: environment)
        guard !paths.isEmpty else { throw NousPortalAuthError.authStoreMissing }

        var lastReadError: Error?
        for path in paths {
            do {
                guard let data = try? Data(contentsOf: path) else { continue }
                let object = try JSONSerialization.jsonObject(with: data)
                guard let store = object as? [String: Any] else {
                    throw NousPortalAuthError.authStoreUnreadable("auth.json is not a JSON object")
                }
                if let credential = try self.credential(from: store, path: path, environment: environment) {
                    return credential
                }
            } catch {
                lastReadError = error
            }
        }

        if let lastReadError {
            throw NousPortalAuthError.authStoreUnreadable(lastReadError.localizedDescription)
        }
        if paths.contains(where: { (try? $0.checkResourceIsReachable()) == true }) {
            throw NousPortalAuthError.credentialMissing
        }
        throw NousPortalAuthError.authStoreMissing
    }

    public static func tokenExpiresSoon(
        _ credential: NousPortalCredential,
        within seconds: TimeInterval = 90,
        now: Date = Date()) -> Bool
    {
        guard let expiry = self.jwtExpiry(credential.accessToken) else { return false }
        return expiry.timeIntervalSince(now) <= seconds
    }

    private static func credential(
        from store: [String: Any],
        path: URL,
        environment: [String: String]) throws -> NousPortalCredential?
    {
        if let providers = store["providers"] as? [String: Any],
           let nous = providers["nous"] as? [String: Any],
           let credential = try self.credentialFromState(nous, path: path, environment: environment)
        {
            return credential
        }

        guard let pools = store["credential_pool"] as? [String: Any],
              let entries = pools["nous"] as? [[String: Any]]
        else { return nil }

        let candidates = entries.compactMap { entry -> (credential: NousPortalCredential, expiry: Date?)? in
            do {
                guard let credential = try self.credentialFromState(entry, path: path, environment: environment) else {
                    return nil
                }
                return (credential, self.jwtExpiry(credential.accessToken) ?? self.isoDate(entry["expires_at"]))
            } catch {
                return nil
            }
        }
        return candidates.max { lhs, rhs in
            (lhs.expiry ?? .distantPast) < (rhs.expiry ?? .distantPast)
        }?.credential
    }

    private static func credentialFromState(
        _ state: [String: Any],
        path: URL,
        environment: [String: String]) throws -> NousPortalCredential?
    {
        guard let accessToken = self.nonEmptyString(state["access_token"]) else { return nil }

        let portalString = self.nonEmptyString(environment["HERMES_PORTAL_BASE_URL"])
            ?? self.nonEmptyString(environment["NOUS_PORTAL_BASE_URL"])
            ?? self.nonEmptyString(state["portal_base_url"])
            ?? self.defaultPortalBaseURL

        guard let portalURL = URL(string: portalString),
              let scheme = portalURL.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              portalURL.host != nil
        else {
            throw NousPortalAuthError.portalURLInvalid(portalString)
        }

        return NousPortalCredential(
            accessToken: accessToken,
            portalBaseURL: portalURL,
            sourcePath: path.path)
    }

    private static func authStorePaths(environment: [String: String]) -> [URL] {
        var candidates: [URL] = []
        if let hermesHome = self.nonEmptyString(environment["HERMES_HOME"]) {
            candidates.append(URL(fileURLWithPath: hermesHome, isDirectory: true).appendingPathComponent("auth.json"))
        }

        let home = self.nonEmptyString(environment["HOME"]) ?? NSHomeDirectory()
        if !home.isEmpty {
            candidates.append(
                URL(fileURLWithPath: home, isDirectory: true)
                    .appendingPathComponent(".hermes", isDirectory: true)
                    .appendingPathComponent("auth.json"))
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func jwtExpiry(_ token: String) -> Date? {
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return nil }
        var payload = String(pieces[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data),
              let claims = object as? [String: Any],
              let exp = self.number(claims["exp"])
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private static func isoDate(_ value: Any?) -> Date? {
        guard let text = self.nonEmptyString(value) else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = fractional.date(from: text) { return value }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: text)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
