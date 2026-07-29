#!/usr/bin/env bash

set -Eeuo pipefail

STOCK_IMAGE="${1:?stock vendor_dlkm image is required}"
CANDIDATE_IMAGE="${2:?candidate vendor_dlkm image is required}"
TARGET_SIZE="${3:-}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

for tool in dump.erofs fsck.erofs modinfo; do
    command -v "${tool}" >/dev/null 2>&1 || {
        echo "required command not found: ${tool}" >&2
        exit 1
    }
done

candidate_size="$(stat -c %s "${CANDIDATE_IMAGE}")"
if [[ -n "${TARGET_SIZE}" ]]; then
    [[ "${TARGET_SIZE}" =~ ^[0-9]+$ ]] || {
        echo "target size must be an integer" >&2
        exit 2
    }
    [[ "${candidate_size}" -le "${TARGET_SIZE}" ]] || {
        echo "candidate exceeds target: image=${candidate_size}, target=${TARGET_SIZE}" >&2
        exit 1
    }
fi
erofs_block_size="$(
    dump.erofs -s "${CANDIDATE_IMAGE}" |
        awk -F: '/Filesystem blocksize:/ { gsub(/[[:space:]]/, "", $2); print $2 }'
)"
erofs_blocks="$(
    dump.erofs -s "${CANDIDATE_IMAGE}" |
        awk -F: '/Filesystem blocks:/ { gsub(/[[:space:]]/, "", $2); print $2 }'
)"
erofs_size="$((erofs_block_size * erofs_blocks))"
[[ "${candidate_size}" == "${erofs_size}" ]] || {
    echo "candidate has bytes beyond its EROFS filesystem: image=${candidate_size}, erofs=${erofs_size}" >&2
    exit 1
}

fsck.erofs -p "${CANDIDATE_IMAGE}"
if dump.erofs -s "${CANDIDATE_IMAGE}" | grep -q 'xattr_filter'; then
    echo "candidate enables the Linux 6.6+ xattr name filter" >&2
    exit 1
fi

mkdir -p "${WORK_DIR}/stock" "${WORK_DIR}/candidate"
fsck.erofs --extract="${WORK_DIR}/stock" --no-preserve-owner --no-preserve-perms \
    "${STOCK_IMAGE}"
fsck.erofs --extract="${WORK_DIR}/candidate" --no-preserve-owner --no-preserve-perms \
    "${CANDIDATE_IMAGE}"

find "${WORK_DIR}/stock" -printf '%y %m %P -> %l\n' | sort > "${WORK_DIR}/stock.tree"
find "${WORK_DIR}/candidate" -printf '%y %m %P -> %l\n' | sort > "${WORK_DIR}/candidate.tree"
diff -u "${WORK_DIR}/stock.tree" "${WORK_DIR}/candidate.tree"
cmp "${WORK_DIR}/stock/lib/modules/modules.load" \
    "${WORK_DIR}/candidate/lib/modules/modules.load"

module_count="$(find "${WORK_DIR}/candidate/lib/modules" -maxdepth 1 \
    -type f -name '*.ko' | wc -l)"
dep_count="$(awk -F: 'NF { count++ } END { print count + 0 }' \
    "${WORK_DIR}/candidate/lib/modules/modules.dep")"
[[ "${dep_count}" == "${module_count}" ]] || {
    echo "modules.dep has ${dep_count} entries for ${module_count} modules" >&2
    exit 1
}

while IFS= read -r module; do
    modinfo "${module}" >/dev/null
done < <(find "${WORK_DIR}/candidate/lib/modules" -maxdepth 1 \
    -type f -name '*.ko' | sort)

echo "stock-compatible vendor_dlkm image test passed"
