#!/usr/bin/env bash

set -Eeuo pipefail
export LC_ALL=C

(( $# == 1 )) || { echo "usage: $0 <kernel.release file>" >&2; exit 1; }
[[ -s "$1" ]] || { echo "error: kernel release file not found or empty: $1" >&2; exit 1; }
release="$(cat -- "$1")"
[[ "${release}" =~ ^[[:alnum:]][[:alnum:]._+-]*$ && ${#release} -le 64 ]] || {
    echo "error: invalid kernel release in $1" >&2
    exit 1
}
printf '%s\n' "${release}"
