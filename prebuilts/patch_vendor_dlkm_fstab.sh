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
function strip_avb(entry, flag_list,    flag_count, flags, filtered, removed, i) {
    flag_count = split(flag_list, flags, ",")
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
        printf "%s must contain exactly one AVB flag\n", entry > "/dev/stderr"
        fatal_status = 2
        exit fatal_status
    }
    return filtered
}
$1 == "vendor_dlkm" {
    vendor_count++
    $5 = strip_avb("vendor_dlkm", $5)
}
$1 == "system_dlkm" {
    system_count++
    if ($3 == "erofs") {
        system_erofs_count++
    } else if ($3 == "f2fs") {
        system_f2fs_count++
    } else if ($3 == "ext4") {
        system_ext4_count++
    } else {
        printf "unexpected system_dlkm filesystem: %s\n", $3 > "/dev/stderr"
        fatal_status = 4
        exit fatal_status
    }
    $5 = strip_avb("system_dlkm " $3, $5)
}
{
    print
}
END {
    if (fatal_status != 0) {
        exit fatal_status
    }
    if (vendor_count != 1) {
        printf "expected exactly one vendor_dlkm fstab entry, found %d\n", vendor_count > "/dev/stderr"
        exit 3
    }
    if (system_count != 3 ||
        system_erofs_count != 1 ||
        system_f2fs_count != 1 ||
        system_ext4_count != 1) {
        printf "expected exactly one system_dlkm entry for erofs, f2fs, and ext4; found total=%d erofs=%d f2fs=%d ext4=%d\n", system_count, system_erofs_count, system_f2fs_count, system_ext4_count > "/dev/stderr"
        exit 3
    }
}
' "${FSTAB_FILE}" > "${TMP_FILE}"

touch --reference="${FSTAB_FILE}" "${TMP_FILE}"
mv "${TMP_FILE}" "${FSTAB_FILE}"
trap - EXIT
