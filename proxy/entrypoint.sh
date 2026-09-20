#!/bin/sh
# Renders /config/hosts.conf into an nginx map and reloads nginx when the file
# changes. Invalid edits are rejected and the previous mapping stays active.
set -eu

HOSTS_FILE="${HOSTS_FILE:-/config/hosts.conf}"
MAP_FILE=/etc/nginx/generated/hosts.map
POLL_SECONDS="${POLL_SECONDS:-5}"

mkdir -p "$(dirname "$MAP_FILE")"

render() {
    [ -r "$HOSTS_FILE" ] || return 0
    awk '
        { sub(/#.*/, "") }
        NF == 0 { next }
        NF != 2 {
            printf "hosts: line %d ignored, expected \"<domain> <upstream>\"\n", NR > "/dev/stderr"; next
        }
        {
            d = tolower($1); u = $2
            if (d !~ /^(\*\.)?[a-z0-9.-]+$/) {
                printf "hosts: line %d ignored, invalid domain \"%s\"\n", NR, $1 > "/dev/stderr"; next
            }
            if (u !~ /^[A-Za-z0-9._-]+(:[0-9]+)?$/) {
                printf "hosts: line %d ignored, invalid upstream \"%s\"\n", NR, $2 > "/dev/stderr"; next
            }
            printf "%s %s;\n", d, u
        }
    ' "$HOSTS_FILE"
}

apply() {
    new="$(mktemp)"
    render > "$new"
    cp "$MAP_FILE" "$MAP_FILE.bak" 2>/dev/null || : > "$MAP_FILE.bak"
    cp "$new" "$MAP_FILE"
    rm -f "$new"
    if nginx -t >/dev/null 2>&1; then
        return 0
    fi
    echo "hosts: nginx rejected the new mapping, keeping the previous one" >&2
    cp "$MAP_FILE.bak" "$MAP_FILE"
    return 1
}

: > "$MAP_FILE"
apply || { echo "hosts: initial mapping invalid" >&2; : > "$MAP_FILE"; }
nginx -t

watch() {
    last="$(cksum "$HOSTS_FILE" 2>/dev/null || echo missing)"
    while sleep "$POLL_SECONDS"; do
        cur="$(cksum "$HOSTS_FILE" 2>/dev/null || echo missing)"
        if [ "$cur" != "$last" ]; then
            last="$cur"
            if apply; then
                nginx -s reload && echo "hosts: mapping reloaded"
            fi
        fi
    done
}

watch &

exec nginx -g 'daemon off;'
