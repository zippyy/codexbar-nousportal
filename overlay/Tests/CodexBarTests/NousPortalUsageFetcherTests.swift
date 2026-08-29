import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct NousPortalUsageFetcherTests {
    @Test
    func `maps Plus credits into monthly usage`() throws {
        let json = """
        {
          "user": { "email": "user@example.com" },
          "organisation": { "id": "org_1", "slug": "personal", "name": "Personal" },
          "subscription": {
            "plan": "Plus",
            "tier": 2,
            "monthly_charge": 20.0,
            "monthly_credits": 22.0,
            "current_period_end": "2026-09-14T12:00:00Z",
            "credits_remaining": 13.2,
            "rollover_credits": 1.5
          },
          "paid_service_access": {
            "allowed": true,
            "paid_access": true,
            "subscription_credits_remaining": 13.2,
            "purchased_credits_remaining": 3.0,
            "total_usable_credits": 16.2,
            "member_spend_cap_usd": 50.0,
            "member_spend_usd": 8.8
          }
        }
        """
        let now = Date(timeIntervalSince1970: 1_787_990_400)
        let snapshot = try NousPortalUsageFetcher._parseForTesting(Data(json.utf8), now: now)
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.plan == "Plus")
        #expect(snapshot.monthlyCredits == 22.0)
        #expect(snapshot.subscriptionCreditsRemaining == 13.2)
        #expect(snapshot.purchasedCreditsRemaining == 3.0)
        #expect(snapshot.totalUsableCredits == 16.2)
        #expect(abs((usage.primary?.usedPercent ?? -1) - 40.0) < 0.0001)
        #expect(abs((usage.providerCost?.used ?? -1) - 8.8) < 0.0001)
        #expect(usage.providerCost?.limit == 22.0)
        #expect(usage.providerCost?.balance == 16.2)
        #expect(usage.identity?.accountEmail == "user@example.com")
        #expect(usage.identity?.accountOrganization == "Personal")
    }

    @Test
    func `rollover above allowance avoids misleading percentage`() throws {
        let json = """
        {
          "subscription": {
            "plan": "Plus",
            "monthly_credits": 22.0,
            "credits_remaining": 29.0,
            "rollover_credits": 7.0
          },
          "paid_service_access": {
            "allowed": true,
            "subscription_credits_remaining": 29.0,
            "purchased_credits_remaining": 0.0,
            "total_usable_credits": 29.0
          }
        }
        """

        let snapshot = try NousPortalUsageFetcher._parseForTesting(Data(json.utf8))
        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary == nil)
        #expect(snapshot.rolloverCredits == 7.0)
        #expect(snapshot.totalUsableCredits == 29.0)
    }

    @Test
    func `invalid response reports parse error`() {
        let json = """
        { "subscription": "not-an-object" }
        """

        #expect {
            _ = try NousPortalUsageFetcher._parseForTesting(Data(json.utf8))
        } throws: { error in
            guard case NousPortalUsageError.invalidResponse = error else { return false }
            return true
        }
    }
}
