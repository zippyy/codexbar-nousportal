# CodexBar Nous Portal Plugin

A user-installable CodexBar provider for **Nous Portal** subscription and credit usage.

The `.js` is a normal CodexBar user plugin. It does **not** patch CodexBar or require rebuilding CodexBar.

## Why a helper is required

Nous Portal uses Privy's default browser-session mode for many accounts. In that mode the access token lives in browser localStorage rather than a `privy-token` cookie.

CodexBar user plugins can broker Chrome cookies, but they cannot read browser localStorage, `~/.hermes/auth.json`, local files, or subprocesses. That means a cookie-only plugin cannot reliably authenticate to Nous Portal.

This project therefore includes a tiny localhost helper. The helper:

- binds only to `127.0.0.1:38417`;
- reads the existing Hermes Nous OAuth state from `~/.hermes/auth.json` (or `HERMES_HOME`);
- lets `hermes status` handle OAuth refresh/rotation when needed;
- calls `GET https://portal.nousresearch.com/api/oauth/account` with the current Hermes access token;
- returns only the Nous account/billing JSON to CodexBar;
- never returns OAuth access or refresh tokens to the plugin.

## Install

For releases, download and extract:

```text
codexbar-nousportal-v0.2.0-macos.zip
```

Then run the included helper installer:

```bash
./install-helper-v0.2.0.sh
```

Verify it is running:

```bash
curl http://127.0.0.1:38417/health
```

Then install the `.js` in:

**CodexBar → Settings → Plugins → Install…**

When CodexBar asks for the plugin setting, enter:

```text
Helper URL: http://127.0.0.1:38417
```

Approve the loopback origin and enable **Nous Portal**.

If Hermes is not authenticated to Nous, run:

```bash
hermes model
```

or:

```bash
hermes status
```

and refresh the plugin.

## What it shows

- Nous plan name
- Monthly credit allowance
- Monthly usage percentage
- Subscription credits remaining
- Purchased/top-up credits remaining
- Total usable credits
- Rollover credits
- Renewal date
- Organization/account identity
- Member spend cap and current spend, when present
- Active/depleted paid-access state

## Plugin file

```text
nousportal.js
```

Dynamic provider ID:

```text
nous-portal
```

## Helper

Source:

```text
helper/main.go
```

Default listener:

```text
http://127.0.0.1:38417
```

The release workflow builds a universal macOS binary containing both Apple Silicon and Intel slices.

The installer places it at:

```text
~/.local/bin/codexbar-nousportal-helper
```

and installs a per-user LaunchAgent:

```text
~/Library/LaunchAgents/com.zippyy.codexbar-nousportal-helper.plist
```

Logs:

```text
~/Library/Logs/CodexBar/nousportal-helper.log
```

## Testing

Plugin fixtures:

```bash
node tests/plugin.test.mjs
```

Helper:

```bash
cd helper
go test ./...
go vet ./...
```

GitHub Actions additionally:

1. builds the helper for `darwin/arm64` and `darwin/amd64`;
2. combines them into one universal binary;
3. builds the current stock CodexBar CLI;
4. verifies stock CodexBar discovers the `.js` as `nous-portal`.

## Releases

Trigger a release by pushing a semantic tag or using **GitHub → Actions → Build and release plugin → Run workflow**.

Manual versions accept either:

```text
0.2.0
v0.2.0
```

Release assets include:

```text
codexbar-nousportal-v0.2.0.js
codexbar-nousportal-helper-v0.2.0
install-helper-v0.2.0.sh
codexbar-nousportal-v0.2.0-macos.zip
codexbar-nousportal-v0.2.0.sha256
codexbar-nousportal-v0.2.0.txt
```

## Security model

The CodexBar plugin itself receives only loopback network authority for the configured helper URL. It has no cookie permission, filesystem access, subprocess access, Node APIs, arbitrary native APIs, or direct Hermes credential access.

The helper is a separate local process bound only to `127.0.0.1`. It reads Hermes credentials locally, delegates refresh to Hermes, and sends the access token only to the Nous Portal HTTPS endpoint. The token is never returned through the localhost API.

## Notes

The account response is mapped using the same Nous Portal fields consumed by Hermes, including:

- `subscription.monthly_credits`
- `subscription.credits_remaining`
- `paid_service_access.subscription_credits_remaining`
- `paid_service_access.purchased_credits_remaining`
- `paid_service_access.total_usable_credits`

When rollover makes available subscription credits greater than the normal monthly allowance, the plugin avoids presenting a misleading monthly percentage while still displaying the actual balances.
