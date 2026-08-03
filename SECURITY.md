# Security

## What this software touches

`book.sh` and the native app read only text entered by the user or files selected
through the macOS file picker, run the bundled `pandoc` and `typst` executables,
and write rendering intermediates to the app's temporary directory. There is no
telemetry, advertising, account, credential handling, or reader-client delivery.

**The one network path** is the WeChat article feature: when *you* paste an
`mp.weixin.qq.com` link, the app fetches that page and the images it references.
Nothing is uploaded, no account is involved, and nothing is contacted unless you
paste a link. While parsing, the `WKWebView` doing the extraction has *every*
network request blocked via `WKContentRuleList` — so the page's own scripts and
trackers cannot fire, and Tencent's CDN is only contacted by our own deliberate
image fetches.

The app is sandboxed. Outgoing network access exists solely for user-initiated
HTTPS article conversion. Source and reproducible packaging materials for bundled
components are published with each matching release.

## Reporting a vulnerability

Email **leekaomin@foxmail.com**. Please don't open a public issue for anything
that could be actively exploited before a fix ships — for a project this size a
private email is faster to act on anyway.

Include what you found, and a minimal reproduction if you have one. There's no
bug bounty; there is a genuine, prompt fix and credit in the commit message if you
want it.

## Scope

This is a personal-scale, single-maintainer project run on trust and code review,
not a hardened service. If your threat model requires supply-chain attestation,
signed releases, or a formal disclosure SLA, this project doesn't currently offer
that — happy to discuss what's realistic if it matters to your use case.
