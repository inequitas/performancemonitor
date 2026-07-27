# Contributing

Thanks for your interest in Performance Monitor! Bug reports and pull requests are welcome.

## Branching

Development happens on the **`beta`** branch — `main` only receives release merges.

- Branch your work off `beta`
- Open your pull request **against `beta`**

Accidentally targeted `main`? No problem — just change the base branch with the "Edit" button at the top of your PR, or ask and we'll switch it for you.

## Building

See [README.md](README.md#building-from-source) — `bash build_app.sh` is all you need (Apple Silicon Mac, Xcode Command Line Tools, Swift 5.10+).

Run the tests with `bash scripts/test.sh` (it takes the same arguments as `swift test`, e.g. `bash scripts/test.sh --filter DiskIORates`). Use it rather than a bare `swift test`: with only the Command Line Tools installed, swift-testing isn't on the default search path and `swift test` fails with `no such module 'Testing'`. The script adds the three search paths needed and is a plain `swift test` everywhere else.

## Translations

The app is localized in English, Dutch, German, French, Spanish, Simplified Chinese, and Japanese. The non-English translations are AI-generated — **improvements by native speakers are very welcome!** Each language lives in two files:

- `Sources/PerformanceApp/Resources/<lang>.lproj/Localizable.strings` — all UI strings
- `Resources/<lang>.lproj/InfoPlist.strings` — system permission prompts

Open a PR that edits the value side of any entry (the English key must stay unchanged). New languages are welcome too — copy `en.lproj` as a starting point.

## Guidelines

- Keep the app dependency-free: system frameworks only.
- No telemetry, analytics, or network calls beyond what the README documents.
- Match the existing code style; run `bash scripts/test.sh` before opening a PR.
