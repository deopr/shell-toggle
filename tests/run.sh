#!/usr/bin/env bash
# Integration tests: fake shells, fake adapters, fake wallpaper state.
# No real desktop is touched. Run from anywhere:
#
#   ./tests/run.sh
#
# Linux only: uses pgrep/pkill, setsid, /proc and symlinked sleep binaries.
set -uo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
T="$(mktemp -d "${TMPDIR:-/tmp}/shell-toggle-test.XXXXXX")"

FAKE_A=stfakeaaa
FAKE_B=stfakebbb

mkdir -p "$T/home/.config/mango/cfg" "$T/home/.config/shell-toggle/adapters" \
         "$T/state" "$T/wall"
export HOME="$T/home"
export XDG_STATE_HOME="$T/state"
export XDG_CONFIG_HOME="$T/home/.config"
export SHELL_TOGGLE_CONF="$T/home/.config/shell-toggle/config"
export TESTDIR="$T"

ln -s "$(command -v sleep)" "$T/$FAKE_A"
ln -s "$(command -v sleep)" "$T/$FAKE_B"
touch "$T/wall/img1.png" "$T/wall/img2.png"
printf '%s\n' "$T/wall/img1.png" > "$T/wall/a.txt"
printf '%s\n' "$T/wall/img2.png" > "$T/wall/b.txt"

cat > "$T/wall-a" <<'EOF'
#!/usr/bin/env bash
f="$TESTDIR/wall/a.txt"
case "${1:-get}" in
    get) cat "$f" ;;
    set) printf '%s\n' "$2" > "$f" ;;
esac
EOF
cat > "$T/wall-b" <<'EOF'
#!/usr/bin/env bash
f="$TESTDIR/wall/b.txt"
case "${1:-get}" in
    get) cat "$f" ;;
    set) printf '%s\n' "$2" > "$f" ;;
esac
EOF
cat > "$T/home/.config/shell-toggle/adapters/$FAKE_A" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TESTDIR/adapter.log"
EOF
chmod +x "$T/wall-a" "$T/wall-b" \
         "$T/home/.config/shell-toggle/adapters/$FAKE_A"

cat > "$SHELL_TOGGLE_CONF" <<EOF
SHELLS=(aaa bbb ccc)
BINDS_LINK="\$HOME/.config/mango/cfg/binds-active.conf"
NOTIFY="0"
SYNC_WALLPAPER="1"
WALLPAPER_POLL="1"
DEFAULT_WARMUP="0.05"
SPAWN_TIMEOUT="1"
REAP_GRACE="0.1"

shell_aaa_name="Test A"
shell_aaa_match=(-x $FAKE_A)
shell_aaa_launch=("$T/$FAKE_A" 300)
shell_aaa_binds="aaa"
shell_aaa_adapter="\$HOME/.config/shell-toggle/adapters/$FAKE_A"
shell_aaa_wallpaper="$T/wall-a"
shell_aaa_warmup="0.05"

shell_bbb_name="Test B"
shell_bbb_match=(-x $FAKE_B)
shell_bbb_launch=("$T/$FAKE_B" 301)
shell_bbb_env=(TEST_MARK=yes)
shell_bbb_binds="bbb"
shell_bbb_wallpaper="$T/wall-b"
shell_bbb_warmup="0.05"

shell_ccc_name="Broken C"
shell_ccc_match=(-x stfakeccc)
shell_ccc_launch=(false)
shell_ccc_warmup="0.05"
EOF

for b in aaa bbb; do
    printf 'bind = SUPER, x, spawn, %s\n' "$b" > "$HOME/.config/mango/cfg/binds-$b.conf"
done
ln -sfn binds-aaa.conf "$HOME/.config/mango/cfg/binds-active.conf"
printf 'aaa\n' > "$XDG_STATE_HOME/shell-mode"

