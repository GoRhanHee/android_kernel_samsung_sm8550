#!/usr/bin/env sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)"
PATCHER="${REPO_ROOT}/prebuilts/patch_vendor_dlkm_fstab.sh"
MODE="${1-all}"

case "${MODE}" in
    baseline|system|all) ;;
    *)
        printf 'usage: %s [baseline|system|all]\n' "$0" >&2
        exit 2
        ;;
esac

TMP_ROOT="$(mktemp -d)" || exit 1
trap 'rm -rf "${TMP_ROOT}"' EXIT HUP INT TERM

passes=0
failures=0

pass() {
    passes=$((passes + 1))
    printf 'ok - %s\n' "$1"
}

fail() {
    failures=$((failures + 1))
    printf 'not ok - %s\n' "$1" >&2
}

write_valid_fixture() {
    fixture="$1"
    printf '%s\n' \
        'vendor_dlkm /vendor_dlkm erofs ro wait,logical,first_stage_mount,avb=vbmeta_vendor' \
        'system_dlkm /system_dlkm erofs ro wait,logical,first_stage_mount,avb=vbmeta_system' \
        'system_dlkm /system_dlkm f2fs noatime wait,logical,first_stage_mount,avb' \
        'system_dlkm /system_dlkm ext4 ro wait,logical,first_stage_mount,avb=vbmeta_system' \
        'metadata /metadata ext4 noatime wait,check,avb=vbmeta' > "${fixture}"
}

run_patcher() {
    fixture="$1"
    stdout_file="${TMP_ROOT}/patch.stdout"
    stderr_file="${TMP_ROOT}/patch.stderr"
    : > "${stdout_file}"
    : > "${stderr_file}"
    "${PATCHER}" "${fixture}" > "${stdout_file}" 2> "${stderr_file}"
    PATCH_STATUS=$?
}

entry_has_avb_count() {
    fixture="$1"
    partition="$2"
    filesystem="$3"
    expected="$4"
    awk -v partition="${partition}" -v filesystem="${filesystem}" -v expected="${expected}" '
        $1 == partition && $3 == filesystem {
            entries++
            count = split($5, flags, ",")
            for (i = 1; i <= count; i++) {
                if (flags[i] ~ /^avb(=|$)/) {
                    avb_count++
                }
            }
        }
        END {
            exit !(entries == 1 && avb_count == expected)
        }
    ' "${fixture}"
}

run_baseline_tests() {
    fixture="${TMP_ROOT}/baseline-happy.fstab"
    write_valid_fixture "${fixture}"
    run_patcher "${fixture}"
    if [ "${PATCH_STATUS}" -eq 0 ] &&
        entry_has_avb_count "${fixture}" vendor_dlkm erofs 0 &&
        grep -Fq 'metadata' "${fixture}" &&
        grep -Fq 'avb=vbmeta' "${fixture}"; then
        pass 'vendor_dlkm AVB is removed while unrelated entries remain'
    else
        fail 'vendor_dlkm AVB is removed while unrelated entries remain'
    fi

    fixture="${TMP_ROOT}/missing-vendor.fstab"
    write_valid_fixture "${fixture}"
    awk '$1 != "vendor_dlkm" { print }' "${fixture}" > "${fixture}.new"
    mv "${fixture}.new" "${fixture}"
    cp "${fixture}" "${fixture}.before"
    run_patcher "${fixture}"
    if [ "${PATCH_STATUS}" -ne 0 ] && cmp -s "${fixture}.before" "${fixture}"; then
        pass 'missing vendor_dlkm entry fails without mutating fstab'
    else
        fail 'missing vendor_dlkm entry fails without mutating fstab'
    fi

    fixture="${TMP_ROOT}/missing-vendor-avb.fstab"
    write_valid_fixture "${fixture}"
    sed '1s/,avb=vbmeta_vendor//' "${fixture}" > "${fixture}.new"
    mv "${fixture}.new" "${fixture}"
    cp "${fixture}" "${fixture}.before"
    run_patcher "${fixture}"
    if [ "${PATCH_STATUS}" -ne 0 ] &&
        grep -Fq 'vendor_dlkm must contain exactly one AVB flag' "${TMP_ROOT}/patch.stderr" &&
        cmp -s "${fixture}.before" "${fixture}"; then
        pass 'missing vendor_dlkm AVB fails without mutating fstab'
    else
        fail 'missing vendor_dlkm AVB fails without mutating fstab'
    fi

    fixture="${TMP_ROOT}/multiple-vendor-avb.fstab"
    write_valid_fixture "${fixture}"
    sed '1s/$/,avb/' "${fixture}" > "${fixture}.new"
    mv "${fixture}.new" "${fixture}"
    cp "${fixture}" "${fixture}.before"
    run_patcher "${fixture}"
    if [ "${PATCH_STATUS}" -ne 0 ] &&
        grep -Fq 'vendor_dlkm must contain exactly one AVB flag' "${TMP_ROOT}/patch.stderr" &&
        cmp -s "${fixture}.before" "${fixture}"; then
        pass 'multiple vendor_dlkm AVB flags fail without mutating fstab'
    else
        fail 'multiple vendor_dlkm AVB flags fail without mutating fstab'
    fi
}

