#!/usr/bin/env bash

set -Eeuo pipefail

FSTAB_FILE="${1:?fstab path is required}"
[[ -f "${FSTAB_FILE}" ]] || {
    echo "fstab not found: ${FSTAB_FILE}" >&2
    exit 1
}

TMP_FILE="$(mktemp "${FSTAB_FILE}.XXXXXX")"
FALLBACK_FILE="$(mktemp "${FSTAB_FILE}.XXXXXX")"
trap 'rm -f "${TMP_FILE}" "${FALLBACK_FILE}"' EXIT
chmod --reference="${FSTAB_FILE}" "${TMP_FILE}"

add_filesystem_fallbacks() {
    local input_file="$1"
    local output_file="$2"

    awk '
    BEGIN {
        OFS = "\t"
        fallback_partitions[1] = "system"
        fallback_partitions[2] = "system_ext"
        fallback_partitions[3] = "product"
        fallback_partitions[4] = "vendor"
        fallback_partitions[5] = "odm"
        fallback_filesystems[1] = "erofs"
        fallback_filesystems[2] = "f2fs"
        fallback_filesystems[3] = "ext4"
    }
    function is_fallback_partition(partition) {
        return partition == "system" ||
            partition == "system_ext" ||
            partition == "product" ||
            partition == "vendor" ||
            partition == "odm"
    }
    function normalized_record() {
        return $1 OFS $2 OFS $3 OFS $4 OFS $5
    }
    function change_filesystem(base_record, filesystem, fields, field_count) {
        field_count = split(base_record, fields, /[[:space:]]+/)
        return fields[1] OFS fields[2] OFS filesystem OFS fields[4] OFS fields[5]
    }
    {
        record_count++
        if (is_fallback_partition($1) &&
            ($3 == "erofs" || $3 == "f2fs" || $3 == "ext4")) {
            partition = $1
            filesystem = $3
            target_record[record_count] = partition
            key = partition SUBSEP filesystem
            if (!(key in target_line)) {
                target_line[key] = normalized_record()
            }
            if (!(partition in target_base)) {
                target_base[partition] = normalized_record()
            }
            next
        }
        records[record_count] = $0
    }
    END {
        for (partition_index = 1; partition_index <= 5; partition_index++) {
            partition = fallback_partitions[partition_index]
            if (!(partition in target_base)) {
                printf "expected at least one %s fstab entry\n", partition > "/dev/stderr"
                fatal_status = 1
            }
        }
        if (fatal_status != 0) {
            exit fatal_status
        }

        for (record_index = 1; record_index <= record_count; record_index++) {
            if (!(record_index in target_record)) {
                print records[record_index]
                continue
            }
            partition = target_record[record_index]
            if (emitted[partition]) {
                continue
            }
            base_record = target_base[partition]
            for (filesystem_index = 1; filesystem_index <= 3; filesystem_index++) {
                filesystem = fallback_filesystems[filesystem_index]
                key = partition SUBSEP filesystem
                if (key in target_line) {
                    print target_line[key]
                } else {
                    print change_filesystem(base_record, filesystem)
                }
            }
            emitted[partition] = 1
        }
    }
    ' "${input_file}" > "${output_file}"
}

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

add_filesystem_fallbacks "${TMP_FILE}" "${FALLBACK_FILE}"

touch --reference="${FSTAB_FILE}" "${FALLBACK_FILE}"
mv "${FALLBACK_FILE}" "${FSTAB_FILE}"
trap - EXIT
