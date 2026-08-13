# SyntaxFixer

A tiny floating panel for macOS that fixes the grammar and syntax of a sentence and leaves the result **on your clipboard**. No browser window, no tabs, no leaving whatever you were doing.

```
┌──────────────────────────────┐
│ ●  syntax [opus ⌄]   copied ✓│
├──────────────────────────────┤
│ ❯ this dont read good        │
├──────────────────────────────┤
│ ✓ This doesn't read well.    │
├──────────────────────────────┤
│ [ Validate ⌘↵ ]  [ Clear ⌘K ]│
└──────────────────────────────┘
```

- Always above every other window, on every desktop.
- Model picker (`haiku` / `sonnet` / `opus` / `fable`) that remembers your choice.
- Drag it from anywhere in its background; it remembers where you left it.
- The window grows on its own when the response is long.
- No Dock icon while running (it's an agent-style app), but a permanent launcher if you drag it to the Dock.

## Requirements

- macOS 14 or later.
- Xcode Command Line Tools (`xcode-select --install`) to build.
- **[Claude Code](https://claude.com/claude-code) installed and signed in** (`claude` on your `PATH`).

## How the Claude integration works

**There is no API key in this repository, in the code, or in the binary.** The app handles no credentials at all.

What it does is run the `claude` binary you already have installed and authenticated, passing the text on `stdin`:

```
claude -p --model opus --output-format text \
  --setting-sources "" --strict-mcp-config \
  --system-prompt "<rewriting instructions>" \
  "<task>"
```

Authentication is the CLI's business: it lives in the macOS keychain, Claude Code manages it, and the app never sees or touches it. If you use Claude Code with a subscription, this draws on that subscription; if you use it with your own API key, it draws on that. Either way the app is indifferent.

Three details that matter:

- **`--setting-sources ""`** — without it the CLI loads your global configuration (`CLAUDE.md` included) and contaminates the response: you get the text back with a preamble like "Here's your corrected text:" or translated into whatever language you have configured. With it, the output is only the corrected text.
- **`--system-prompt`** replaces the system prompt entirely (it doesn't append), and the process runs with its working directory in an empty temp folder so it won't load any project's `CLAUDE.md`.
- **The binary is located by known paths** (Homebrew, `~/.claude/local`, `~/.local/bin`, …) because an app launched from Finder doesn't inherit your shell's `PATH`.

### Choosing the model

The header picker uses the CLI's **aliases** (`haiku`, `sonnet`, `opus`, `fable`), not versioned IDs: an alias always resolves to the latest model in that family, so the app needs no update when a new version ships.

Timings in the menu are **measured on your machine, not hardcoded**:

- **Passive measurement.** Every real call is timed and recorded per model — a rolling average of the last 10, so a slow afternoon ages out. Only successful calls count; a timeout or a CLI error would poison the average with a time that isn't the model's.
- **Benchmark all models** (in the menu) times all four once on a fixed sentence, ~20s. It's opt-in rather than automatic on launch for two reasons: it spends four calls of quota every time, and passive measurement alone only ever tells you about the model you already use, so you'd never learn another is faster.
- **The default follows the data.** With no hand-picked model the app selects the fastest one it has measured, and the picker shows `auto` to say so. Picking a model from the menu pins it, `auto` disappears, and the measurements stop overriding you. **Forget measurements** clears the history and returns to `auto`.

Ranking needs at least 3 samples on 2 or more models before the app will claim a fastest — one sample is noise.

### About speed

Reference numbers from the developer's machine (2 runs per model) — yours may differ, which is the point of measuring locally:

| model | average |
|---|---|
| `opus` | 3.7s |
| `sonnet` | 4.4s |
| `haiku` | 5.2s |
| `fable` | 6.0s |

**Model size does not predict latency here**: `opus` measured faster than `haiku`. Since the output is a single sentence, the time is dominated by service and network overhead rather than generation — and the variance between runs is larger than the gap between models, so treat any single ranking with suspicion. `opus` is the starting default because it measured fastest. The CLI's startup, which looks like the obvious suspect, is 0.06s: it's a native binary.

Things I tried that **don't** help: dropping tools (`--allowed-tools ""`) and dynamic prompt sections (`--exclude-dynamic-system-prompt-sections`) gave the same time and degraded the result — the model swallowed the instruction and returned `"Fix it. This doesn't work well."`. If you want this to be instant you have to go straight at the API with a key, which is a different usage model (and there you *would* have a secret to protect).

## Build and install

```bash
./build.sh                                    # produces build/SyntaxFixer.app
cp -R build/SyntaxFixer.app /Applications/
```

No Xcode and no `.xcodeproj` needed: `build.sh` compiles with `swiftc`, generates the icon, assembles the bundle and signs it ad-hoc (without the signature, macOS kills the app when you open it from Finder).

For a permanent Dock launcher, drag `/Applications/SyntaxFixer.app` onto the Dock. Since it's an agent-style app, clicking it opens the panel; if it's already running, the click brings it to the front.

## Usage

| Action | Shortcut |
|---|---|
| Fix the text | `⌘↵` or the **Validate** button |
| Clear everything | `⌘K` or the **Clear** button |
| Copy the result again | click the result |
| Quit | `⌘Q` or the `×` |

The result is copied to the clipboard automatically as soon as it arrives.

## Layout

| File | What it does |
|---|---|
| `Sources/main.swift` | The floating `NSPanel`, the app lifecycle and the height fitting |
| `Sources/ContentView.swift` | The SwiftUI interface and state |
| `Sources/ClaudeRunner.swift` | Locates and runs the `claude` CLI |
| `Sources/Stats.swift` | Rolling per-model latency stats, persisted in UserDefaults |
| `make-icon.swift` | Draws the icon at the 10 sizes `iconutil` wants |
| `build.sh` | Compiles and assembles the `.app` |

If something behaves oddly, the app writes a log to `~/Library/Logs/SyntaxFixer.log`.

## License

MIT
