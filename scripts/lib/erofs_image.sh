#!/usr/bin/env bash

set -Eeuo pipefail

EROFS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${EROFS_SCRIPT_DIR}/../.." && pwd)"

build_image() {
    local image="$1" root="$2" partition="$3" uuid="$4" epoch="$5" contexts="$6"

    mkfs.erofs \
        -zlz4hc,level=12 \
        -E^xattr-name-filter \
        -T"${epoch}" \
        --all-time \
        --all-root \
        -U"${uuid}" \
        -L "${partition}" \
        --file-contexts="${contexts}" \
        "${image}" "${root}" || return
    fsck.erofs -p "${image}"
}

check_tools() {
    local work_dir partition uuid

    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/sm8550-erofs-check.XXXXXX")"
    trap "rm -rf -- $(printf '%q' "${work_dir}")" EXIT
    mkdir -p "${work_dir}/root/etc" "${work_dir}/root/lib/modules"
    printf 'packaging capability check\n' >"${work_dir}/root/etc/build.prop"
    # Exercise compression as well as labels, timestamps and SELinux xattrs.
    head -c 65536 /dev/zero >"${work_dir}/root/lib/modules/probe"

    for partition in vendor_dlkm system_dlkm; do
        case "${partition}" in
            vendor_dlkm) uuid="6b128d5a-0f66-4bb6-b5d1-90c9ad38c54a" ;;
            system_dlkm) uuid="f2ec91c9-d5a7-47bf-a6eb-c19f24ee6fcb" ;;
        esac
        if ! build_image "${work_dir}/${partition}.img" "${work_dir}/root" \
            "${partition}" "${uuid}" 1700000000 \
            "${REPO_ROOT}/prebuilts/${partition}_file_contexts"; then
            echo "error: EROFS tools cannot create and verify ${partition}; run scripts/lib/install_erofs_utils.sh <prefix> and add <prefix>/bin to PATH" >&2
            return 1
        fi
    done
    echo "[packaging] EROFS image creation and verification checks passed"
}

for tool in mkfs.erofs fsck.erofs; do
    command -v "${tool}" >/dev/null || { echo "error: ${tool} not found" >&2; exit 1; }
done

if [[ $# == 1 && "$1" == --check ]]; then
    check_tools
elif (( $# == 6 )); then
    build_image "$@"
else
    echo "usage: $0 --check | <image> <root> <partition> <uuid> <epoch> <file contexts>" >&2
    exit 1
fi
