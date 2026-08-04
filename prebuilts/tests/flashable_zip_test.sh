#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly PACKAGER="${REPO_DIR}/prebuilts/make_flashable_zip.sh"
readonly TEST_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sm8550-flashable-test.XXXXXX")"

cleanup() {
    rm -rf "${TEST_TMP_DIR}"
}
trap cleanup EXIT

die() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    [[ "${haystack}" == *"${needle}"* ]] ||
        die "${label}: missing ${needle@Q}"
}

assert_rejected() {
    local label="$1"
    local image_dir="$2"
    local output_zip="${TEST_TMP_DIR}/${label}.zip"
    local output
    local status

    if output="$(bash "${PACKAGER}" "${output_zip}" "${image_dir}" 'Galaxy S23 Ultra' 2>&1)"; then
        status=0
    else
        status=$?
    fi
    [[ "${status}" -ne 0 ]] ||
        die "${label}: packager accepted invalid image set"
    [[ ! -e "${output_zip}" ]] ||
        die "${label}: packager left an output ZIP after rejection"
    assert_contains "${output}" 'system_dlkm.img' "${label} diagnostic"
    printf 'PASS: %s rejected with exit %s\n' "${label}" "${status}"
    printf '%s\n' "${output}"
}

assert_stale_output_removed() {
    local label="$1"
    local image_dir="$2"
    local output_zip="${TEST_TMP_DIR}/${label}.zip"
    local output
    local status

    printf '%s\n' 'STALE-OUTPUT-SENTINEL' > "${output_zip}"
    [[ -e "${output_zip}" ]] || die "${label}: failed to create sentinel output"

    if output="$(bash "${PACKAGER}" "${output_zip}" "${image_dir}" 'Galaxy S23 Ultra' 2>&1)"; then
        status=0
    else
        status=$?
    fi
    [[ "${status}" -ne 0 ]] ||
        die "${label}: packager accepted invalid image set"
    [[ ! -e "${output_zip}" ]] ||
        die "${label}: packager left a stale output ZIP after rejection"
    assert_contains "${output}" 'system_dlkm.img' "${label} diagnostic"
    printf 'PASS: %s rejected and stale output removed with exit %s\n' "${label}" "${status}"
    printf '%s\n' "${output}"
}

make_fixture() {
    local image_dir="$1"

    mkdir -p "${image_dir}"
    for image in boot.img vendor_boot.img vendor_dlkm.img system_dlkm.img; do
        truncate -s 4096 "${image_dir}/${image}"
    done
}

command -v cmp >/dev/null 2>&1 || die 'cmp is required'
command -v unzip >/dev/null 2>&1 || die 'unzip is required'
command -v zipinfo >/dev/null 2>&1 || die 'zipinfo is required'

fixture_dir="${TEST_TMP_DIR}/fixture"
make_fixture "${fixture_dir}"

# Extra dist-side files model the files that CI collects separately. They must
# never be pulled into the recovery ZIP by a fixed-name package contract.
truncate -s 4096 "${fixture_dir}/dtbo.img"
printf '%s\n' 'module' > "${fixture_dir}/system_dlkm.modules.load"
printf '%s\n' 'module' > "${fixture_dir}/system_dlkm.modules.blocklist"
printf '%s\n' 'staging' > "${fixture_dir}/system_dlkm_staging_archive.tar.gz"
printf '%s\n' 'metadata' > "${fixture_dir}/metadata.txt"

zip_path="${TEST_TMP_DIR}/four-image.zip"
bash "${PACKAGER}" "${zip_path}" "${fixture_dir}" 'Galaxy S23 Ultra'
unzip -t "${zip_path}" >/dev/null

actual_entries="$(zipinfo -1 "${zip_path}" | LC_ALL=C sort)"
expected_entries="$(printf '%s\n' \
    'META-INF/' \
    'META-INF/com/' \
    'META-INF/com/google/' \
    'META-INF/com/google/android/' \
    'META-INF/com/google/android/sm8550-flash-image.sh' \
    'META-INF/com/google/android/update-binary' \
    'META-INF/com/google/android/updater-script' \
    'dynamic_partitions_op_list' \
    'files/' \
    'files/boot.img' \
    'files/system_dlkm.img' \
    'files/vendor_boot.img' \
    'files/vendor_dlkm.img' | LC_ALL=C sort)"
[[ "${actual_entries}" == "${expected_entries}" ]] || {
    printf '%s\n' 'actual ZIP entries:' "${actual_entries}" >&2
    printf '%s\n' 'expected ZIP entries:' "${expected_entries}" >&2
    die 'four-image ZIP entry set differs from the exact contract'
}

for image in boot.img vendor_boot.img vendor_dlkm.img system_dlkm.img; do
    cmp "${fixture_dir}/${image}" \
        <(unzip -p "${zip_path}" "files/${image}") ||
        die "${image} was not copied byte-for-byte"
done

updater_script="$(unzip -p "${zip_path}" META-INF/com/google/android/updater-script)"
resize_operations="$(unzip -p "${zip_path}" dynamic_partitions_op_list)"
[[ "${resize_operations}" == $'resize system_dlkm 4096\nresize vendor_dlkm 4096' ]] || {
    printf '%s\n' 'actual resize operations:' "${resize_operations}" >&2
    die 'dynamic partition resize operation list does not match image sizes'
}
assert_contains "${updater_script}" 'update_dynamic_partitions' \
    'updater-script dynamic partition resize'
assert_contains "${updater_script}" 'files/system_dlkm.img' \
    'updater-script system image extraction'
assert_contains "${updater_script}" 'system_dlkm' \
    'updater-script system partition'

missing_dir="${TEST_TMP_DIR}/missing-system"
cp -a "${fixture_dir}" "${missing_dir}"
find "${missing_dir}" -maxdepth 1 -type f -name 'system_dlkm.img' -delete
assert_rejected 'missing-system-image' "${missing_dir}"
assert_stale_output_removed 'missing-system-image-stale-output' "${missing_dir}"

empty_dir="${TEST_TMP_DIR}/empty-system"
cp -a "${fixture_dir}" "${empty_dir}"
truncate -s 0 "${empty_dir}/system_dlkm.img"
assert_rejected 'empty-system-image' "${empty_dir}"

three_image_dir="${TEST_TMP_DIR}/three-image"
cp -a "${fixture_dir}" "${three_image_dir}"
find "${three_image_dir}" -maxdepth 1 -type f -name 'system_dlkm.img' -delete
assert_rejected 'three-image-input' "${three_image_dir}"

printf '%s\n' 'PASS: four-image ZIP contract, resize metadata, exact entries, byte copies, updater references, and rejection cases'
