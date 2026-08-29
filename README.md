# CodexBar Nous Portal Plugin

A true user-installable CodexBar provider for **Nous Portal** subscription and credit usage.

This project is a normal CodexBar user plugin. It does **not** patch CodexBar source code and does **not** require rebuilding CodexBar.

## Install

1. Download the latest `codexbar-nousportal-vX.Y.Z.js` release asset.
2. Open **CodexBar → Settings → Plugins → Install…**.
3. Select the downloaded `.js` file.
4. Approve access to `https://portal.nousresearch.com` and the Portal browser cookie.
5. Sign in to `portal.nousresearch.com` in Chrome if you are not already signed in.
6. Enable **Nous Portal** in CodexBar.

You can also install the development copy directly from this repository by selecting `nousportal.js`.

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

## Authentication

CodexBar user plugins cannot read `~/.hermes/auth.json`, launch Hermes, or run their own OAuth flow. This plugin therefore uses CodexBar's sandboxed **browser-cookie broker**.

The plugin requests the `portal.nousresearch.com` browser session, extracts the Portal `privy-token`, and sends it as:

```text
Authorization: Bearer <privy-token>
```

to:

```text
GET https://portal.nousresearch.com/api/oauth/account
```

Current CodexBar user-plugin cookie import is Chrome-based, so sign in to Nous Portal in Chrome before enabling the plugin.

No Nous token is stored in the plugin source or written to the repository.

## Plugin file

```text
nousportal.js
```

The dynamic provider ID is:

```text
nous-portal
```

This is the exact file format supported by **CodexBar → Settings → Plugins → Install…**.

## Testing

Run the local fixture tests with:

```bash
node tests/plugin.test.mjs
```

The tests cover:

- provider manifest registration
- Portal billing/credit mapping
- monthly percentage calculation
- rollover-credit behavior
- expired authentication
- missing Portal cookie handling

GitHub Actions additionally builds the current stock CodexBar CLI, places the plugin into a clean CodexBar user-plugin directory, and verifies that CodexBar discovers:

```text
nous-portal    Nous Portal
```

No CodexBar source patch is applied during this validation.

## Releases

`.github/workflows/release.yml` creates importable plugin releases.

You can trigger a release either by pushing a semantic version tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

or from **GitHub → Actions → Build and release plugin → Run workflow**.

For a manual release, the version field accepts either form:

```text
0.1.0
v0.1.0
```

The workflow normalizes both to `v0.1.0`.

If an older workflow run failed because it rejected `0.1.0`, start a **new Run workflow** from current `main` rather than using **Re-run jobs** on that old run; GitHub reruns the workflow definition from the original commit.

Release assets are:

```text
codexbar-nousportal-v0.1.0.js
codexbar-nousportal-v0.1.0.sha256
codexbar-nousportal-v0.1.0.txt
```

Before publishing, the workflow:

1. runs plugin fixture tests;
2. checks out current upstream CodexBar;
3. builds stock `CodexBarCLI`;
4. validates that the plugin is discovered as a dynamic user plugin;
5. packages the `.js` file;
6. generates SHA-256 metadata;
7. publishes the GitHub Release.

## Security model

The plugin declares only the authority it needs:

- HTTPS access to `portal.nousresearch.com`
- browser-cookie access for `portal.nousresearch.com`

It has no local filesystem access, subprocess access, Node APIs, arbitrary network access, or Hermes credential access. All network requests go through CodexBar's plugin sandbox.

## Notes

The account response is mapped using the same Nous Portal fields consumed by Hermes, including:

- `subscription.monthly_credits`
- `subscription.credits_remaining`
- `paid_service_access.subscription_credits_remaining`
- `paid_service_access.purchased_credits_remaining`
- `paid_service_access.total_usable_credits`

When rollover makes available subscription credits greater than the normal monthly allowance, the plugin avoids presenting a misleading monthly percentage while still displaying the actual balances.
