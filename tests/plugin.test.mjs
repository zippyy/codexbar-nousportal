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
assert.deepEqual(provider.capabilities, ["http-status"]);
assert.equal(provider.endpoints.length, 1);
assert.equal(provider.endpoints[0].setting, "HELPER_URL");
assert.equal(provider.endpoints[0].policy, "https-or-loopback-http");
assert.equal(provider.settings[0].key, "HELPER_URL");
assert.equal(provider.settings[0].type, "plain");

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

let helperURL = "http://127.0.0.1:38417";
let response = { status: 200, headers: {}, json: fixture };
let observedURL = null;

const ctx = {
  settings: {
    get(key) {
      assert.equal(key, "HELPER_URL");
      return helperURL;
    },
  },
  http: {
    async getJSON(url) {
      observedURL = url;
      return response;
    },
  },
  fail: {
    missingCredential: (message) => new Error(`missingCredential:${message}`),
    authenticationExpired: (message) => new Error(`authenticationExpired:${message}`),
    rateLimited: (message) => new Error(`rateLimited:${message}`),
    providerUnavailable: (message) => new Error(`providerUnavailable:${message}`),
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
assert.equal(observedURL, "http://127.0.0.1:38417/v1/account");
assert.equal(Math.round(snapshot.primary.usedPercent), 25);
assert.equal(snapshot.primary.resetDescription, "$16.50 of $22.00 left");
assert.equal(snapshot.identity.email, "nick@example.com");
assert.equal(snapshot.identity.organization, "Example Org");
assert.equal(snapshot.identity.loginMethod, "Plus");
assert.equal(snapshot.identity.accountID, "org_123");
assert.equal(snapshot.dataConfidence, "exact");
assert.ok(snapshot.details[0].rows.some((row) => row.label === "Top-up remaining" && row.value === "$7.25"));
assert.ok(snapshot.details[0].rows.some((row) => row.label === "Total usable" && row.value === "$23.75"));

const rolloverFixture = structuredClone(fixture);
rolloverFixture.paid_service_access.subscription_credits_remaining = 25;
rolloverFixture.subscription.credits_remaining = 25;
response = { status: 200, headers: {}, json: rolloverFixture };
const rolloverSnapshot = await provider.fetchUsage(ctx);
assert.equal(rolloverSnapshot.primary, undefined, "rollover above monthly grant must not produce misleading percentage");

response = { status: 401, headers: {}, json: { error: "OAuth expired" } };
await assert.rejects(() => provider.fetchUsage(ctx), /authenticationExpired:.*OAuth expired/);

response = { status: 503, headers: {}, json: { error: "Hermes executable not found" } };
await assert.rejects(() => provider.fetchUsage(ctx), /providerUnavailable:.*Hermes executable not found/);

helperURL = "";
await assert.rejects(() => provider.fetchUsage(ctx), /missingCredential:.*127\.0\.0\.1:38417/);

console.log("Nous Portal plugin fixture tests passed");
