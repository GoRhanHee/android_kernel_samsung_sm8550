#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly HELPER="${REPO_ROOT}/prebuilts/vendor_dlkm_capacity.sh"
readonly PACKAGER="${REPO_ROOT}/prebuilts/build_vendor_dlkm.sh"
readonly FIXTURES="$(mktemp -d)"
trap 'rm -rf -- "${FIXTURES}"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

make_image() {
    local name="$1"
    local size="$2"

    truncate -s "${size}" -- "${FIXTURES}/${name}"
    printf '%s\n' "${FIXTURES}/${name}"
}

assert_fails_unchanged() {
    local description="$1"
    local stock_image="$2"
    local rebuilt_image="$3"
    local expected_message="$4"
    local before
    local after
    local output
    local status

    before="$(sha256sum -- "${rebuilt_image}"; stat -c '%s:%Y:%i' -- "${rebuilt_image}")"
    set +e
    output="$(vendor_dlkm_capacity_pad_to_stock \
        "${stock_image}" "${rebuilt_image}" 2>&1)"
    status=$?
    set -e
    after="$(sha256sum -- "${rebuilt_image}"; stat -c '%s:%Y:%i' -- "${rebuilt_image}")"

    [[ "${status}" == 1 ]] || fail "${description} returned ${status}, expected 1"
    grep -Fq -- "${expected_message}" <<<"${output}" ||
        fail "${description} omitted diagnostic: ${expected_message}"
    [[ "${before}" == "${after}" ]] ||
        fail "${description} mutated the rejected rebuilt image"
}

bash -n "${HELPER}" "${PACKAGER}"

# shellcheck source=/dev/null
source "${HELPER}"
for function_name in \
    vendor_dlkm_metadata_set_uuid \
    vendor_dlkm_capacity_pad_to_stock \
    vendor_dlkm_capacity_validate \
    vendor_dlkm_selinux_xattrs_validate; do
    declare -F "${function_name}" >/dev/null ||
        fail "sourceable compatibility function is missing: ${function_name}"
done

stock="$(make_image stock 8192)"
short="$(make_image short 4096)"
exact="$(make_image exact 8192)"

strict_output="$(bash "${HELPER}" "${stock}" "${exact}")"
[[ "${strict_output}" == \
    'vendor_dlkm capacity: used=8192 max=8192 headroom=0' ]] ||
    fail "vendor CLI exact-capacity output changed: ${strict_output}"

set +e
strict_short_output="$(bash "${HELPER}" "${stock}" "${short}" 2>&1)"
strict_short_status=$?
set -e
[[ "${strict_short_status}" == 1 ]] || fail "vendor CLI accepted a short image"
grep -Fqx 'vendor_dlkm capacity: used=4096 max=8192 headroom=4096' \
    <<<"${strict_short_output}" || fail "vendor CLI short-image diagnostic changed"

pad_output="$(vendor_dlkm_capacity_pad_to_stock "${stock}" "${short}")"
[[ "${pad_output}" == \
    'vendor_dlkm capacity padded: used_before=4096 max=8192 padding=4096 used_after=8192' ]] ||
    fail "vendor pad output changed: ${pad_output}"
[[ "$(stat -c %s -- "${short}")" == 8192 ]] || fail "vendor pad missed exact size"
[[ -z "$(tail -c 4096 -- "${short}" | tr -d '\0')" ]] ||
    fail "vendor padding contains non-zero bytes"

equal_before="$(sha256sum -- "${exact}"; stat -c '%s:%Y:%i' -- "${exact}")"
equal_output="$(vendor_dlkm_capacity_pad_to_stock "${stock}" "${exact}")"
equal_after="$(sha256sum -- "${exact}"; stat -c '%s:%Y:%i' -- "${exact}")"
[[ "${equal_output}" == \
    'vendor_dlkm capacity padded: used_before=8192 max=8192 padding=0 used_after=8192' ]] ||
    fail "vendor equal-capacity output changed: ${equal_output}"
[[ "${equal_before}" == "${equal_after}" ]] || fail "vendor equal-capacity pad is not a no-op"

oversize="$(make_image oversize 12288)"
assert_fails_unchanged oversize "${stock}" "${oversize}" \
    'rebuilt vendor_dlkm image exceeds stock partition capacity: 12288 > 8192 bytes'
empty="$(make_image empty 0)"
assert_fails_unchanged empty "${stock}" "${empty}" \
    'rebuilt vendor_dlkm size must be positive: 0'
unaligned="$(make_image unaligned 4097)"
assert_fails_unchanged unaligned "${stock}" "${unaligned}" \
    'rebuilt vendor_dlkm size is not 4096-byte aligned: 4097'

metadata="${FIXTURES}/metadata.txt"
printf '%s\n' \
    'UNPACK_TIME=1' \
    'ORIGINAL_UUID=11111111-1111-1111-1111-111111111111' \
    'MOUNT_METHOD=kernel' \
    'ORIGINAL_UUID=22222222-2222-2222-2222-222222222222' \
    >"${metadata}"
stock_uuid='eed248a3-f6c7-5860-a9d8-f805c2b5e8a4'
vendor_dlkm_metadata_set_uuid "${metadata}" "${stock_uuid}"
[[ "$(grep -c '^ORIGINAL_UUID=' "${metadata}")" == 1 ]] ||
    fail "vendor UUID rewrite did not leave exactly one entry"
grep -Fqx "ORIGINAL_UUID=${stock_uuid}" "${metadata}" ||
    fail "vendor UUID rewrite did not preserve the requested UUID"
grep -Fqx 'UNPACK_TIME=1' "${metadata}" || fail "vendor UUID rewrite lost metadata"
grep -Fqx 'MOUNT_METHOD=kernel' "${metadata}" || fail "vendor UUID rewrite lost metadata"

set +e
xattr_output="$(bash "${HELPER}" --validate-selinux-xattrs \
    "${FIXTURES}/missing-root" 2>&1)"
xattr_status=$?
set -e
[[ "${xattr_status}" == 1 ]] || fail "vendor xattr wrapper accepted a missing root"
grep -Fq 'vendor_dlkm SELinux xattr security.selinux missing from /' \
    <<<"${xattr_output}" || fail "vendor xattr wrapper diagnostic changed"

printf 'PASS vendor_dlkm capacity, UUID, xattr, and wrapper compatibility baseline\n'
