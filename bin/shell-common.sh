#!/usr/bin/env bash
# shell-common.sh - config loading and shared helpers for the shell-toggle
# suite. This file is sourced, not executed.
#
# The config is plain bash. It defines an ordered SHELLS array and one
# shell_<id>_* block per shell; see examples/config.
#
# shell ids become part of variable names, so they must match
# [A-Za-z_][A-Za-z0-9_]* and must be unique.

[ -n "${_SHELL_COMMON_LOADED:-}" ] && return 0
_SHELL_COMMON_LOADED=1

_SHELL_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

: "${SHELL_TOGGLE_CONF:=${XDG_CONFIG_HOME:-$HOME/.config}/shell-toggle/config}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"

SHELL_TOGGLE_CONF_DIR="$(dirname -- "$SHELL_TOGGLE_CONF")"
STATE_FILE="$XDG_STATE_HOME/shell-mode"
LOCK_FILE="$XDG_STATE_HOME/shell-toggle.lock"
PID_FILE="$XDG_STATE_HOME/shell-toggle.pid"

# Shared defaults. A config can override any of these.
BINDS_LINK="$HOME/.config/mango/cfg/binds-active.conf"
SPAWN_TIMEOUT="6"
REAP_GRACE="0.25"
DEFAULT_WARMUP="0.35"
SYNC_WALLPAPER="1"
NOTIFY="1"
WALLPAPER_POLL="1"
WALLPAPER_SYNC="${WALLPAPER_SYNC:-$_SHELL_LIB_DIR/wallpaper-sync}"

SHELLS=""
SHELL_CONFIG_OK=0

if [ -r "$SHELL_TOGGLE_CONF" ]; then
    # shellcheck source=/dev/null
    . "$SHELL_TOGGLE_CONF"
    SHELL_CONFIG_OK=1
fi

# Accept SHELLS="dms caelestia" as well as the documented array form.
# SHELLS starts as a scalar on purpose: assigning "a b" to a variable that
# is already an array stores it as a single element instead of two ids.
if ! declare -p SHELLS 2>/dev/null | grep -q '^declare -a'; then
    _shells_scalar="$SHELLS"
    read -r -a SHELLS <<< "$_shells_scalar"
    unset _shells_scalar
fi

# --------------------------------------------------------------------------
# per-shell settings
# --------------------------------------------------------------------------
# Config keys are named shell_<id>_<field>. Two accessors are provided:
# shell_get for scalars and shell_get_array for arrays. Everything is
# looked up through declare -p first, so unset keys never trip `set -u`.

_shell_var() { printf 'shell_%s_%s' "$1" "$2"; }

_shell_has() { declare -p "$1" >/dev/null 2>&1; }

shell_get() {
    local id="$1" field="$2" default="${3:-}" name val
    name="$(_shell_var "$id" "$field")"
    if ! _shell_has "$name"; then
        printf '%s' "$default"
        return 0
    fi
    local -n ref="$name"
    case "$(declare -p "$name" 2>/dev/null)" in
        "declare -a"*) val="${ref[*]}" ;;
        *)             val="$ref" ;;
    esac
    [ -n "$val" ] || val="$default"
    printf '%s' "$val"
}

shell_get_array() {
    local id="$1" field="$2" dest="$3" name item
    local -n out="$dest"
    out=()
    name="$(_shell_var "$id" "$field")"
    _shell_has "$name" || return 0
    local -n src="$name"
    case "$(declare -p "$name" 2>/dev/null)" in
        "declare -a"*) for item in "${src[@]}"; do [ -n "$item" ] && out+=("$item"); done ;;
        *)             [ -n "$src" ] && out=("$src") ;;
    esac
}

shell_name() { shell_get "$1" name "$1"; }
shell_warmup() { shell_get "$1" warmup "$DEFAULT_WARMUP"; }
shell_timeout() { shell_get "$1" timeout "$SPAWN_TIMEOUT"; }

# --------------------------------------------------------------------------
# validation and state
# --------------------------------------------------------------------------

