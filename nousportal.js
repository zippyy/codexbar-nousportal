const NOUS_PORTAL_PLUGIN_BUILD = "0.2.1";
const DEFAULT_HELPER_URL = "http://127.0.0.1:38417";

defineProvider({
  id: "nous-portal",
  name: "Nous Portal",
  topLevel: true,
  icon: { monogram: "N", tint: "#6C5CE7" },
  endpoints: [{ setting: "HELPER_URL", policy: "https-or-loopback-http" }],
  settings: [
    {
      key: "HELPER_URL",
      title: "Helper URL",
      subtitle: `Use ${DEFAULT_HELPER_URL} with the companion helper.`,
      type: "plain",
    },
  ],
  capabilities: ["http-status"],

  async fetchUsage(ctx) {
    const configuredURL = String(ctx.settings.get("HELPER_URL") || "").trim();
    if (!configuredURL) {
      throw ctx.fail.missingCredential(
        `Nous Portal helper URL is not configured. Set Helper URL to ${DEFAULT_HELPER_URL}, install the companion helper, then refresh.`
      );
    }

    const helperURL = configuredURL.replace(/\/+$/, "");
    const response = await ctx.http.getJSON(`${helperURL}/v1/account`);

    if (response.status === 401 || response.status === 403) {
      const detail = response.json?.error ? ` ${String(response.json.error)}` : "";
      throw ctx.fail.authenticationExpired(
        `[${NOUS_PORTAL_PLUGIN_BUILD}] Hermes Nous authentication needs attention.${detail} Run \`hermes model\` or \`hermes status\`, then refresh Nous Portal.`
      );
    }

    if (response.status === 429) {
      const retryAfter = Number(response.headers?.["retry-after"] || 1);
      throw ctx.fail.rateLimited("Nous Portal rate limit reached", {
        retryAfterSeconds: Number.isFinite(retryAfter) ? retryAfter : 1,
      });
    }

    if (response.status === 502 || response.status === 503 || response.status === 504) {
      const detail = response.json?.error ? `: ${String(response.json.error)}` : "";
      throw ctx.fail.providerUnavailable(`Nous Portal helper unavailable${detail}`);
    }

    if (response.status < 200 || response.status >= 300) {
      const detail = response.json?.error ? `: ${String(response.json.error)}` : "";
      throw ctx.fail.apiFailure(`Nous Portal helper returned HTTP ${response.status}${detail}`);
    }

    const root = response.json || {};
    const subscription = root.subscription && typeof root.subscription === "object" ? root.subscription : {};
    const access = root.paid_service_access && typeof root.paid_service_access === "object" ? root.paid_service_access : {};
    const user = root.user && typeof root.user === "object" ? root.user : {};
    const organisation = root.organisation && typeof root.organisation === "object" ? root.organisation : {};

    const finite = (value) => {
      const number = Number(value);
      return Number.isFinite(number) ? number : null;
    };

    const usd = (value) => (value == null ? null : ctx.format.usd(value));
    const rows = [];

    const plan = typeof subscription.plan === "string" && subscription.plan.trim()
      ? subscription.plan.trim()
      : null;
    const monthlyAllowance = finite(subscription.monthly_credits);
    const subscriptionRemaining = finite(
      access.subscription_credits_remaining ?? subscription.credits_remaining
    );
    const topUpRemaining = finite(access.purchased_credits_remaining);
    const totalUsable = finite(access.total_usable_credits);
    const rollover = finite(subscription.rollover_credits);
    const monthlyCharge = finite(subscription.monthly_charge ?? access.subscription_monthly_charge);
    const memberSpend = finite(access.member_spend_usd);
    const memberSpendCap = finite(access.member_spend_cap_usd);
    const memberSpendCapRemaining = finite(access.member_spend_cap_remaining_usd);

    if (plan) rows.push({ label: "Plan", value: plan });
    if (monthlyCharge != null) rows.push({ label: "Monthly price", value: usd(monthlyCharge) });
    if (monthlyAllowance != null) rows.push({ label: "Monthly allowance", value: usd(monthlyAllowance) });
    if (subscriptionRemaining != null) rows.push({ label: "Subscription remaining", value: usd(subscriptionRemaining) });
    if (topUpRemaining != null) rows.push({ label: "Top-up remaining", value: usd(topUpRemaining) });
    if (totalUsable != null) rows.push({ label: "Total usable", value: usd(totalUsable) });
    if (rollover != null && rollover > 0) rows.push({ label: "Rollover", value: usd(rollover) });
    if (memberSpend != null) rows.push({ label: "Member spend", value: usd(memberSpend) });
    if (memberSpendCap != null) rows.push({ label: "Member spend cap", value: usd(memberSpendCap) });
    if (memberSpendCapRemaining != null) rows.push({ label: "Spend-cap remaining", value: usd(memberSpendCapRemaining) });

    if (access.member_spend_cap_exceeded === true) {
      rows.push({ label: "Access", value: "Paused — member spend cap exceeded" });
    } else if (access.allowed === false || access.paid_access === false) {
      rows.push({ label: "Access", value: access.reason ? String(access.reason) : "Unavailable" });
    } else if (access.allowed === true || access.paid_access === true) {
      rows.push({ label: "Access", value: "Active" });
    }

    const renewal = subscription.current_period_end
      ? ctx.date.iso(String(subscription.current_period_end))
      : undefined;

    if (renewal) {
      rows.push({ label: "Renews", value: ctx.format.monthDay(renewal) });
    }

    const canShowMonthlyPercent =
      monthlyAllowance != null &&
      monthlyAllowance > 0 &&
      subscriptionRemaining != null &&
      subscriptionRemaining >= 0 &&
      subscriptionRemaining <= monthlyAllowance;

    const primary = canShowMonthlyPercent
      ? {
          usedPercent: ctx.pct(monthlyAllowance - subscriptionRemaining, monthlyAllowance),
          resetsAt: renewal,
          resetDescription: `${usd(subscriptionRemaining)} of ${usd(monthlyAllowance)} left`,
        }
      : undefined;

    const email = typeof user.email === "string" && user.email.trim() ? user.email.trim() : undefined;
    const orgName = typeof organisation.name === "string" && organisation.name.trim()
      ? organisation.name.trim()
      : undefined;
    const orgID = typeof organisation.id === "string" && organisation.id.trim()
      ? organisation.id.trim()
      : undefined;

    if (!primary && rows.length === 0 && !email && !orgName && !orgID) {
      throw ctx.fail.parseFailure("Nous Portal account response contained no usable billing data");
    }

    return {
      primary,
      details: rows.length > 0 ? [{ title: "Nous Portal", rows }] : undefined,
      identity: {
        email,
        organization: orgName,
        loginMethod: plan || "Nous Portal",
        accountID: orgID,
      },
      subscriptionRenewsAt: renewal,
      dataConfidence: "exact",
    };
  },
});
