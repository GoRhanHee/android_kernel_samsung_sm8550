#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly HELPER="${REPO_ROOT}/prebuilts/dlkm_capacity.sh"
readonly FIXTURES="$(mktemp -d)"
trap 'rm -rf -- "${FIXTURES}"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

make_file() {
    local name="$1"
    local size="$2"

    truncate -s "${size}" -- "${FIXTURES}/${name}"
    printf '%s\n' "${FIXTURES}/${name}"
}

assert_rejected_unchanged() {
    local partition="$1"
    local stock="$2"
    local rebuilt="$3"
    local expected="$4"
    local before
    local after
    local output
    local status

    before="$(sha256sum -- "${rebuilt}"; stat -c '%s:%Y:%i' -- "${rebuilt}")"
    set +e
    output="$(dlkm_capacity_pad_to_stock "${partition}" "${stock}" "${rebuilt}" 2>&1)"
    status=$?
    set -e
    after="$(sha256sum -- "${rebuilt}"; stat -c '%s:%Y:%i' -- "${rebuilt}")"
    [[ "${status}" == 1 ]] || fail "${partition} rejected case returned ${status}"
    grep -Fq -- "${expected}" <<<"${output}" || fail "missing diagnostic: ${expected}"
    [[ "${before}" == "${after}" ]] || fail "${partition} rejection mutated output"
}

for command_name in truncate mkfs.erofs fsck.erofs dump.erofs; do
    command -v "${command_name}" >/dev/null || fail "missing command: ${command_name}"
done

# shellcheck source=/dev/null
source "${HELPER}"

for partition in vendor_dlkm system_dlkm; do
    stock="$(make_file "${partition}-stock" 8192)"
    short="$(make_file "${partition}-short" 4096)"
    output="$(dlkm_capacity_pad_to_stock "${partition}" "${stock}" "${short}")"
    [[ "${output}" == \
        "${partition} capacity padded: used_before=4096 max=8192 padding=4096 used_after=8192" ]] ||
        fail "${partition} pad diagnostic changed: ${output}"
    [[ "$(stat -c %s -- "${short}")" == 8192 ]] || fail "${partition} pad size"
    [[ -z "$(tail -c 4096 -- "${short}" | tr -d '\0')" ]] || fail "${partition} pad bytes"
    dlkm_capacity_validate "${partition}" "${stock}" "${short}" >/dev/null

    equal="$(make_file "${partition}-equal" 8192)"
    equal_before="$(sha256sum -- "${equal}"; stat -c '%s:%Y:%i' -- "${equal}")"
    dlkm_capacity_pad_to_stock "${partition}" "${stock}" "${equal}" >/dev/null
    equal_after="$(sha256sum -- "${equal}"; stat -c '%s:%Y:%i' -- "${equal}")"
    [[ "${equal_before}" == "${equal_after}" ]] || fail "${partition} equality was not a no-op"

    oversize="$(make_file "${partition}-oversize" 12288)"
    assert_rejected_unchanged "${partition}" "${stock}" "${oversize}" \
        "rebuilt ${partition} image exceeds stock partition capacity: 12288 > 8192 bytes"
    empty="$(make_file "${partition}-empty" 0)"
    assert_rejected_unchanged "${partition}" "${stock}" "${empty}" \
        "rebuilt ${partition} size must be positive: 0"
    unaligned="$(make_file "${partition}-unaligned" 4097)"
    assert_rejected_unchanged "${partition}" "${stock}" "${unaligned}" \
        "rebuilt ${partition} size is not 4096-byte aligned: 4097"
done

source_root="${FIXTURES}/identity-source"
mkdir -p "${source_root}/etc" "${source_root}/lib/modules/release"
printf 'fixture\n' >"${source_root}/etc/build.prop"
printf 'metadata\n' >"${source_root}/lib/modules/release/modules.dep"
uuid='2b92cbbe-4b7a-57ae-9ea3-b6ccf6512b74'
wrong_uuid='11111111-2222-3333-4444-555555555555'
mkfs.erofs --quiet --all-root -U"${uuid}" \
    --file-contexts="${REPO_ROOT}/prebuilts/system_dlkm_file_contexts" \
    "${FIXTURES}/identity-stock.img" "${source_root}"
mkfs.erofs --quiet --all-root -U"${uuid}" \
    --file-contexts="${REPO_ROOT}/prebuilts/system_dlkm_file_contexts" \
    "${FIXTURES}/identity-good.img" "${source_root}"
