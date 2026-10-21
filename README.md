# shell-toggle

**Hot-swap the status shell of a live Wayland desktop — one keypress, any number of shells.**

`shell-toggle` was built to flip a MangoWM session between
[DankMaterialShell](https://danklinux.com) and
[Caelestia](https://github.com/caelestia-dots/shell), but the switcher itself
is not attached to either one. Every shell is described in a config file: how
to launch it, how to recognise its process, how to stop it, and optionally
which keybinds and wallpaper provider belong to it. Want
DMS ⇄ Caelestia ⇄ Waybar? Append an id to `SHELLS`, add a block, done.

The important part is the handoff: the incoming shell is started first,
allowed to paint, and only then is the outgoing shell reaped. A broken
incoming shell cannot cost you the session, and you never stare at a bare
desktop in between.

```text
SUPER+SHIFT+PgUp     shell-toggle          next shell
SUPER+SHIFT+PgDn     shell-toggle status   which shell is active?
```

## Why it exists

Swapping a shell normally means logging out. This does it in place, and
solves the annoyances that come with that:

- **Overlap, not a hard cut.** The new bar animates in while the old one is
  still on screen. A real crossfade is impossible: wlr-layer-shell has no
  "surface is going away" callback, shells expose no opacity setter over IPC,
  and Mango disables animations for layer-shell surfaces. Starting the
  incoming shell first is the whole effect.
- **Any number of shells.** `SHELLS` is an ordered array; `toggle` walks it,
  `prev` walks it backwards, or name a shell directly.
- **Per-shell keybinds.** Each shell can point at its own `binds-<id>.conf`.
  A symlink is flipped as part of the switch, so the same key does the right
  thing in every mode.
- **Wallpaper continuity.** Optional providers read/write each shell's own
  wallpaper state before the switch, so changing shells does not change your
  background.
- **Hardware keys never depend on a shell.** Volume, mic, media and
  brightness are driven natively by `shellctl`.
- **Failure safety.** If the new shell dies during startup, the old one is
  left running and the state file is not touched.
- **One switch at a time.** `flock` serialises rapid keypresses.

## Install

```sh
git clone https://github.com/deopr/shell-toggle.git
cd shell-toggle
./install.sh
```

The installer puts the scripts in `~/.local/bin`, and the config, adapters
and wallpaper providers in `~/.config/shell-toggle`. It keeps an existing
config and writes the shipped one as `config.example` instead.

Requirements:

| What | Why |
| --- | --- |
| bash ≥ 4.3, `procps`, util-linux | core (`pgrep`, `setsid`, `flock`) |
| a Wayland compositor | layer-shell shells need one |
| `libnotify` | optional notifications |
| `python3` | DMS wallpaper provider |
| `wireplumber`, `playerctl`, `light` | optional hardware keys in `shellctl` |

## Configure

The config is plain bash, sourced by every tool:

```bash
SHELLS=(dms caelestia)

shell_dms_name="DankMaterialShell"
shell_dms_match=(-x dms)
shell_dms_also_match=(-f '^(/[^ ]*/)?qs -p /run/user/[0-9]+/danklinux-shell/')
shell_dms_launch=(dms run)
shell_dms_stop=(dms kill)
shell_dms_warmup="0.45"
shell_dms_binds="dms"
shell_dms_adapter="$HOME/.config/shell-toggle/adapters/dms"
shell_dms_wallpaper="$HOME/.config/shell-toggle/wallpaper/dms"

shell_caelestia_name="Caelestia"
shell_caelestia_match=(-f '^(/[^ ]*/)?qs -c caelestia$')
shell_caelestia_launch=(qs -c caelestia)
shell_caelestia_env=(
    CAELESTIA_LIB_DIR=/usr/lib64/caelestia
    CAELESTIA_XKB_RULES_PATH=/usr/share/X11/xkb/rules/base.lst
)
shell_caelestia_binds="caelestia"
shell_caelestia_adapter="$HOME/.config/shell-toggle/adapters/caelestia"
shell_caelestia_wallpaper="$HOME/.config/shell-toggle/wallpaper/caelestia"
```

Every key is optional except `match` and `launch`:

| Key | Meaning |
| --- | --- |
| `name` | label for notifications (defaults to the id) |
| `match` | `pgrep`/`pkill` argument list identifying the shell |
| `also_match` | extra match for helper processes that must die with it |
| `launch` | argv used to start the shell |
| `stop` | optional graceful shutdown, run before signals |
| `env` | `KEY=VALUE` array exported before launch |
| `warmup` | seconds to let the incoming shell animate (default 0.35) |
| `timeout` | seconds to wait for it to appear (default `SPAWN_TIMEOUT`) |
| `binds` | suffix of `binds-<x>.conf` to activate |
| `adapter` | executable handling `shellctl` panel/screenshot commands |
| `wallpaper` | provider executable with `get` / `set PATH` |

Shared keys: `BINDS_LINK`, `SPAWN_TIMEOUT`, `REAP_GRACE`, `DEFAULT_WARMUP`,
`SYNC_WALLPAPER`, `WALLPAPER_POLL`, `NOTIFY`.

### Adding a shell

Append the id to `SHELLS` and add a block. A bar like Waybar needs nothing
else:

```bash
SHELLS=(dms caelestia waybar)

shell_waybar_name="Waybar"
shell_waybar_match=(-x waybar)
shell_waybar_launch=(waybar)
shell_waybar_warmup="0.20"
```

Another quickshell config works the same way, by pointing the launch command
at its config:

```bash
shell_noctalia_launch=(qs -p /path/to/noctalia/shell.qml)
shell_noctalia_match=(-f '^(/[^ ]*/)?qs -p /path/to/noctalia/shell.qml$')
```

`adapter`, `binds`, `wallpaper` and `stop` are all optional. Without an
adapter, `shellctl`'s UI keys are simply inert for that shell while volume,
media and brightness keep working.

### Process matching

`match` is passed straight to `pgrep`/`pkill`, so it is an argument list, not
a glob:

```bash
match=(-x waybar)                      # exact process name
match=(-f '^(/[^ ]*/)?qs -c foo$')     # full command line, anchored
```

Anchor `-f` patterns. An unanchored pattern such as `qs -c caelestia` can
match the shell that invoked the toggle (or a CLI call that merely mentions
the name), making the switcher think a shell is already running.

DMS is the reason `also_match` exists: `dms run` owns a quickshell child,
and `dms` is also the name of the CLI. Matching it by exact process name and
killing its `/run/user/.../danklinux-shell/` child with `also_match` keeps the
two shells from being confused with each other.

## MangoWM integration

Copy the files in `examples/mango` into `~/.config/mango/cfg`, then:

```ini
# ~/.config/mango/config.conf
source = ./cfg/keybinds.conf
```

```ini
# ~/.config/mango/cfg/keybinds.conf
source = ./cfg/binds-common.conf
source = ./cfg/binds-active.conf
```

```sh
ln -sfn binds-dms.conf ~/.config/mango/cfg/binds-active.conf
```

Autostart:

```ini
exec_once = ~/.local/bin/shell-start &
exec_once = ~/.local/bin/wallpaper-sync &
```

Binds (in `binds-common.conf`, so they survive every switch):

```ini
bind = SUPER+SHIFT, Prior, spawn, ~/.local/bin/shell-toggle
bind = SUPER+SHIFT, Next, spawn, ~/.local/bin/shell-toggle status
```

Mango expands `~` in `spawn`, but it inherits SDDM's `PATH`, which usually
does not include `~/.local/bin` — hence the absolute paths.

`shell-toggle` flips `binds-active.conf` only after the new shell is alive.
Mango's `auto_reload_config` applies it immediately, so the keymap changes at
the same moment the bar does.

## Other compositors

The core has no Mango dependency: launch, match, stop and wallpaper sync are
all process/file level. The binds symlink is optional and skipped when
`BINDS_LINK` is not a symlink.

- **Hyprland:** point `BINDS_LINK` at a file sourced by your Hyprland config
  and copy `post-switch.example` to `~/.config/shell-toggle/post-switch` with
  `hyprctl reload` uncommented.
- **Sway/niri:** same idea; run your config reload (or nothing) from the hook.
- **i3/X11:** process switching works for X11 bars, but quickshell-based
  shells require Wayland.

To be clear: this swaps the **shell/bar layer inside a running compositor**.
It is not a compositor hot-swap — Hyprland and i3 cannot replace each other
inside a live session.

## Wallpaper providers

Each shell points at a provider executable:

```bash
shell_<id>_wallpaper="$HOME/.config/shell-toggle/wallpaper/<id>"
```

The provider implements:

```sh
provider get        # print the stored wallpaper path
provider set PATH   # store it
```

Bundled providers cover DMS (`session.json` → `wallpaperPath`) and Caelestia
(`path.txt` + `current` symlink). The sync refuses to write to a shell that is
running, because that shell would keep its in-memory copy and clobber the
file on exit. A 1-second polling daemon keeps the inactive shells in step;
`shell-toggle` also runs `wallpaper-sync --once` before every switch, so even
a change made one second before pressing the key is carried over.

```sh
wallpaper-sync --status
wallpaper-sync --once
```

## Commands

```text
shell-toggle                next shell
shell-toggle next|prev      cycle forward/back
shell-toggle <id>           switch to a configured shell
shell-toggle list           all shells, * marks the active one
shell-toggle status         active shell and whether it is running
```

```text
shellctl panel-toggle launcher
shellctl panel-toggle control-center
shellctl screenshot-region
shellctl volume-up
shellctl media toggle
```

`shellctl` hardware verbs are shell-independent. UI verbs are handed to the
active shell's adapter; bundled adapters exist for DMS and Caelestia.

## Files

| Path | Purpose |
| --- | --- |
| `~/.config/shell-toggle/config` | shell definitions |
| `~/.config/shell-toggle/adapters/` | panel/screenshot adapters |
| `~/.config/shell-toggle/wallpaper/` | wallpaper providers |
| `~/.local/state/shell-mode` | active shell id |
| `/tmp/shell-toggle-<id>.log` | stdout/stderr of the last launch |
| `~/.local/state/shell-toggle.lock` | switch serialisation |

## Troubleshooting

**A shell did not come up.** Check `/tmp/shell-toggle-<id>.log`. On failure
the previous shell is intentionally left running.

**The old bar stays.** The outgoing shell's `match` is wrong. Run the same
pgrep with the same arguments, e.g. `pgrep -x waybar` or
`pgrep -f '^(/[^ ]*/)?qs -c caelestia$'`.

**`toggle` thinks the shell is already running.** The pattern matches the
toggle itself. Anchor `-f` patterns and avoid bare `-f "qs"`.

**UI keys do nothing.** The active shell has no `adapter`, or the configured
adapter is not executable. Hardware keys are unaffected.

**DMS config on Mango says `Unknown keyword: monitorrule`.** DMS 1.6.x writes
the pre-0.17.5 Mango key dialect. Use the `dms-git` build, or run
`dms config mango-migrate` and switch the generated fragments to snake_case.

**Wallpaper did not follow.** `wallpaper-sync --status` shows both stored
values. A provider returns failure if its state file does not exist yet; run
each shell once so it writes its own state.

## Uninstall

```sh
rm -f ~/.local/bin/{shell-toggle,shell-start,shellctl,wallpaper-sync,shell-common.sh}
rm -rf ~/.config/shell-toggle
rm -f ~/.local/state/shell-mode ~/.local/state/shell-toggle.*
```

## License

MIT. Built while setting up a MangoWM rice; thanks to the DMS, Caelestia and
quickshell folks for the shells worth switching between.
