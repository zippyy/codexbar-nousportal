import Foundation

public enum NousPortalProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .nousportal,
            menuBarMetrics: ProviderMenuBarMetricCapabilities(supported: [.automatic, .primary]),
            metadata: ProviderMetadata(
                id: .nousportal,
                displayName: "Nous Portal",
                shortDisplayName: "Nous",
                sessionLabel: "Monthly",
                weeklyLabel: "Credits",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Nous Portal usage",
                cliName: "nousportal",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                dashboardURL: "https://portal.nousresearch.com/billing",
                subscriptionDashboardURL: "https://portal.nousresearch.com/billing",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .nousportal),
                iconResourceName: "ProviderIcon-nousportal",
                color: ProviderColor(red: 0.39, green: 0.32, blue: 0.94),
                confettiPalette: [
                    ProviderColor(hex: 0x6552EF),
                    ProviderColor(hex: 0xAFA6FF),
                    ProviderColor(hex: 0x17151F),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Nous Portal token-cost history is not available." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .oauth],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [NousPortalOAuthFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "nousportal",
                aliases: ["nous"],
                versionDetector: nil))
    }
}

struct NousPortalOAuthFetchStrategy: ProviderFetchStrategy {
    let id = "nousportal.oauth"
    let kind: ProviderFetchKind = .oauth
    private let transport: any ProviderHTTPTransport

    init(transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) {
        self.transport = transport
    }

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        NousPortalAuthReader.hasCredentials(environment: context.env)
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        var credential = try NousPortalAuthReader.load(environment: context.env)

        if NousPortalAuthReader.tokenExpiresSoon(credential) {
            await NousPortalHermesRefresh.refresh(environment: context.env)
            credential = try NousPortalAuthReader.load(environment: context.env)
        }

        do {
            let usage = try await NousPortalUsageFetcher.fetch(
                credential: credential,
                session: self.transport)
            return self.makeResult(usage: usage.toUsageSnapshot(), sourceLabel: "Hermes OAuth")
        } catch NousPortalUsageError.authenticationExpired {
            await NousPortalHermesRefresh.refresh(environment: context.env)
            credential = try NousPortalAuthReader.load(environment: context.env)
            let usage = try await NousPortalUsageFetcher.fetch(
                credential: credential,
                session: self.transport)
            return self.makeResult(usage: usage.toUsageSnapshot(), sourceLabel: "Hermes OAuth")
        }
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}

enum NousPortalHermesRefresh {
    private static let timeoutSeconds: TimeInterval = 20

    static func refresh(environment: [String: String]) async {
        var commandEnvironment = environment
        let loginPATH = LoginShellPathCache.shared.current
        commandEnvironment["PATH"] = PathBuilder.effectivePATH(
            purposes: [.tty, .nodeTooling],
            env: environment,
            loginPATH: loginPATH)
        commandEnvironment["NO_COLOR"] = "1"

        // Let Hermes own refresh-token rotation and auth.json locking. Nous refresh
        // tokens rotate and use reuse detection, so CodexBar intentionally never
        // submits the refresh token itself.
        _ = try? await SubprocessRunner.run(
            binary: "/usr/bin/env",
            arguments: ["hermes", "status"],
            environment: commandEnvironment,
            timeout: self.timeoutSeconds,
            standardInput: FileHandle.nullDevice,
            label: "nousportal-hermes-refresh")
    }
}