mkfs.erofs --quiet --all-root -U"${wrong_uuid}" \
    --file-contexts="${REPO_ROOT}/prebuilts/system_dlkm_file_contexts" \
    "${FIXTURES}/identity-wrong-uuid.img" "${source_root}"
identity_size=$(( $(stat -c %s -- "${FIXTURES}/identity-stock.img") + 4096 ))
truncate -s "${identity_size}" -- \
    "${FIXTURES}/identity-stock.img" \
    "${FIXTURES}/identity-good.img" \
    "${FIXTURES}/identity-wrong-uuid.img"
printf 'AVBf' | dd of="${FIXTURES}/identity-stock.img" bs=1 \
    seek=$((identity_size - 64)) conv=notrunc status=none
dlkm_image_validate system_dlkm \
    "${FIXTURES}/identity-stock.img" "${FIXTURES}/identity-good.img" >/dev/null

set +e
wrong_uuid_output="$(dlkm_image_validate system_dlkm \
    "${FIXTURES}/identity-stock.img" "${FIXTURES}/identity-wrong-uuid.img" 2>&1)"
wrong_uuid_status=$?
set -e
[[ "${wrong_uuid_status}" == 1 ]] || fail "wrong UUID was accepted"
grep -Fq "rebuilt system_dlkm UUID differs from stock: ${wrong_uuid} != ${uuid}" \
    <<<"${wrong_uuid_output}" || fail "wrong UUID diagnostic omitted both UUIDs"

cp -- "${FIXTURES}/identity-good.img" "${FIXTURES}/identity-avbf.img"
printf 'AVBf' | dd of="${FIXTURES}/identity-avbf.img" bs=1 \
    seek=$((identity_size - 64)) conv=notrunc status=none
set +e
avbf_output="$(dlkm_image_validate system_dlkm \
    "${FIXTURES}/identity-stock.img" "${FIXTURES}/identity-avbf.img" 2>&1)"
avbf_status=$?
set -e
[[ "${avbf_status}" == 1 ]] || fail "copied AVB footer was accepted"
grep -Fq 'rebuilt system_dlkm image retains an AVBf footer' <<<"${avbf_output}" ||
    fail "AVB footer diagnostic missing"

fake_bin="${FIXTURES}/fake-bin"
mkdir -p "${fake_bin}"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'target="${!#}"' \
    '[[ "${target}" != "${DLKM_TEST_MISSING_LABEL:-}" ]] || exit 1' \
    'case "${target}" in' \
    '  *vendor-labels/etc/build.prop) printf "u:object_r:vendor_configs_file:s0" ;;' \
    '  *vendor-labels*) printf "u:object_r:vendor_file:s0" ;;' \
    '  *) printf "u:object_r:system_dlkm_file:s0" ;;' \
    'esac' \
    >"${fake_bin}/getfattr"
chmod +x "${fake_bin}/getfattr"
mkdir -p \
    "${FIXTURES}/vendor-labels/etc" "${FIXTURES}/vendor-labels/lib/modules" \
    "${FIXTURES}/system-labels/etc" "${FIXTURES}/system-labels/lib/modules/release"
printf 'fixture\n' >"${FIXTURES}/vendor-labels/etc/build.prop"
printf 'fixture\n' >"${FIXTURES}/system-labels/etc/build.prop"
PATH="${fake_bin}:${PATH}" dlkm_selinux_xattrs_validate \
    vendor_dlkm "${FIXTURES}/vendor-labels" /lib/modules
PATH="${fake_bin}:${PATH}" dlkm_selinux_xattrs_validate \
    system_dlkm "${FIXTURES}/system-labels" /lib/modules/release

export DLKM_TEST_MISSING_LABEL="${FIXTURES}/system-labels/lib/modules/release"
set +e
missing_label_output="$(PATH="${fake_bin}:${PATH}" dlkm_selinux_xattrs_validate \
    system_dlkm "${FIXTURES}/system-labels" /lib/modules/release 2>&1)"
missing_label_status=$?
set -e
unset DLKM_TEST_MISSING_LABEL
[[ "${missing_label_status}" == 1 ]] || fail "missing system label was accepted"
grep -Fq 'system_dlkm SELinux label security.selinux missing from /lib/modules/release' \
    <<<"${missing_label_output}" || fail "missing-label diagnostic lacks path"

printf 'PASS shared DLKM capacity, UUID, AVB-tail, and label gates\n'
