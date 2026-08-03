# Contributing

TrueScale PDF welcomes reproducible rendering fixes, accessibility improvements,
format compatibility work, and additional physical-size measurements.

## Device measurements (start here)

If you own any e-ink device, see the [Contributing section in
README](README.md#contributing) — measuring your device's true display size takes
about five minutes with the calibration page and is the single most useful thing
you can send. This section is about code.

## Code contributions

### Before you start

- Read [`docs/PRD.md`](docs/PRD.md) §7 ("Quality invariants") — every one of those
  eight rules was learned from a real bug that shipped once. They're not style
  preferences; violating one will very likely reintroduce a bug that's already been
  fixed once.
- `tasks/T-001.md` through `T-008.md` are dated task briefs written for a
  specific point in this project's history — not a template you need to follow.
  They're kept as a record of *why* a given piece of the system looks the way it
  does. Worth skimming if you're about to touch the GUI or `book.sh`.

### Setup

```bash
brew install pandoc typst poppler
./book.sh --help
xcodegen generate
```

The native macOS app additionally needs Xcode and XcodeGen.

### Before opening a PR

```bash
./test.sh
```

The assertions take a few seconds. If you touched `book.sh`, `deliver.typ`,
`config.sh`, or any font/rendering logic, run it — page-size and Markdown-dialect
regressions here are easy to introduce and easy to catch. If it can't run in your
environment (missing `pandoc`/`typst`), say so in the PR rather than skipping it
silently.

### Style

- Keep changes scoped to what the PR is about. Don't refactor adjacent code in the
  same PR, even if it's tempting.
- Comments only where they explain a non-obvious constraint or a "why," not what
  the code does. Most of this codebase has none, on purpose.
- Shell scripts target `zsh` (macOS default). Don't introduce bashisms.

### What's especially welcome

- Measurements from additional printers and reading devices using the calibration
  page, with the exact model and measurement method recorded.
- English-language error messages (currently Chinese in some paths).
- Import support for additional reflowable document formats with legal, auditable
  dependencies.

### What to avoid

- New third-party dependencies. The project's stated design goal is that a user
  should be able to read the entire delivery pipeline before running it; adding
  a pip package or npm dependency works against that.
- Device-client delivery integrations. The current product deliberately stops at
  producing a standard PDF that the user controls.
