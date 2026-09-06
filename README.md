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
./squish install
```

This copies the code to `~/.local/share/squish`, symlinks `~/bin/squish` onto
your `PATH`, generates the launchd agent, creates the watch folder, and starts
watching. Make sure `~/bin` is on your `PATH` (add `export PATH="$HOME/bin:$PATH"`
to `~/.zshrc` if needed — `install` warns you if it isn't).

Then just drop a video into the watch folder — a compressed copy appears in
`outputs/` and you get a macOS notification when it's done.

## Usage

```
squish <command> [args]
```

### Target folder
```bash
squish folder                 # print the current watch folder
squish folder ~/Movies/caps   # set it (recreates + reloads the agent)
```
Changing the folder also updates the launchd `WatchPaths` and reloads the agent,
because that path is baked into the plist — `squish` handles that for you.

### Compression config
```bash
squish config show            # effective settings + where they come from
squish config get CRF
squish config set CRF 20      # better quality, bigger file
squish config set PRESET slow
squish config set NOTIFY 0    # silence notifications
squish config reset           # restore all defaults
squish config path            # where the config file lives
```

| Key              | Default                     | Meaning                                    |
| ---------------- | --------------------------- | ------------------------------------------ |
| `WATCH_DIR`      | `~/Movies/squish/clips`     | Folder to watch (use `folder` to change)   |
| `COMPRESSED_DIR` | `~/Movies/squish/compressed`| Where results go (must be outside the watch folder) |
| `CRF`            | `23`                        | Quality 0–51, lower = better/bigger        |
| `PRESET`         | `medium`                    | ffmpeg speed/size tradeoff                 |
| `AUDIO_BITRATE`  | `128k`                      | Audio bitrate                              |
| `NOTIFY`         | `1`                         | `0` to silence macOS notifications         |

Settings are validated on write (a bad value is rejected, not saved) and read
fresh on every run — no reload needed except for `WATCH_DIR` (which is baked into
the launchd plist, so changing it regenerates and reloads the agent).

### Agent control
```bash
squish status                 # config + is the agent loaded?
squish start | stop | restart
squish logs                   # last 40 log lines
squish logs -f                # follow live
squish uninstall              # unload + remove the agent
```

### Run by hand
```bash
squish run                    # the worker launchd calls; safe to run yourself
```

## Where things live

| Thing         | Path                                                       |
| ------------- | ---------------------------------------------------------- |
| CLI (symlink) | `~/bin/squish` → `~/.local/share/squish/squish`            |
| Installed code| `~/.local/share/squish/` (entry point + `lib/`)            |
| Watch folder  | `~/Movies/squish/clips` (default; change with `squish folder`) |
| Output folder | `~/Movies/squish/compressed/` (one subfolder per video)    |
| Config        | `~/.config/squish/config`                                  |
| launchd agent | `~/Library/LaunchAgents/com.mahesh.squish.plist`           |
| Run log       | `~/Library/Logs/squish.log`                                |
| launchd log   | `~/Library/Logs/squish.launchd.log`                        |

## Project layout

```
squish            thin entry point — resolves its path, sources lib/, dispatches
lib/
  common.sh       constants, paths, output helpers
  config.sh       load / validate / persist settings
  agent.sh        launchd plist generation, install/uninstall/status
  worker.sh       the run() compression pass
  cli.sh          help + command dispatch
```

Adding a feature: write its function in the right `lib/` module, then register a
line in `cli_main()` and `cmd_help()` in `lib/cli.sh`.

## How it works (and why the guards exist)

`launchd`'s `WatchPaths` is blunt — it fires many times while a file is still
copying. The `run` worker defends against that:

- **Lock directory** — one run at a time; extra triggers exit immediately.
- **Size-stability poll** — waits until the file stops growing before encoding.
- **Already-processed skip** — never re-compresses an existing `_output.mp4`.
- **Absolute ffmpeg path** — launchd gives the script almost no `PATH`.

> `Bootstrap failed: 5` when loading means the agent is **already loaded**, not
> broken. `squish restart` handles the unload/reload for you.

## Roadmap

- `run --dry-run`, per-extension rules, configurable output naming, and more.
