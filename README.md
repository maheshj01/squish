# squish

A tiny macOS CLI that watches a folder and auto-compresses any video dropped into
it with `ffmpeg`. A `launchd` agent does the watching; `squish` manages everything
— the target folder, the compression settings, and the agent itself.
**Originals are never touched.**

Typical result: a screen recording drops ~90% in size in a few seconds.

```
~/Movies/squish/
├── clips/                     drop videos here (the watch folder; untouched)
│   └── my-clip.mov
└── compressed/                one subfolder per video
    └── my-clip/
        ├── my-clip.mp4        compressed result
        └── my-clip.log        its ffmpeg log
```

`compressed/` is a sibling of `clips/`, i.e. **outside** the watched folder, on
purpose: anything written inside the watch folder would re-fire `launchd`'s
`WatchPaths` and loop the agent. For the same reason the watch folder must not be
a TCC-protected location (`~/Desktop`, `~/Documents`, `~/Downloads`) — a headless
agent is silently denied there. The run log lives at `~/Library/Logs/squish.log`.

## Requirements

- macOS
- [ffmpeg](https://ffmpeg.org/) — `brew install ffmpeg`

## Install

**Homebrew** (recommended):

```bash
brew install maheshj01/tap/squish          # latest tagged release
# or the latest main, no release needed:
brew install --HEAD maheshj01/tap/squish
squish start
```

**Manual / from a clone:**

```bash
./install.sh      # copies to ~/.local/share/squish, links ~/bin/squish,
                  # installs zsh completion, then runs `squish start`
```

**Dev (run straight from the repo):**

```bash
./squish start    # uses the repo code in place; no copying
```

`squish start` **creates the default folders if they don't exist**
(`~/Movies/squish/clips` and `~/Movies/squish/compressed`) and loads the launchd
agent. Then drop a video into `clips/`; the compressed copy appears under
`compressed/<name>/` with a notification. File placement (the CLI on `PATH`,
`lib/`, the completion) is done by the installer — Homebrew or `install.sh` —
not by `start`.

For a manual install, add these to `~/.zshrc` once (the installer prints them if
needed); Homebrew wires both up for you:

```bash
export PATH="$HOME/bin:$PATH"                                   # so `squish` is found
fpath=(~/.zsh/completions $fpath); autoload -Uz compinit; compinit   # tab-completion
```

## Commands

The surface is deliberately small: **read state with `status`, change it with
`config`.**

```bash
squish status              # settings + whether it's watching (the read view)
squish compress <file>    # compress one file now, prints the output path
squish start              # start watching (sets everything up on first run)
squish stop               # stop watching
squish config set CRF 20  # change a setting
squish config reset       # restore defaults
squish clean              # empty clips AND compressed (asks y/N)
squish clean clips        # empty only the watched inputs
squish clean compressed   # empty only the compressed outputs
squish logs               # last 40 log lines   (squish logs -f to follow)
squish help
squish version
```

`clean` shows what it will delete and asks for a `y/N` confirmation first; the
`clips/` and `compressed/` folders themselves are kept, only their contents go.

### One-shot compression

`compress` handles a single file synchronously — no watch folder needed — and
prints the output path to stdout (handy for scripts and agents):

```bash
squish compress ~/Desktop/demo.mov                 # -> ~/Movies/squish/compressed/demo/demo.mp4
squish compress demo.mov --destination ~/out       # -> ~/out/demo.mp4  (+ demo.log)
squish compress demo.mov --destination ~/out/small.mp4   # exact output path
```

Without `--destination` it uses the same `compressed/<name>/` layout as the
watcher. Progress and the size summary go to stderr; stdout is only the path.

### Settings (`config set <key> <value>`)

| Key              | Default                     | Meaning                                    |
| ---------------- | --------------------------- | ------------------------------------------ |
| `WATCH_DIR`      | `~/Movies/squish/clips`     | Folder to watch                            |
| `COMPRESSED_DIR` | `~/Movies/squish/compressed`| Where results go (kept outside the watch folder) |
| `CRF`            | `23`                        | Quality 0–51, lower = better/bigger        |
| `PRESET`         | `medium`                    | ffmpeg speed/size tradeoff                 |
| `AUDIO_BITRATE`  | `128k`                      | Audio bitrate                              |
| `NOTIFY`         | `1`                         | `0` to silence macOS notifications         |

Values are validated on write (a bad value is rejected, not saved) and read fresh
on every run. Changing `WATCH_DIR` regenerates and reloads the launchd agent,
since that path is baked into the plist.

Tab-completion (zsh) completes commands, keys, presets, and folders.

## Where things live

Runtime files (created/managed by `squish`, same for every install method):

| Thing         | Path                                                       |
| ------------- | ---------------------------------------------------------- |
| Watch folder  | `~/Movies/squish/clips` (change with `config set WATCH_DIR`)|
| Output folder | `~/Movies/squish/compressed/` (one subfolder per video)    |
| Config        | `~/.config/squish/config`                                  |
| launchd agent | `~/Library/LaunchAgents/com.mahesh.squish.plist`           |
| Run log       | `~/Library/Logs/squish.log`                                |
| launchd log   | `~/Library/Logs/squish.launchd.log`                        |

Program files (placed by the installer):

| Install     | CLI on PATH             | code + completion                              |
| ----------- | ----------------------- | ---------------------------------------------- |
| Homebrew    | `$(brew --prefix)/bin/squish` | `…/libexec/` · `…/share/zsh/site-functions/_squish` |
| `install.sh`| `~/bin/squish`          | `~/.local/share/squish/` · `~/.zsh/completions/_squish` |

## Project layout

```
squish            thin entry point — resolves its path, sources lib/, dispatches
lib/
  common.sh       app identity, launchd + runtime paths, output helpers
  config.sh       load / validate / persist settings (the write side)
  agent.sh        launchd plist, start/stop, status (the read side)
  worker.sh       compression — the watch pass (run) and one-shot (compress)
  clean.sh        empty the clips / compressed folders (with confirm)
  cli.sh          help + command dispatch
completions/
  _squish         zsh tab-completion
install.sh        manual/dev installer (non-Homebrew)
```

The Homebrew formula lives in the separate tap repo
[`maheshj01/homebrew-tap`](https://github.com/maheshj01/homebrew-tap), not here.

Adding a command: write its function in the right `lib/` module, then register a
line in `cli_main()` and `cmd_help()` in `lib/cli.sh` and one in `completions/_squish`.

## How it works (and why the guards exist)

`launchd`'s `WatchPaths` is blunt — it fires many times while a file is still
copying. The `run` worker defends against that:

- **Lock directory** — one run at a time; extra triggers exit immediately.
- **Size-stability poll** — waits until the file stops growing before encoding.
- **Already-processed skip** — never re-compresses a clip that already has output.
- **Mid-run rescan** — a run holds the lock, then rescans and repeats until a pass
  compresses nothing new, so a video dropped while encoding is caught in the same run.
- **Absolute ffmpeg path** — launchd gives the script almost no `PATH`.
- **Outputs outside the watch folder** — so writing results never re-fires the watcher.

> `Bootstrap failed: 5` when loading means the agent is **already loaded**, not
> broken. Re-running `squish start` handles the unload/reload for you.

## Publishing to Homebrew

Standard two-repo tap layout — this repo is the **source**; the formula lives in
the separate [`maheshj01/homebrew-tap`](https://github.com/maheshj01/homebrew-tap)
repo, which scales to future tools:

```
maheshj01/squish          this repo — the source
maheshj01/homebrew-tap    the tap  — Formula/squish.rb, later Formula/<next>.rb
```

### Releasing a new version

1. Bump `VERSION` in `lib/common.sh`, then commit and push.
2. Tag the source and push the tag (keep it in sync with `VERSION`):
   ```bash
   git tag v0.2.0 && git push --tags
   ```
3. Hash the release tarball:
   ```bash
   curl -sL https://github.com/maheshj01/squish/archive/refs/tags/v0.2.0.tar.gz | shasum -a 256
   ```
4. In the **homebrew-tap** repo, update `Formula/squish.rb` — the `url` tag and
   the `sha256` from step 3 — then commit and push.
5. Users upgrade with:
   ```bash
   brew update && brew upgrade squish
   ```

Test changes from `main` before tagging: `brew install --HEAD maheshj01/tap/squish`.

## Roadmap

- `run --dry-run`, per-extension rules, configurable output naming, and more.
