# Contributing

Thanks for your interest in Performance Monitor! Bug reports and pull requests are welcome.

## Building

See [README.md](README.md#building-from-source) — `bash build_app.sh` is all you need (Apple Silicon Mac, Xcode Command Line Tools, Swift 5.10+). Run the tests with `swift test`.

## Translations

The app is localized in English, Dutch, German, French, Spanish, Simplified Chinese, and Japanese. The non-English translations are AI-generated — **improvements by native speakers are very welcome!** Each language lives in two files:

- `Sources/PerformanceApp/Resources/<lang>.lproj/Localizable.strings` — all UI strings
- `Resources/<lang>.lproj/InfoPlist.strings` — system permission prompts

Open a PR that edits the value side of any entry (the English key must stay unchanged). New languages are welcome too — copy `en.lproj` as a starting point.

## Guidelines

- Keep the app dependency-free: system frameworks only.
- No telemetry, analytics, or network calls beyond what the README documents.
- Match the existing code style; run `swift test` before opening a PR.
