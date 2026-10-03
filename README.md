# Overhang

A personal macOS notch utility: hover over the MacBook notch and it opens into a panel with twenty tools. Modeled on the feature set of [OmniNotch](https://omninotch.app/), written from scratch in SwiftUI/AppKit with no third-party dependencies. The notch window approach is adapted from [NotchDrop](https://github.com/Lakr233/NotchDrop) (MIT).

- macOS 14 Sonoma or later, Apple silicon or Intel
- Works on Macs without a notch (draws a floating notch at the top of the main display)
- Everything is local. Only Weather, Stocks and currency rates touch the network, and only while those tools are open

## Tools

| Tool | How it works |
|---|---|
| Ask | Apple's on-device Foundation Model (macOS 26 + Apple Intelligence). Compiled out when built with an older SDK |
| Now Playing | Music & Spotify via their state notifications + AppleScript; other players via media keys |
| Clipboard | Polls the pasteboard; skips items marked concealed by password managers |
| Shelf | Drag files onto the notch; drag them back out, AirDrop, reveal in Finder |
| AI Usage | Sums tokens from local Claude Code (`~/.claude/projects`) and Codex (`~/.codex/sessions`) logs |
| Timer | Countdown presets, free-form durations (`90s`, `1h30m`), Pomodoro cycles |
| Weather | Open-Meteo (no API key) |
| Stocks | Yahoo Finance chart endpoint (no API key; unofficial) |
| System | CPU, memory, disk, network throughput, battery |
| Calendar | EventKit, next 4 days |
| To-dos / Notes | JSON files in `~/Library/Application Support/Overhang` |
| Emoji | Search by Unicode name; inserts into the frontmost app (Accessibility) |
| Convert | `12 km to mi`, `100 usd to eur` (Frankfurter / ECB rates) |
| Calculator | Expression parser with a tape |
| Keep Awake | IOKit power assertion, same mechanism as `caffeinate` |
| Volume | CoreAudio; shows a HUD in the closed notch on volume changes |
| Teleprompter | Scrolls a script right under the camera |
| Mirror | Camera preview |
| Color Picker | `NSColorSampler`; copies hex/rgb/hsl |

While closed, the notch shows **live activities** beside the camera: album art + equalizer, timer countdown, volume level, keep-awake state.

Two of the twenty (Color Picker, Calculator) are my picks. OmniNotch's public pages that I could find list eighteen tools, not all twenty.

## Build & run

Requires Xcode (16+, or 26+ for the Ask tool).

```sh
make run        # builds build/Overhang.app and opens it
make install    # copies to /Applications
make test       # unit tests for the pure logic (OverhangCore)
```

`ARCHS=arm64 ./scripts/build-app.sh` builds for one architecture, which is faster.

Shortcut: **⌥⌘N** toggles the notch. **Esc** closes it. The pin button keeps it open.

### Downloading a CI build instead

Each push to `main` builds `Overhang.zip` as a GitHub Actions artifact. It is ad-hoc signed, not notarized, so after unzipping:

```sh
xattr -dr com.apple.quarantine Overhang.app
```

## Permissions

Asked for only when a tool needs them:

- **Automation** (Music, Spotify): Now Playing
- **Accessibility**: media keys for non-Music/Spotify players, auto-inserting emoji
- **Calendars**: Calendar tool
- **Camera**: Mirror tool

Ad-hoc signed builds get a new signature on every rebuild, so macOS may ask again (or list a stale Accessibility entry you need to remove and re-add).

## Layout

```
Sources/OverhangCore   pure logic, unit tested: calculator, unit/currency conversion,
                       durations & Pomodoro, agent-log parsing, emoji catalog, weather codes
Sources/Overhang/App   window, hover/click/drag tracking, hotkey, prefs, storage
Sources/Overhang/UI    notch shape, root/closed views, tool strip, settings
Sources/Overhang/Tools one file per tool (service + view)
```

## Known limits

- Now Playing artwork/position come from Music and Spotify only. macOS 15.4+ blocks third-party access to the system-wide now-playing API, so browser players show no metadata (their play/pause still works through media keys).
- The equalizer in the closed notch is decorative, not driven by audio levels.
- The volume HUD appears alongside the system HUD; it doesn't replace it.
- Stock quotes use an unofficial Yahoo endpoint that can change without notice.

## License

MIT. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.
