#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

assert_line() {
    local output="$1"
    local expected="$2"

    grep -Fxq "${expected}" <<<"${output}" ||
        fail "expected profile line: ${expected}"
}

assert_word() {
    local words="$1"
    local expected="$2"

    grep -qw -- "${expected}" <<<"${words}" ||
        fail "expected Kbuild object ${expected} (got: ${words})"
}

assert_contains() {
    local output="$1"
    local expected="$2"

    grep -Fq -- "${expected}" <<<"${output}" ||
        fail "expected output to contain: ${expected}"
}

assert_not_contains() {
    local output="$1"
    local rejected="$2"

    if grep -Fq -- "${rejected}" <<<"${output}"; then
        fail "expected output not to contain: ${rejected}"
    fi
}

dm3q_profile="$(BUILD_SH_PROFILE_ONLY=1 "${REPO_ROOT}/build.sh" dm3q full)"
q5q_profile="$(BUILD_SH_PROFILE_ONLY=1 "${REPO_ROOT}/build.sh" q5q full)"

assert_line "${dm3q_profile}" "WLAN_PROFILE=kiwi_v2"
assert_line "${dm3q_profile}" \
    "WLAN_EXT_MODULE=../vendor/qcom/opensource/wlan/qcacld-3.0/.kiwi_v2"
assert_line "${dm3q_profile}" "WLAN_BUILT_MODULE=kiwi_v2.ko"
assert_line "${dm3q_profile}" "WLAN_PACKAGED_MODULE=qca_cld3_kiwi_v2.ko"

assert_line "${q5q_profile}" "WLAN_PROFILE=qca6490"
assert_line "${q5q_profile}" \
    "WLAN_EXT_MODULE=../vendor/qcom/opensource/wlan/qcacld-3.0/.qca6490"
assert_line "${q5q_profile}" "WLAN_BUILT_MODULE=qca6490.ko"
assert_line "${q5q_profile}" "WLAN_PACKAGED_MODULE=qca_cld3_qca6490.ko"

cirrus_dir="${REPO_ROOT}/kernel_platform/msm-kernel/drivers/firmware/cirrus"
[[ -f "${cirrus_dir}/cl_dsp-debugfs.c" ]] ||
    fail "Fold5 Cirrus debugfs source is missing"

cirrus_objects="$({
    printf '%s\n' \
        'CONFIG_CIRRUS_FIRMWARE_CL_DSP := m' \
        "include ${cirrus_dir}/Makefile" \
        'all:' \
        $'\t@echo '\''$(obj-m)'\'''
} | make --no-print-directory -s -f - all)"
assert_word "${cirrus_objects}" "cl_dsp.o"
assert_word "${cirrus_objects}" "cl_dsp-debugfs.o"

qcacld_dir="${REPO_ROOT}/vendor/qcom/opensource/wlan/qcacld-3.0"
qca6490_options="$({
    printf '%s\n' \
        "M := ${qcacld_dir}/.qca6490" \
        "KERNEL_SRC := ${REPO_ROOT}/kernel_platform/msm-kernel" \
        "include ${qcacld_dir}/Makefile" \
        'print-options:' \
        $'\t@echo '\''$(KBUILD_OPTIONS)'\'''
} | make --no-print-directory -s -f - print-options)"
assert_contains "${qca6490_options}" "WLAN_PROFILE=qca6490"
assert_contains "${qca6490_options}" "MODNAME=qca6490"
assert_not_contains "${qca6490_options}" "CONFIG_CNSS_KIWI_V2=y"

if (( failures > 0 )); then
    echo "${failures} build configuration assertion(s) failed" >&2
    exit 1
fi

echo "Build configuration assertions passed"
