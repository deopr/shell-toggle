# Hyprland setup

The toggle core is compositor-agnostic: it launches, identifies, and stops
processes, and flips a binds symlink. Only the bind syntax and the config
reload are Hyprland-specific.

These Hyprland examples are new and have not yet been verified on a live
Hyprland session, unlike the MangoWM setup. The toggle, process matching,
wallpaper sync, and adapters are the same tested code paths.

## 1. Install the binds

```sh
mkdir -p ~/.config/hypr/cfg
cp examples/hypr/binds-*.conf ~/.config/hypr/cfg/
ln -sfn binds-dms.conf ~/.config/hypr/cfg/binds-active.conf
```

Add to `~/.config/hypr/hyprland.conf`:

```ini
source = ~/.config/hypr/cfg/binds-common.conf
source = ~/.config/hypr/cfg/binds-active.conf
```

## 2. Point shell-toggle at the Hyprland binds

Edit `~/.config/shell-toggle/config`:

```bash
BINDS_LINK="$HOME/.config/hypr/cfg/binds-active.conf"
```

`shell_dms_binds="dms"` and `shell_caelestia_binds="caelestia"` then resolve
to `~/.config/hypr/cfg/binds-dms.conf` and `binds-caelestia.conf`.

## 3. Reload keybinds on switch

Hyprland does not re-read sourced files when the symlink changes. The
installer writes `~/.config/shell-toggle/post-switch`; it calls
`hyprctl reload` when `HYPRLAND_INSTANCE_SIGNATURE` is set.

## 4. Autostart

```ini
exec-once = ~/.local/bin/shell-start
exec-once = ~/.local/bin/wallpaper-sync
```

## 5. Check

```sh
shell-toggle check
```

It reports the detected session, every shell's launch/match/stop commands,
bind files, adapters, providers, and the active state. `shell-toggle status`
and `shell-toggle list` work as on Mango.
