# Security

## What this software touches

`book.sh` and the native app read only EPUB files selected by the user through
the macOS file picker, run the bundled `pandoc` and `typst` executables,
and write rendering intermediates to the app's temporary directory. There is no
telemetry, advertising, account, credential handling, or reader-client delivery.

The app is sandboxed and has no outgoing-network entitlement. It does not fetch
webpages or upload documents. Source and reproducible packaging materials for
bundled components are published with each matching release.

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
