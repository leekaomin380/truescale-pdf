# Changelog

## [1.1.0] - 2026-08-07

### Added

- Local HTML/HTM, FB2 and Markdown file input alongside EPUB.
- Local relative-image resolution for HTML documents.
- Clear file-type identification after selecting a source file.

### Fixed

- Large HTML documents no longer fail when level-one headings occur inside container elements.
- Chapter page breaks are inserted only at safe document boundaries.
- HTML math written for MathJax is parsed instead of appearing as source text.
- Rendering errors now surface the relevant Pandoc or Typst message.

## [1.0.0] - 2026-08-03

### Added

- Native macOS app for converting EPUB to PDF.
- A4, A5 and B5 page presets with plain-language size descriptions.
- PDF preview, save workflow and adjustable fonts, type size, margins and leading.
- Bundled arm64 Pandoc 3.10, Typst 0.15.1 and GNU MP 6.3.0 runtime.
- In-app open-source component disclosure, bundled corresponding source, release archives and checksums.
- App Sandbox, privacy manifest, privacy policy and App Store metadata.

### Changed

- The product is now Epub 转 PDF, focused on local fixed-layout conversion.
- A4 is the default output instead of a device-specific display size.

### Removed

- Quaderno delivery UI, runtime code, client detection and legacy delivery launchers.

Historical calibration documents remain in `docs/` because the physical-size measurements are the project's accuracy baseline.