expect_system_failure_without_mutation() {
    label="$1"
    fixture="$2"
    cp "${fixture}" "${fixture}.before"
    run_patcher "${fixture}"
    if [ "${PATCH_STATUS}" -ne 0 ] && cmp -s "${fixture}.before" "${fixture}"; then
        pass "${label}"
    else
        fail "${label}"
    fi
}

run_system_tests() {
    fixture="${TMP_ROOT}/system-happy.fstab"
    write_valid_fixture "${fixture}"
    run_patcher "${fixture}"
    if [ "${PATCH_STATUS}" -eq 0 ] &&
        entry_has_avb_count "${fixture}" vendor_dlkm erofs 0 &&
        entry_has_avb_count "${fixture}" system_dlkm erofs 0 &&
        entry_has_avb_count "${fixture}" system_dlkm f2fs 0 &&
        entry_has_avb_count "${fixture}" system_dlkm ext4 0 &&
        entry_has_avb_count "${fixture}" metadata ext4 1; then
        pass 'all expected DLKM fstab AVB flags are removed'
    else
        fail 'all expected DLKM fstab AVB flags are removed'
    fi

    fixture="${TMP_ROOT}/missing-system-format.fstab"
    write_valid_fixture "${fixture}"
    awk '!($1 == "system_dlkm" && $3 == "f2fs") { print }' "${fixture}" > "${fixture}.new"
    mv "${fixture}.new" "${fixture}"
    expect_system_failure_without_mutation \
        'missing system_dlkm filesystem variant fails without mutation' "${fixture}"

    fixture="${TMP_ROOT}/duplicate-system-format.fstab"
    write_valid_fixture "${fixture}"
    sed -n '2p' "${fixture}" >> "${fixture}"
    expect_system_failure_without_mutation \
        'duplicate system_dlkm filesystem variant fails without mutation' "${fixture}"

    fixture="${TMP_ROOT}/missing-system-avb.fstab"
    write_valid_fixture "${fixture}"
    sed '2s/,avb=vbmeta_system//' "${fixture}" > "${fixture}.new"
    mv "${fixture}.new" "${fixture}"
    expect_system_failure_without_mutation \
        'missing system_dlkm AVB flag fails without mutation' "${fixture}"

    fixture="${TMP_ROOT}/multiple-system-avb.fstab"
    write_valid_fixture "${fixture}"
    sed '3s/$/,avb=vbmeta_system/' "${fixture}" > "${fixture}.new"
    mv "${fixture}.new" "${fixture}"
    expect_system_failure_without_mutation \
        'multiple system_dlkm AVB flags fail without mutation' "${fixture}"

    fixture="${TMP_ROOT}/unexpected-system-format.fstab"
    write_valid_fixture "${fixture}"
    printf '%s\n' \
        'system_dlkm /system_dlkm squashfs ro wait,logical,first_stage_mount,avb' >> "${fixture}"
    expect_system_failure_without_mutation \
        'unexpected system_dlkm filesystem variant fails without mutation' "${fixture}"
}

case "${MODE}" in
    baseline)
        run_baseline_tests
        ;;
    system)
        run_system_tests
        ;;
    all)
        run_baseline_tests
        run_system_tests
        ;;
esac

printf 'fstab tests: %d passed, %d failed\n' "${passes}" "${failures}"
[ "${failures}" -eq 0 ]
