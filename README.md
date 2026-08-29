# CodexBar Nous Portal Plugin

A **true user-installable CodexBar plugin** for Nous Portal subscription and credit usage.

No CodexBar fork, source patch, or rebuild is required.

## Install

1. Download the latest `codexbar-nousportal-vX.Y.Z.js` from GitHub Releases.
2. Open **CodexBar → Settings → Plugins → Install…**.
3. Select the downloaded `.js` file.
4. Review and approve the requested access to `https://portal.nousresearch.com` and the Nous Portal browser cookie.
5. Enable **Nous Portal**.

You can also install the source file from this repository directly:

```text
nousportal.js
```

CodexBar user plugins can also be installed manually by placing the file in:

```text
~/.config/codexbar/providers/
```

## Authentication

The plugin does **not** read `~/.hermes/auth.json` and does not store a Nous refresh token.

Instead it uses CodexBar's sandboxed `browser-cookies` capability to obtain the logged-in Nous Portal browser session. It extracts the Portal `privy-token` and uses that credential for the account request.

Current CodexBar user-plugin cookie brokerage imports the browser session from **Chrome**. If Nous Portal shows an authentication error in CodexBar:

1. Open `https://portal.nousresearch.com` in Chrome.
2. Sign in to Nous Portal.
3. Return to CodexBar and refresh the Nous Portal plugin.

This avoids Nous's rotating Hermes refresh-token flow entirely; the plugin never touches or rotates Hermes OAuth credentials.

## What it shows

- Plan name
- Monthly plan price
- Monthly credit allowance
- Monthly usage percentage when it can be represented accurately
- Subscription dollars remaining
- Top-up dollars remaining
- Total usable balance
- Rollover balance
- Renewal date
- Account email and organization
- Member spend and spend cap, when supplied by Portal
- Paid-access state

If rollover makes the subscription balance larger than the base monthly allowance, the plugin deliberately omits the percentage meter rather than showing a misleading negative/over-100% value. Dollar balances are still shown.

## CodexBar permissions

The plugin manifest declares only:

```text
Network origin: https://portal.nousresearch.com
Capability: browser-cookies
Capability: http-status
Cookie domain: portal.nousresearch.com
```

The plugin cannot read local files, launch subprocesses, access Hermes credentials, use arbitrary network origins, or run Node/browser APIs inside CodexBar.

## Development

Run the standalone fixture tests:

```bash
node tests/plugin.test.mjs
```

The tests cover:

- Manifest identity and permissions
- Portal cookie extraction
- Authorization header construction
- Billing/account response mapping
- Monthly percentage calculation
- Rollover behavior
- Expired authentication
- Missing Portal cookie behavior

## Upstream compatibility

`.github/workflows/upstream-compat.yml` regularly checks the plugin against the current stock `steipete/CodexBar` main branch.

CI:

1. Runs the plugin fixture tests.
2. Enforces CodexBar's 1 MiB plugin limit.
3. Builds the stock CodexBar CLI.
4. Places `nousportal.js` into a clean `~/.config/codexbar/providers/` directory.
5. Runs `CodexBarCLI plugins list`.
6. Fails unless stock CodexBar discovers `nous-portal` as a dynamic user provider.

That means compatibility testing does **not** patch or rebuild CodexBar with a new built-in provider ID.

## Releases

Push a semantic version tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

or run **Actions → Build and release plugin → Run workflow**.

The release workflow validates the plugin against current stock CodexBar and publishes:

```text
codexbar-nousportal-vX.Y.Z.js
codexbar-nousportal-vX.Y.Z.sha256
codexbar-nousportal-vX.Y.Z.txt
```

The `.js` file is the artifact users import directly through **CodexBar → Settings → Plugins → Install…**.

## Data source

The provider requests:

```text
GET https://portal.nousresearch.com/api/oauth/account
```

and maps the billing fields Nous currently exposes to Hermes, including:

```text
subscription.monthly_credits
subscription.credits_remaining
subscription.rollover_credits
subscription.current_period_end
paid_service_access.subscription_credits_remaining
paid_service_access.purchased_credits_remaining
paid_service_access.total_usable_credits
paid_service_access.member_spend_usd
paid_service_access.member_spend_cap_usd
```

## License

This project is an independent CodexBar provider plugin and is not affiliated with Nous Research or the CodexBar project.
