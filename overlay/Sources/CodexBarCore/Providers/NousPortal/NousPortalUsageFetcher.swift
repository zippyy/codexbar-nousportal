import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct NousPortalUsageSnapshot: Sendable {
    public let plan: String?
    public let email: String?
    public let organization: String?
    public let monthlyCredits: Double?
    public let subscriptionCreditsRemaining: Double?
    public let purchasedCreditsRemaining: Double?
    public let totalUsableCredits: Double?
    public let rolloverCredits: Double?
    public let renewsAt: Date?
    public let paidAccess: Bool?
    public let memberSpendCapUSD: Double?
    public let memberSpendUSD: Double?
    public let updatedAt: Date

    public init(
        plan: String?,
        email: String?,
        organization: String?,
        monthlyCredits: Double?,
        subscriptionCreditsRemaining: Double?,
        purchasedCreditsRemaining: Double?,
        totalUsableCredits: Double?,
        rolloverCredits: Double?,
        renewsAt: Date?,
        paidAccess: Bool?,
        memberSpendCapUSD: Double?,
        memberSpendUSD: Double?,
        updatedAt: Date)
    {
        self.plan = plan
        self.email = email
        self.organization = organization
        self.monthlyCredits = monthlyCredits
        self.subscriptionCreditsRemaining = subscriptionCreditsRemaining
        self.purchasedCreditsRemaining = purchasedCreditsRemaining
        self.totalUsableCredits = totalUsableCredits
        self.rolloverCredits = rolloverCredits
        self.renewsAt = renewsAt
        self.paidAccess = paidAccess
        self.memberSpendCapUSD = memberSpendCapUSD
        self.memberSpendUSD = memberSpendUSD
        self.updatedAt = updatedAt
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let monthlyRemaining = self.subscriptionCreditsRemaining
        let monthlyWindow: RateWindow? = if let allowance = self.monthlyCredits,
                                            allowance.isFinite,
                                            allowance > 0,
                                            let remaining = monthlyRemaining,
                                            remaining.isFinite,
                                            remaining <= allowance
        {
            RateWindow(
                usedPercent: max(0, min(100, ((allowance - remaining) / allowance) * 100)),
                windowMinutes: ProviderPaceCapability.monthlyWindowSentinelMinutes,
                resetsAt: self.renewsAt,
                resetDescription: nil)
        } else {
            nil
        }

        let providerCost: ProviderCostSnapshot? = if let allowance = self.monthlyCredits,
                                                     allowance.isFinite,
                                                     allowance > 0,
                                                     let remaining = monthlyRemaining,
                                                     remaining.isFinite
        {
            ProviderCostSnapshot(
                used: max(0, allowance - min(allowance, remaining)),
                limit: allowance,
                currencyCode: "USD",
                period: "Monthly credits",
                resetsAt: self.renewsAt,
                balance: self.totalUsableCredits,
                updatedAt: self.updatedAt)
        } else {
            nil
        }

        var rows: [ProviderDetailSection.Row] = []
        if let plan = self.plan {
            rows.append(.makeRow(label: "Plan", value: plan))
        }
        if let value = self.monthlyCredits {
            rows.append(.makeRow(label: "Monthly allowance", value: Self.usd(value)))
        }
        if let value = self.subscriptionCreditsRemaining {
            rows.append(.makeRow(label: "Subscription remaining", value: Self.usd(value)))
        }
        if let value = self.purchasedCreditsRemaining {
            rows.append(.makeRow(label: "Top-up remaining", value: Self.usd(value)))
        }
        if let value = self.totalUsableCredits {
            rows.append(.makeRow(label: "Total usable", value: Self.usd(value)))
        }
        if let value = self.rolloverCredits, value > 0 {
            rows.append(.makeRow(label: "Rollover", value: Self.usd(value)))
        }
        if let cap = self.memberSpendCapUSD {
            let secondary = self.memberSpendUSD.map { "\(Self.usd($0)) used" }
            rows.append(.makeRow(label: "Member spend cap", value: Self.usd(cap), secondaryValue: secondary))
        }
        if let paidAccess = self.paidAccess {
            rows.append(.makeRow(label: "Access", value: paidAccess ? "Active" : "Depleted"))
        }

        let details = rows.isEmpty ? [] : [ProviderDetailSection.makeSection(title: "Nous Portal", rows: rows)]
        let identity = ProviderIdentitySnapshot(
            providerID: .nousportal,
            accountEmail: self.email,
            accountOrganization: self.organization,
            loginMethod: "Hermes OAuth")

        return UsageSnapshot(
            primary: monthlyWindow,
            secondary: nil,
            providerCost: providerCost,
            details: details,
            subscriptionRenewsAt: self.renewsAt,
            updatedAt: self.updatedAt,
            identity: identity,
            dataConfidence: .exact)
    }

    private static func usd(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

public enum NousPortalUsageError: LocalizedError, Sendable {
    case authenticationExpired
    case network(String)
    case api(statusCode: Int)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .authenticationExpired:
            "Nous Portal OAuth expired. Run `hermes portal` or `hermes model` to sign in again."
        case let .network(message):
            "Nous Portal network error: \(message)"
        case let .api(statusCode):
            "Nous Portal returned HTTP \(statusCode)."
        case let .invalidResponse(message):
            "Could not parse Nous Portal usage: \(message)"
        }
    }
}

