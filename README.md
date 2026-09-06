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

```bash
./squish start
```

`start` does everything the first time: copies the code to `~/.local/share/squish`,
symlinks `~/bin/squish` onto your `PATH`, installs tab-completion, creates the
folders, and begins watching. It's idempotent — run it again any time to pick up
changes. Then just drop a video into `~/Movies/squish/clips`; the compressed copy
appears under `~/Movies/squish/compressed/<name>/` with a notification.

Two one-time shell tweaks `start` will prompt for if needed — add to `~/.zshrc`:

```bash
export PATH="$HOME/bin:$PATH"                                   # so `squish` is found
fpath=(~/.zsh/completions $fpath); autoload -Uz compinit; compinit   # tab-completion
```

## Commands

The surface is deliberately small: **read state with `status`, change it with
`config`.**

```bash
squish status              # settings + whether it's watching (the read view)
squish start              # start watching (sets everything up on first run)
squish stop               # stop watching
squish config set CRF 20  # change a setting
squish config reset       # restore defaults
squish logs               # last 40 log lines   (squish logs -f to follow)
squish help
squish version
```

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

| Thing         | Path                                                       |
| ------------- | ---------------------------------------------------------- |
| CLI (symlink) | `~/bin/squish` → `~/.local/share/squish/squish`            |
| Installed code| `~/.local/share/squish/` (entry point + `lib/`)            |
| Watch folder  | `~/Movies/squish/clips` (change with `config set WATCH_DIR`)|
| Output folder | `~/Movies/squish/compressed/` (one subfolder per video)    |
| Config        | `~/.config/squish/config`                                  |
| Completion    | `~/.zsh/completions/_squish`                               |
| launchd agent | `~/Library/LaunchAgents/com.mahesh.squish.plist`           |
| Run log       | `~/Library/Logs/squish.log`                                |
| launchd log   | `~/Library/Logs/squish.launchd.log`                        |

## Project layout

```
squish            thin entry point — resolves its path, sources lib/, dispatches
lib/
  common.sh       constants, paths, output helpers
  config.sh       load / validate / persist settings (the write side)
  agent.sh        launchd plist, start/stop, status (the read side)
  worker.sh       the run() compression pass
  cli.sh          help + command dispatch
completions/
  _squish         zsh tab-completion
```

Adding a command: write its function in the right `lib/` module, then register a
line in `cli_main()` and `cmd_help()` in `lib/cli.sh` and one in `completions/_squish`.

## How it works (and why the guards exist)

`launchd`'s `WatchPaths` is blunt — it fires many times while a file is still
copying. The `run` worker defends against that:

- **Lock directory** — one run at a time; extra triggers exit immediately.
- **Size-stability poll** — waits until the file stops growing before encoding.
- **Already-processed skip** — never re-compresses a clip that already has output.
- **Absolute ffmpeg path** — launchd gives the script almost no `PATH`.
- **Outputs outside the watch folder** — so writing results never re-fires the watcher.

> `Bootstrap failed: 5` when loading means the agent is **already loaded**, not
> broken. Re-running `squish start` handles the unload/reload for you.

## Roadmap

- `run --dry-run`, per-extension rules, configurable output naming, and more.
