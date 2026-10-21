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

cat <<EOF

Binaries: $bindir
Config:   $confdir/config

Next:
  1. Make sure $bindir is in the PATH of the process that launches
     your compositor (Mango inherits SDDM's PATH), or use absolute
     paths in keybinds.
  2. Copy the examples/mango files into your compositor config and make
     cfg/binds-active.conf a symlink to one of the binds-*.conf files.
  3. Add to autostart:
       shell-start &
       wallpaper-sync &
  4. Bind shell-toggle, then press it.
EOF
