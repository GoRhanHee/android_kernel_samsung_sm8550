#!/usr/bin/env bash

set -Eeuo pipefail

FSTAB_FILE="${1:?fstab path is required}"
[[ -f "${FSTAB_FILE}" ]] || {
    echo "fstab not found: ${FSTAB_FILE}" >&2
    exit 1
}

TMP_FILE="$(mktemp "${FSTAB_FILE}.XXXXXX")"
trap 'rm -f "${TMP_FILE}"' EXIT
chmod --reference="${FSTAB_FILE}" "${TMP_FILE}"

awk '
BEGIN {
    OFS = "\t"
}
$1 == "vendor_dlkm" {
    target_count++
    flag_count = split($5, flags, ",")
    filtered = ""
    removed = 0
    for (i = 1; i <= flag_count; i++) {
        if (flags[i] ~ /^avb(=|$)/) {
            removed++
            continue
        }
        filtered = filtered (filtered == "" ? "" : ",") flags[i]
    }
    if (removed != 1) {
        printf "vendor_dlkm must contain exactly one AVB flag\n" > "/dev/stderr"
        exit 2
    }
    $5 = filtered
}
{
    print
}
END {
    if (target_count != 1) {
        printf "expected exactly one vendor_dlkm fstab entry, found %d\n", target_count > "/dev/stderr"
        exit 3
    }
}
' "${FSTAB_FILE}" > "${TMP_FILE}"

touch --reference="${FSTAB_FILE}" "${TMP_FILE}"
mv "${TMP_FILE}" "${FSTAB_FILE}"
trap - EXIT
