import CodexBarCore
import Foundation

struct NousPortalProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .nousportal

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            context.store.sourceLabel(for: context.provider)
        }
    }

    @MainActor
    func defaultSourceLabel(context _: ProviderSourceLabelContext) -> String? {
        "Hermes OAuth"
    }
}
