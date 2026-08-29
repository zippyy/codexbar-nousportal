const NOUS_PORTAL_PLUGIN_BUILD = "0.1.1-dev-cookie-diag";

defineProvider({
  id: "nous-portal",
  name: "Nous Portal",
  icon: { monogram: "N", tint: "#6C5CE7" },
  endpoints: ["https://portal.nousresearch.com"],
  settings: [],
  capabilities: ["browser-cookies", "http-status"],
  cookieDomains: ["portal.nousresearch.com"],

  async fetchUsage(ctx) {
    const portalOrigin = "https://portal.nousresearch.com";
    const accountURL = `${portalOrigin}/api/oauth/account`;
    const cookieHeader = await ctx.browser.cookieHeader("portal.nousresearch.com");
    const cookieNames = cookieHeader
      .split(";")
      .map((part) => part.split("=", 1)[0].trim())
      .filter(Boolean);
    const cookieSummary = cookieNames.length > 0 ? cookieNames.join(", ") : "none";

    const tokenMatch = /(?:^|;\s*)(?:__Host-|__Secure-)?privy-token=([^;]+)/i.exec(cookieHeader);
    const renewableSession = /(?:^|;\s*)(?:__Host-|__Secure-)?(?:privy-session|privy-refresh-token)=([^;]+)/i.test(
      cookieHeader
    );

    const requestHeaders = {
      Cookie: cookieHeader,
      Accept: "application/json",
      Origin: portalOrigin,
      Referer: `${portalOrigin}/`,
    };

    let response;

    if (tokenMatch) {
      let privyToken = tokenMatch[1];
      try {
        privyToken = decodeURIComponent(privyToken);
      } catch {
        // Cookie was already decoded; use it as-is.
      }

      response = await ctx.http.getJSON(accountURL, {
        headers: {
          ...requestHeaders,
          Authorization: `Bearer ${privyToken}`,
        },
      });
    } else {
      // Some Portal sessions may be usable through the browser cookie jar even
      // when the short-lived Privy access-token cookie is absent. Try the exact
      // browser session first before asking the user to re-authenticate.
      response = await ctx.http.getJSON(accountURL, { headers: requestHeaders });

      if (response.status === 401 || response.status === 403) {
        const prefix = `[${NOUS_PORTAL_PLUGIN_BUILD}] Cookies visible to CodexBar: ${cookieSummary}.`;
        if (renewableSession) {
          throw ctx.fail.missingCredential(
            `${prefix} Nous Portal has a renewable browser session but no usable access token. Open or hard-refresh portal.nousresearch.com in Chrome, then use the top Plugins Refresh button before refreshing Nous Portal.`
          );
        }
        throw ctx.fail.missingCredential(
          `${prefix} No usable Nous Portal login token was found. Sign in to portal.nousresearch.com in Chrome, then use the top Plugins Refresh button before refreshing Nous Portal.`
        );
      }
    }

    if (response.status === 401 || response.status === 403) {
      throw ctx.fail.authenticationExpired(
        `[${NOUS_PORTAL_PLUGIN_BUILD}] Nous Portal rejected the imported browser session. Cookies visible to CodexBar: ${cookieSummary}. Sign in to portal.nousresearch.com in Chrome, reload the Portal page, then refresh plugin discovery in CodexBar.`
      );
    }

    if (response.status === 429) {
      const retryAfter = Number(response.headers?.["retry-after"] || 1);
      throw ctx.fail.rateLimited("Nous Portal rate limit reached", {
        retryAfterSeconds: Number.isFinite(retryAfter) ? retryAfter : 1,
      });
    }

    if (response.status < 200 || response.status >= 300) {
      throw ctx.fail.apiFailure(`Nous Portal returned HTTP ${response.status}`);
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