public enum NousPortalUsageFetcher {
    private static let timeoutSeconds: TimeInterval = 12

    public static func fetch(
        credential: NousPortalCredential,
        session transport: any ProviderHTTPTransport = ProviderHTTPClient.shared,
        now: Date = Date()) async throws -> NousPortalUsageSnapshot
    {
        let accountURL = credential.portalBaseURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("oauth", isDirectory: true)
            .appendingPathComponent("account")

        var request = URLRequest(url: accountURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.timeoutSeconds

        let response: ProviderHTTPResponse
        do {
            response = try await transport.response(for: request)
        } catch {
            throw NousPortalUsageError.network(error.localizedDescription)
        }

        if response.statusCode == 401 {
            throw NousPortalUsageError.authenticationExpired
        }
        guard response.statusCode == 200 else {
            throw NousPortalUsageError.api(statusCode: response.statusCode)
        }
        return try self.parse(data: response.data, now: now)
    }

    static func _parseForTesting(_ data: Data, now: Date = Date()) throws -> NousPortalUsageSnapshot {
        try self.parse(data: data, now: now)
    }

    private static func parse(data: Data, now: Date) throws -> NousPortalUsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response: AccountResponse
        do {
            response = try decoder.decode(AccountResponse.self, from: data)
        } catch {
            throw NousPortalUsageError.invalidResponse(error.localizedDescription)
        }

        let subscriptionRemaining = response.subscription?.creditsRemaining
            ?? response.paidServiceAccess?.subscriptionCreditsRemaining
        let paidAccess = response.paidServiceAccess?.allowed
            ?? response.paidServiceAccess?.paidAccess

        return NousPortalUsageSnapshot(
            plan: response.subscription?.plan,
            email: response.user?.email,
            organization: response.organisation?.name,
            monthlyCredits: response.subscription?.monthlyCredits,
            subscriptionCreditsRemaining: subscriptionRemaining,
            purchasedCreditsRemaining: response.paidServiceAccess?.purchasedCreditsRemaining,
            totalUsableCredits: response.paidServiceAccess?.totalUsableCredits,
            rolloverCredits: response.subscription?.rolloverCredits,
            renewsAt: Self.parseDate(response.subscription?.currentPeriodEnd),
            paidAccess: paidAccess,
            memberSpendCapUSD: response.paidServiceAccess?.memberSpendCapUsd,
            memberSpendUSD: response.paidServiceAccess?.memberSpendUsd,
            updatedAt: now)
    }

    private static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = fractional.date(from: text) { return value }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: text)
    }
}

private struct AccountResponse: Decodable {
    let user: AccountUser?
    let organisation: AccountOrganisation?
    let subscription: AccountSubscription?
    let paidServiceAccess: PaidServiceAccess?
}

private struct AccountUser: Decodable {
    let email: String?
}

private struct AccountOrganisation: Decodable {
    let name: String?
}

private struct AccountSubscription: Decodable {
    let plan: String?
    let monthlyCredits: Double?
    let currentPeriodEnd: String?
    let creditsRemaining: Double?
    let rolloverCredits: Double?
}

private struct PaidServiceAccess: Decodable {
    let allowed: Bool?
    let paidAccess: Bool?
    let subscriptionCreditsRemaining: Double?
    let purchasedCreditsRemaining: Double?
    let totalUsableCredits: Double?
    let memberSpendCapUsd: Double?
    let memberSpendUsd: Double?
}
