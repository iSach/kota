#!/usr/bin/env bash
# Install kota and (optionally) set the start/end dates of your appointment.
#
#   ./install.sh                      interactive
#   ./install.sh --end 2026-10-02     non-interactive; also --start DATE, --prefix DIR
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="$HOME/.local/bin"
config="${XDG_CONFIG_HOME:-$HOME/.config}/kota/config"
start="" end="" given_start=0 given_end=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --start)  start="${2:-}"; given_start=1; shift 2 ;;
        --end)    end="${2:-}"; given_end=1; shift 2 ;;
        --prefix) prefix="${2:?--prefix needs a directory}"; shift 2 ;;
        -h|--help) sed -n '2,6s/^# \{0,1\}//p' "$0"; exit 0 ;;
        *) echo "install.sh: unknown option $1" >&2; exit 2 ;;
    esac
done

valid_date() {
    [[ -z "$1" ]] || { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && date -d "$1" >/dev/null 2>&1; }
}

current() {  # value of a key in the existing config, if any
    [[ -f "$config" ]] && sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$config" | tail -1
}

ask() {  # ask <prompt> <default> -> echoes a valid date or empty
    local answer
    while true; do
        read -r -p "$1${2:+ [$2]}: " answer || answer=""
        answer="${answer:-$2}"
        [[ "$answer" == "-" ]] && answer=""
        if valid_date "$answer"; then echo "$answer"; return; fi
        echo "  please use YYYY-MM-DD" >&2
    done
}

command -v python3 >/dev/null || { echo "install.sh: python3 not found" >&2; exit 1; }

# Default start: when your cluster account was created (from LDAP), else the existing config.
default_start="$(current start || true)"
if [[ -z "$default_start" ]] && command -v ldapsearch >/dev/null; then
    ts="$(timeout 10 ldapsearch -x -LLL "(uid=$USER)" createTimestamp 2>/dev/null \
          | sed -n 's/^createTimestamp: \([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\).*/\1-\2-\3/p' || true)"
    default_start="$ts"
fi

if ! ((given_start && given_end)); then
    echo "kota: dates are optional. They show the time left and pace the hour bars."
    echo "      Enter '-' to clear a value."
fi
((given_end))   || end="$(ask "End date (YYYY-MM-DD)" "$(current end || true)")"
((given_start)) || start="$(ask "Start date (YYYY-MM-DD)" "$default_start")"
[[ "$start" == "-" ]] && start=""
[[ "$end" == "-" ]] && end=""
for d in "$start" "$end"; do
    valid_date "$d" || { echo "install.sh: bad date '$d' (want YYYY-MM-DD)" >&2; exit 2; }
done
if [[ -n "$start" && -n "$end" && "$start" > "$end" ]]; then
    echo "install.sh: start $start is after end $end" >&2; exit 2
fi

mkdir -p "$prefix" "$(dirname "$config")"
install -m 755 "$here/kota" "$prefix/kota"
{
    echo "[kota]"
    [[ -n "$start" ]] && echo "start = $start"
    [[ -n "$end" ]] && echo "end = $end"
} > "$config"

echo "Installed $prefix/kota"
echo "Config    $config${start:+ (start $start)}${end:+ (end $end)}"
case ":$PATH:" in
    *":$prefix:"*) ;;
    *) echo "Note: $prefix is not on your PATH. Add it, e.g. in ~/.bashrc:"
       echo "      export PATH=\"$prefix:\$PATH\"" ;;
esac