pass=0 fail=0
ok()   { printf 'ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL %s\n' "$1"; fail=$((fail+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

wpid=""
spid=""
cleanup() {
    [ -n "$wpid" ] && kill "$wpid" 2>/dev/null || true
    [ -n "$spid" ] && kill "$spid" 2>/dev/null || true
    pkill -x "$FAKE_A" 2>/dev/null || true
    pkill -x "$FAKE_B" 2>/dev/null || true
    rm -rf "$T"
}
trap cleanup EXIT

ST="$repo/bin/shell-toggle"
SS="$repo/bin/shell-start"
SC="$repo/bin/shellctl"
WS="$repo/bin/wallpaper-sync"

out="$("$ST" list)"
check "list marks aaa active"   "printf '%s' \"\$out\" | grep -q '^\* aaa'"
check "list shows ccc stopped"  "printf '%s' \"\$out\" | grep -q 'ccc.*stopped'"

out="$("$ST" check)"; rc=$?
check "check passes"            "[ $rc -eq 0 ]"
check "check detects session"   "printf '%s' \"\$out\" | grep -q '^session: '"
check "check reports aaa"       "printf '%s' \"\$out\" | grep -q '^\[aaa\] Test A'"

setsid "$T/$FAKE_A" 300 >/dev/null 2>&1 &
sleep 0.2
"$ST" toggle
check "bbb is running"          "pgrep -x $FAKE_B >/dev/null"
check "aaa was reaped"          "! pgrep -x $FAKE_A >/dev/null"
check "state is bbb"            "[ \"\$(cat \"\$XDG_STATE_HOME/shell-mode\")\" = bbb ]"
check "binds flipped to bbb"    "[ \"\$(readlink \"\$HOME/.config/mango/cfg/binds-active.conf\")\" = binds-bbb.conf ]"
check "status says bbb running" "[ \"\$(\"\$ST\" status)\" = 'bbb (running)' ]"

"$ST" prev
check "aaa is running again"    "pgrep -x $FAKE_A >/dev/null"
check "bbb was reaped"          "! pgrep -x $FAKE_B >/dev/null"
check "binds flipped to aaa"    "[ \"\$(readlink \"\$HOME/.config/mango/cfg/binds-active.conf\")\" = binds-aaa.conf ]"

"$SC" panel-toggle launcher
check "shellctl used aaa adapter" "grep -qx 'panel-toggle launcher' \"\$T/adapter.log\""

printf '%s\n' "$T/wall/img1.png" > "$T/wall/a.txt"
printf '%s\n' "$T/wall/img2.png" > "$T/wall/b.txt"
"$WS" --once
check "wall-b followed running aaa" "grep -qx \"$T/wall/img1.png\" \"\$T/wall/b.txt\""
out="$("$WS" --status)"
check "wallpaper status lists aaa" "printf '%s' \"\$out\" | grep -q 'aaa'"
check "wallpaper status has img1"  "printf '%s' \"\$out\" | grep -q 'img1.png'"

"$WS" >/dev/null 2>&1 &
wpid=$!
sleep 1.2
printf '%s\n' "$T/wall/img2.png" > "$T/wall/a.txt"
sleep 2.2
check "daemon propagated live change" "grep -qx \"$T/wall/img2.png\" \"\$T/wall/b.txt\""
kill "$wpid" 2>/dev/null || true
wait "$wpid" 2>/dev/null || true
wpid=""

pkill -x "$FAKE_A" 2>/dev/null || true
printf 'bbb\n' > "$XDG_STATE_HOME/shell-mode"
"$SS" >/dev/null 2>&1 &
spid=$!
sleep 0.4
check "shell-start launched bbb"   "pgrep -x $FAKE_B >/dev/null"
check "shell-start set binds bbb"  "[ \"\$(readlink \"\$HOME/.config/mango/cfg/binds-active.conf\")\" = binds-bbb.conf ]"
bpid="$(pgrep -x -n "$FAKE_B" || true)"
check "shell-start exported env"   "[ -n \"\$bpid\" ] && tr '\\0' '\\n' < /proc/\$bpid/environ | grep -qx TEST_MARK=yes"
kill "$spid" 2>/dev/null || true
pkill -x "$FAKE_B" 2>/dev/null || true
wait "$spid" 2>/dev/null || true
spid=""

printf 'aaa\n' > "$XDG_STATE_HOME/shell-mode"
ln -sfn binds-aaa.conf "$HOME/.config/mango/cfg/binds-active.conf"
setsid "$T/$FAKE_A" 300 >/dev/null 2>&1 &
sleep 0.2
"$ST" ccc >/dev/null 2>&1; rc=$?
check "failed switch exits non-zero" "[ $rc -ne 0 ]"
check "failed switch kept aaa"       "pgrep -x $FAKE_A >/dev/null"
check "failed switch kept state"     "[ \"\$(cat \"\$XDG_STATE_HOME/shell-mode\")\" = aaa ]"
check "failed switch kept binds"     "[ \"\$(readlink \"\$HOME/.config/mango/cfg/binds-active.conf\")\" = binds-aaa.conf ]"

"$ST" bbb
check "direct select bbb"        "[ \"\$(cat \"\$XDG_STATE_HOME/shell-mode\")\" = bbb ] && pgrep -x $FAKE_B >/dev/null"
"$ST" nope >/dev/null 2>&1; rc=$?
check "invalid id rejected"      "[ $rc -ne 0 ]"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
