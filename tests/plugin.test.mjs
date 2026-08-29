import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

let provider = null;
globalThis.defineProvider = (value) => {
  provider = value;
};

const source = fs.readFileSync(new URL("../nousportal.js", import.meta.url), "utf8");
vm.runInThisContext(source, { filename: "nousportal.js" });

assert.ok(provider, "defineProvider was not called");
assert.equal(provider.id, "nous-portal");
assert.equal(provider.name, "Nous Portal");
assert.deepEqual(provider.capabilities, ["browser-cookies", "http-status"]);
assert.deepEqual(provider.cookieDomains, ["portal.nousresearch.com"]);

const fixture = {
  user: { email: "nick@example.com" },
  organisation: { id: "org_123", name: "Example Org", slug: "example-org" },
  subscription: {
    plan: "Plus",
    monthly_charge: 20,
    monthly_credits: 22,
    current_period_end: "2026-09-15T12:00:00Z",
    credits_remaining: 16.5,
    rollover_credits: 2.5,
  },
  paid_service_access: {
    allowed: true,
    paid_access: true,
    subscription_credits_remaining: 16.5,
    purchased_credits_remaining: 7.25,
    total_usable_credits: 23.75,
    member_spend_usd: 5.5,
    member_spend_cap_usd: 50,
    member_spend_cap_remaining_usd: 44.5,
  },
};

let observedRequest = null;
let cookieHeader = "other=1; privy-token=test%2Eprivy%2Ejwt; privy-session=session";
let response = { status: 200, headers: {}, json: fixture };

const ctx = {
  browser: {
    async cookieHeader(domain) {
      assert.equal(domain, "portal.nousresearch.com");
      return cookieHeader;
    },
  },
  http: {
    async getJSON(url, options) {
      observedRequest = { url, options };
      return response;
    },
  },
  fail: {
    missingCredential: (message) => new Error(`missingCredential:${message}`),
    authenticationExpired: (message) => new Error(`authenticationExpired:${message}`),
    rateLimited: (message) => new Error(`rateLimited:${message}`),
    apiFailure: (message) => new Error(`apiFailure:${message}`),
    parseFailure: (message) => new Error(`parseFailure:${message}`),
  },
  pct(used, limit) {
    return Math.max(0, Math.min(100, (used / limit) * 100));
  },
  format: {
    usd(value) {
      return `$${Number(value).toFixed(2)}`;
    },
    monthDay(date) {
      return new Date(date).toISOString().slice(0, 10);
    },
  },
  date: {
    iso(value) {
      return new Date(value);
    },
  },
};

let snapshot = await provider.fetchUsage(ctx);
assert.equal(observedRequest.url, "https://portal.nousresearch.com/api/oauth/account");
assert.equal(observedRequest.options.headers.Authorization, "Bearer test.privy.jwt");
assert.match(observedRequest.options.headers.Cookie, /privy-token=/);
assert.equal(Math.round(snapshot.primary.usedPercent), 25);
assert.equal(snapshot.primary.resetDescription, "$16.50 of $22.00 left");
assert.equal(snapshot.identity.email, "nick@example.com");
assert.equal(snapshot.identity.organization, "Example Org");
assert.equal(snapshot.identity.loginMethod, "Plus");
assert.equal(snapshot.identity.accountID, "org_123");
assert.equal(snapshot.dataConfidence, "exact");
assert.ok(snapshot.details[0].rows.some((row) => row.label === "Top-up remaining" && row.value === "$7.25"));
assert.ok(snapshot.details[0].rows.some((row) => row.label === "Total usable" && row.value === "$23.75"));

cookieHeader = "__Host-privy-token=host%2Eprivy%2Ejwt; privy-id-token=id-token";
response = { status: 200, headers: {}, json: fixture };
snapshot = await provider.fetchUsage(ctx);
assert.equal(observedRequest.options.headers.Authorization, "Bearer host.privy.jwt");

cookieHeader = "__Secure-privy-token=secure%2Eprivy%2Ejwt; privy-id-token=id-token";
snapshot = await provider.fetchUsage(ctx);
assert.equal(observedRequest.options.headers.Authorization, "Bearer secure.privy.jwt");

const rolloverFixture = structuredClone(fixture);
rolloverFixture.paid_service_access.subscription_credits_remaining = 25;
rolloverFixture.subscription.credits_remaining = 25;
cookieHeader = "privy-token=test-token";
response = { status: 200, headers: {}, json: rolloverFixture };
const rolloverSnapshot = await provider.fetchUsage(ctx);
assert.equal(rolloverSnapshot.primary, undefined, "rollover above monthly grant must not produce misleading percentage");

response = { status: 401, headers: {}, json: {} };
await assert.rejects(() => provider.fetchUsage(ctx), /authenticationExpired/);

cookieHeader = "privy-session=only-session";
await assert.rejects(() => provider.fetchUsage(ctx), /access-token cookie is missing/);

cookieHeader = "other=value";
await assert.rejects(() => provider.fetchUsage(ctx), /Nous Portal login cookie not found/);

console.log("Nous Portal plugin fixture tests passed");