validate_shells() {
    local i j id
    if ((${#SHELLS[@]} == 0)); then
        printf 'shell-toggle: SHELLS is empty - edit %s\n' "$SHELL_TOGGLE_CONF" >&2
        return 1
    fi
    for ((i = 0; i < ${#SHELLS[@]}; i++)); do
        id="${SHELLS[i]}"
        if [[ ! "$id" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            printf 'shell-toggle: invalid shell id "%s" (use letters, digits, _)\n' "$id" >&2
            return 1
        fi
        for ((j = 0; j < i; j++)); do
            if [ "${SHELLS[j]}" = "$id" ]; then
                printf 'shell-toggle: duplicate shell id "%s"\n' "$id" >&2
                return 1
            fi
        done
    done
    return 0
}

valid_shell() {
    local s
    for s in "${SHELLS[@]}"; do
        [ "$s" = "$1" ] && return 0
    done
    return 1
}

current_shell() {
    local m=""
    if [ -r "$STATE_FILE" ]; then
        read -r m < "$STATE_FILE" || true
    fi
    valid_shell "$m" || m="${SHELLS[0]}"
    printf '%s' "$m"
}

shell_write_state() {
    mkdir -p "$XDG_STATE_HOME" || return 1
    printf '%s\n' "$1" > "$STATE_FILE"
}

# cycle_shell <current> <+1|-1>
cycle_shell() {
    local cur="$1" offset="$2" i n="${#SHELLS[@]}"
    for i in "${!SHELLS[@]}"; do
        if [ "${SHELLS[i]}" = "$cur" ]; then
            printf '%s' "${SHELLS[$(((i + offset + n) % n))]}"
            return 0
        fi
    done
    printf '%s' "${SHELLS[0]}"
}

# --------------------------------------------------------------------------
# process probing and lifecycle
# --------------------------------------------------------------------------
# match is a pgrep/pkill argument list, not a pattern by itself:
#   (-x waybar)                 exact process name
#   (-f '^...qs -c foo$')       full command line, anchored
# shell-toggle never puts these patterns on its own command line, but
# anchoring is still the safe habit: an unanchored pattern can match the
# shell that invoked the toggle and make it see itself as "already running".

shell_pids() {
    local pat=()
    shell_get_array "$1" match pat
    ((${#pat[@]})) || return 1
    pgrep "${pat[@]}" 2>/dev/null
}

shell_alive() { [ -n "$(shell_pids "$1")" ]; }

_kill_match() {
    local id="$1" field="$2" sig="$3" pat=()
    shell_get_array "$id" "$field" pat
    ((${#pat[@]})) || return 0
    pkill "$sig" "${pat[@]}" 2>/dev/null || true
}

shell_log_file() { printf '%s/shell-toggle-%s.log' "${TMPDIR:-/tmp}" "$1"; }

shell_run_hook() {
    local hook="$SHELL_TOGGLE_CONF_DIR/$1"
    if [ -x "$hook" ]; then
        "$hook" >/dev/null 2>&1 || true
    fi
}

shell_launch() {
    local id="$1" log cmd=() envs=()
    log="$(shell_log_file "$id")"
    shell_get_array "$id" launch cmd
    ((${#cmd[@]})) || return 1
    shell_get_array "$id" env envs
    (
        if ((${#envs[@]})); then
            export "${envs[@]}"
        fi
        # setsid detaches from the toggle's session. 9>&- closes the flock
        # fd; if a launched shell inherited it, it would hold the lock for
        # its whole life and silently block every later toggle.
        exec setsid "${cmd[@]}"
    ) >"$log" 2>&1 </dev/null 9>&- &
    printf '%s\n' "$!" > "$PID_FILE"
}

shell_wait_up() {
    local id="$1" timeout deadline
    timeout="$(shell_timeout "$id")"
    deadline=$(( $(date +%s) + timeout ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if shell_alive "$id"; then
            sleep 0.12
            return 0
        fi
        sleep 0.1
    done
    return 1
}

shell_reap() {
    local id="$1" stop=()
    shell_run_hook "prep-$id"

    shell_get_array "$id" stop stop
    if ((${#stop[@]})); then
        "${stop[@]}" >/dev/null 2>&1 || true
    fi

    _kill_match "$id" match -TERM
    _kill_match "$id" also_match -TERM
    sleep "$REAP_GRACE"
    _kill_match "$id" match -KILL
    _kill_match "$id" also_match -KILL
}

# --------------------------------------------------------------------------
# keybind set swap
# --------------------------------------------------------------------------
# Optional: if BINDS_LINK is a symlink, point it at binds-<id's binds>.conf.
# On Mango, auto_reload_config picks this up immediately. Other compositors
# can run `hyprctl reload` (or equivalent) from a post-switch hook.

shell_swap_binds() {
    local id="$1" want dir
    want="$(shell_get "$id" binds)"
    [ -n "$want" ] || return 0
    [ -L "$BINDS_LINK" ] || return 0
    dir="$(dirname -- "$BINDS_LINK")"
    [ -r "$dir/binds-$want.conf" ] || return 0
    ln -sfn "binds-$want.conf" "$BINDS_LINK" 2>/dev/null || return 0
}

# --------------------------------------------------------------------------
# notifications
# --------------------------------------------------------------------------

shell_notify() {
    [ "${NOTIFY:-1}" = "1" ] || return 0
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a shell-toggle -u "${2:-low}" shell-toggle "$1" >/dev/null 2>&1 || true
}

shell_die() {
    shell_notify "$1" critical
    printf 'shell-toggle: %s\n' "$1" >&2
    exit 1
}
