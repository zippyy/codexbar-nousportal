# CodexBar Nous Portal Provider

Adds **Nous Portal** subscription/credit usage to [CodexBar](https://github.com/steipete/CodexBar).

> CodexBar provider IDs are currently compile-time, so this is an **overlay/provider patch**, not a hot-loadable `.plugin` bundle. `apply.sh` copies the provider into a CodexBar checkout, registers the provider ID, and regenerates CodexBar's provider manifests.

## What it shows

- Nous plan name
- Monthly credit allowance
- Monthly usage percentage
- Subscription credits remaining
- Top-up credits remaining
- Total usable balance
- Rollover credits
- Renewal date
- Organization/account identity
- Member spend cap and spend, when present
- Active/depleted paid-access state

## Authentication

No Nous API key or browser cookie is stored by CodexBar.

The provider reuses the OAuth session already managed by **Hermes Agent** in:

```text
~/.hermes/auth.json
```

`HERMES_HOME` is honored, including a fallback to the normal `~/.hermes/auth.json` store when a Hermes profile does not contain Nous credentials.

The provider calls:

```text
GET https://portal.nousresearch.com/api/oauth/account
Authorization: Bearer <Hermes OAuth token>
```

If the access token is stale, CodexBar invokes:

```bash
hermes status
```

and then retries. This is intentional: Nous refresh tokens rotate and use reuse detection, so **Hermes remains the only process that refreshes/writes the OAuth session**.

## Install into a CodexBar checkout

```bash
git clone https://github.com/steipete/CodexBar.git
cd codexbar-nousportal
./apply.sh ../CodexBar
```

Then build CodexBar normally and enable:

**Settings → Providers → Nous Portal**

If Hermes is not logged into Nous yet:

```bash
hermes portal
```

## Releases

`.github/workflows/release.yml` builds and publishes versioned provider bundles.

A release can be started either by pushing a semantic-version tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

or from **Actions → Build and release plugin → Run workflow**, where you enter a version such as `v0.1.0` and optionally mark it as a prerelease.

Before publishing, the workflow:

1. checks out the current CodexBar `main` revision;
2. selects the same Xcode 26.x toolchain family used by CodexBar CI;
3. applies the Nous Portal provider;
4. runs the focused `NousPortal` Swift tests;
5. compiles the patched CodexBar release product;
6. builds ZIP and tar.gz provider bundles plus SHA-256 checksums;
7. publishes those files as GitHub Release assets.

Each bundle contains `apply.sh`, the provider overlay, install instructions, and `BUILD-METADATA.txt` recording the exact CodexBar commit used for validation.

You can also build the release assets locally:

```bash
bash ./build-release.sh v0.1.0
```

## Verify against current CodexBar

On macOS:

```bash
./check-upstream.sh
```

This clones current CodexBar, applies the provider, regenerates manifests, and runs the Nous Portal tests.

## Provider files

```text
overlay/
├── Sources/
│   ├── CodexBarCore/Providers/NousPortal/
│   │   ├── NousPortalAuthReader.swift
│   │   ├── NousPortalProviderDescriptor.swift
│   │   └── NousPortalUsageFetcher.swift
│   └── CodexBar/
│       ├── Providers/NousPortal/NousPortalProviderImplementation.swift
│       └── Resources/ProviderIcon-nousportal.svg
└── Tests/CodexBarTests/NousPortalUsageFetcherTests.swift
```

## Design notes

The account response is mapped using the same fields Hermes currently consumes from Nous Portal, including `subscription.monthly_credits`, `subscription.credits_remaining`, `paid_service_access.subscription_credits_remaining`, `purchased_credits_remaining`, and `total_usable_credits`.

When rollover makes `credits_remaining` greater than the monthly allowance, the provider deliberately does **not** render a misleading monthly percentage. It still displays the actual dollar balances.

## Upstreaming

The overlay is intentionally shaped like a normal CodexBar first-party provider so it can be converted into an upstream PR with minimal changes.
