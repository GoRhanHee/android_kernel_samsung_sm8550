#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly PACKAGER="${REPO_DIR}/prebuilts/make_fastboot_package.sh"
readonly TEST_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sm8550-fastboot-test.XXXXXX")"

cleanup() {
    rm -rf -- "${TEST_TMP_DIR}"
}
trap cleanup EXIT

die() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local text="$2"
    local label="$3"

    grep -Fq -- "${text}" "${file}" || die "${label}: missing ${text@Q}"
}

image_dir="${TEST_TMP_DIR}/images"
mkdir -p "${image_dir}"
for image in boot.img vendor_boot.img vendor_dlkm.img system_dlkm.img; do
    truncate -s 4096 "${image_dir}/${image}"
done

output_zip="${TEST_TMP_DIR}/GoRhanHee_Kernel-kalama-dm3q-fastboot.zip"
bash "${PACKAGER}" "${output_zip}" "${image_dir}"
unzip -t "${output_zip}" >/dev/null

actual_entries="$(zipinfo -1 "${output_zip}" | LC_ALL=C sort)"
expected_entries="$(printf '%s\n' \
    boot.img \
    flash_linux.sh \
    flash_macos.sh \
    flash_windows.bat \
    system_dlkm.img \
    vendor_boot.img \
    vendor_dlkm.img | LC_ALL=C sort)"
[[ "${actual_entries}" == "${expected_entries}" ]] ||
    die 'fastboot release package must contain exactly four images and three flash scripts'

for script in flash_linux.sh flash_macos.sh flash_windows.bat; do
    unzip -p "${output_zip}" "${script}" > "${TEST_TMP_DIR}/${script}"
    assert_contains "${TEST_TMP_DIR}/${script}" \
        'flash_image boot boot.img' \
        "${script} boot command"
    assert_contains "${TEST_TMP_DIR}/${script}" \
        'flash_image vendor_boot vendor_boot.img' \
        "${script} vendor_boot command"
    assert_contains "${TEST_TMP_DIR}/${script}" \
        'flash_image vendor_dlkm vendor_dlkm.img' \
        "${script} vendor_dlkm command"
    assert_contains "${TEST_TMP_DIR}/${script}" \
        'flash_image system_dlkm system_dlkm.img' \
        "${script} system_dlkm command"
    if grep -Eq 'adb reboot fastboot|fastboot reboot fastboot|is-userspace|enter_fastbootd' \
        "${TEST_TMP_DIR}/${script}"; then
        die "${script} must assume fastbootd instead of entering or probing it"
    fi
done

missing_dir="${TEST_TMP_DIR}/missing-system"
cp -a "${image_dir}" "${missing_dir}"
rm -f -- "${missing_dir}/system_dlkm.img"
missing_zip="${TEST_TMP_DIR}/missing-system.zip"
if bash "${PACKAGER}" "${missing_zip}" "${missing_dir}" >/dev/null 2>&1; then
    die 'packager accepted a missing system_dlkm.img'
fi
[[ ! -e "${missing_zip}" ]] || die 'packager left output after rejection'

printf '%s\n' 'PASS: exact seven-file fastboot package, direct fastbootd flash scripts, and rejection path'
