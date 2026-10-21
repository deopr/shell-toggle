#!/usr/bin/env bash
# Install shell-toggle into ~/.local/bin and ~/.config/shell-toggle.
#
#   ./install.sh                 user install (default)
#   PREFIX=/usr/local ./install.sh
#
# An existing config is never overwritten; the shipped example is written
# next to it as config.example instead.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
prefix="${PREFIX:-$HOME/.local}"
confdir="${XDG_CONFIG_HOME:-$HOME/.config}/shell-toggle"
bindir="$prefix/bin"

install -d "$bindir" "$confdir/adapters" "$confdir/wallpaper"
install -m755 "$here"/bin/* "$bindir"/
install -m755 "$here"/examples/adapters/* "$confdir/adapters"/
install -m755 "$here"/examples/wallpaper/* "$confdir/wallpaper"/

if [ -e "$confdir/config" ]; then
    install -m644 "$here/examples/config" "$confdir/config.example"
    echo "kept existing config: $confdir/config"
    echo "new example:          $confdir/config.example"
else
    install -m644 "$here/examples/config" "$confdir/config"
    echo "installed config:     $confdir/config"
fi

install -m755 "$here/examples/hooks/post-switch" "$confdir/post-switch.example"
if [ -e "$confdir/post-switch" ]; then
    echo "kept existing hook:   $confdir/post-switch"
else
    install -m755 "$here/examples/hooks/post-switch" "$confdir/post-switch"
    echo "installed hook:       $confdir/post-switch"
fi

cat <<EOF

Binaries: $bindir
Config:   $confdir/config

Next:
  1. Make sure $bindir is in the PATH of the process that launches
     your compositor (Mango inherits SDDM's PATH), or use absolute
     paths in keybinds.
  2. Copy the examples/mango (MangoWM) or examples/hypr (Hyprland)
     binds into your compositor config and make binds-active.conf a
     symlink to one of the binds-*.conf files. Other compositors can
     source the same symlink from their own config.
  3. Set BINDS_LINK in $confdir/config to that symlink.
  4. Add to autostart:
       shell-start &
       wallpaper-sync &
  5. Bind shell-toggle, press it, then run: shell-toggle check
EOF
