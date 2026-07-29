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

## The idle-CPU budget

A system monitor that costs a noticeable slice of the thing it is measuring is a bad system monitor, so this one has a budget: **under 3% idle CPU** on an Apple Silicon Mac with nothing open. Getting there took several rounds of work, and it is easy to give back by accident.

Two rules carry most of that:

**Nothing expensive runs for a surface nobody is looking at.** `ps` and `nettop`, the extended SMC sensor set, per-domain power, per-process disk I/O and the latency probe are all gated on whether the window that displays them is actually visible. See `MetricsEngine.setPanelVisible`. If you add a metric that only one window shows, gate it the same way.

**A closed window must stop working.** SwiftUI keeps a scene's view tree alive after its window closes, and a tree that observes `MetricsEngine` will happily re-evaluate its body on every published change forever. Window scenes therefore unmount their content while hidden, driven by `WindowVisibilityAccessor`. Any `.task` loop inside such a tree keeps running too, so include visibility in its `id:`.

### Measuring it

`scripts/benchmark.sh` samples cumulative CPU time and reports the real usage per interval. Do not use `ps -o %cpu` for this; that column is an average since the process launched, so sampling it repeatedly measures the wrong thing.

```sh
bash scripts/benchmark.sh -d 5 -i 10 -l "my-change"
```

Verify the state you think you are measuring before trusting a number. `sample <pid> 20` shows what is actually being evaluated: if a `*DetailView`, `MetricChart` or `OverviewView` frame turns up while no window is on screen, something is still mounted that should not be. A previous attempt at this measurement concluded there was no problem, because one build had a window open and the other did not.
