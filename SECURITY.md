# Security Policy

## Reporting a vulnerability

Please report security issues **privately**, not in a public issue.

Use GitHub's private vulnerability reporting: go to the [Security tab](https://github.com/inequitas/performancemonitor/security) and click **Report a vulnerability**. That opens a private thread visible only to you and the maintainer.

Please include what you found, how to reproduce it, which version you were running (Settings → About shows the version and update channel), and your macOS and chip generation.

## What to expect

This is a free project maintained by one person in their spare time, so please calibrate accordingly:

- I aim to acknowledge a report within a few days.
- If it is confirmed and exploitable, a fix goes out in the next release, or sooner as a patch release if it warrants one.
- I will credit you in the changelog unless you would rather stay anonymous.

## Supported versions

Only the latest stable release is supported. Fixes are not backported to older versions; if you are behind, updating is the fix. The beta channel gets fixes first, since that is where development happens.

## Where the interesting attack surface is

If you are looking for somewhere to dig, these are the parts that actually matter:

- **The update mechanism.** Updates are downloaded from GitHub over HTTPS and verified against an Ed25519 signature with the public key embedded in the app. Verification is fail-closed: an update that does not verify is not installed, and the quarantine attribute is only cleared after a successful verification. Anything that gets around that check, or that lets an unverified bundle run, is the most serious thing you could find here.
- **The IOKit and SMC reads.** These parse data from system interfaces. Malformed or unexpected data should not be able to corrupt memory or crash the app in an exploitable way.
- **The helper subprocesses.** `ps` and `nettop` are invoked with fixed argument lists and their output is parsed. Anything that turns that parsing into command injection or memory unsafety is in scope.

There is no server, no account system, and no telemetry, so there is no backend to attack. Everything the app collects stays on the machine.

## Out of scope

- **The app is ad-hoc signed rather than notarised**, so the first launch requires right-click → Open. This is a deliberate, documented tradeoff (an Apple Developer ID costs €99/year and is not justified for a free app yet), not a vulnerability. Updates are signature-verified regardless of it.
- **Reports that the app can read system information.** That is what it is for. Everything it reads is available to any unprivileged process on the machine.
- **Automated scanner output with no demonstrated impact.** A finding that cannot be tied to something an attacker could actually do is not actionable on a project this size.
