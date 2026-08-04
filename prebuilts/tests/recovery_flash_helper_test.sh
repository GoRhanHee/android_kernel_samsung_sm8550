#!/usr/bin/env sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)"
FLASHER="${REPO_ROOT}/prebuilts/flashable/META-INF/com/google/android/sm8550-flash-image.sh"
UPDATER="${REPO_ROOT}/prebuilts/flashable/META-INF/com/google/android/updater-script"
UPDATE_BINARY="${REPO_ROOT}/prebuilts/flashable/META-INF/com/google/android/update-binary"
MOCK_TOOL="${SCRIPT_DIR}/recovery_mock_tool.sh"
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
MOCK_BIN="${TMP_ROOT}/mock-bin"
mkdir -p "${MOCK_BIN}"
ln -s "${MOCK_TOOL}" "${MOCK_BIN}/dd"
ln -s "${MOCK_TOOL}" "${MOCK_BIN}/sync"
ln -s "${MOCK_TOOL}" "${MOCK_BIN}/umount"
NO_SHA_BIN="${TMP_ROOT}/no-sha-bin"
mkdir -p "${NO_SHA_BIN}"
ln -s "${MOCK_TOOL}" "${NO_SHA_BIN}/dd"
ln -s "${MOCK_TOOL}" "${NO_SHA_BIN}/sync"
ln -s "$(command -v wc)" "${NO_SHA_BIN}/wc"
ln -s /bin/sh "${NO_SHA_BIN}/sh"

REAL_DD="$(command -v dd)"
TEST_PATH="${MOCK_BIN}:/usr/bin:/bin"
passes=0
failures=0
case_number=0

pass() {
    passes=$((passes + 1))
    printf 'ok - %s\n' "$1"
}

fail() {
    failures=$((failures + 1))
    printf 'not ok - %s\n' "$1" >&2
}

make_image() {
    image="$1"
    size="$2"
    marker="$3"
    truncate -s "${size}" "${image}" || exit 1
    printf '%s' "${marker}" |
        "${REAL_DD}" of="${image}" bs=1 conv=notrunc status=none || exit 1
}

make_target() {
    target="$1"
    size="$2"
    truncate -s "${size}" "${target}" || exit 1
}

hash_prefix() {
    target="$1"
    size="$2"
    "${REAL_DD}" if="${target}" bs=1 count="${size}" status=none | sha256sum | awk '{ print $1 }'
}

run_with_target() {
    partition="$1"
    image="$2"
    target="$3"
    dd_mode="$4"
    sync_fail="$5"
    mounts_file="$6"
    umount_fail="$7"

    case_number=$((case_number + 1))
    LAST_STDOUT="${TMP_ROOT}/case-${case_number}.stdout"
    LAST_STDERR="${TMP_ROOT}/case-${case_number}.stderr"
    LAST_EVENTS="${TMP_ROOT}/case-${case_number}.events"
    : > "${LAST_EVENTS}"

    PATH="${TEST_PATH}" \
    SM8550_FLASH_TEST_TARGET="${target}" \
    SM8550_FLASH_TEST_ALLOW_FILE_TARGET=1 \
    SM8550_FLASH_TEST_MOUNTS_FILE="${mounts_file}" \
    SM8550_FLASH_TEST_EVENT_LOG="${LAST_EVENTS}" \
    SM8550_FLASH_TEST_DD_MODE="${dd_mode}" \
    SM8550_FLASH_TEST_SYNC_FAIL="${sync_fail}" \
    SM8550_FLASH_TEST_UMOUNT_FAIL="${umount_fail}" \
    SM8550_FLASH_TEST_REAL_DD="${REAL_DD}" \
        sh "${FLASHER}" "${partition}" "${image}" > "${LAST_STDOUT}" 2> "${LAST_STDERR}"
    LAST_STATUS=$?
}

run_without_target() {
    partition="$1"
    image="$2"

    case_number=$((case_number + 1))
    LAST_STDOUT="${TMP_ROOT}/case-${case_number}.stdout"
    LAST_STDERR="${TMP_ROOT}/case-${case_number}.stderr"
    LAST_EVENTS="${TMP_ROOT}/case-${case_number}.events"
    : > "${LAST_EVENTS}"

    PATH="${TEST_PATH}" \
    SM8550_FLASH_TEST_EVENT_LOG="${LAST_EVENTS}" \
    SM8550_FLASH_TEST_REAL_DD="${REAL_DD}" \
        sh "${FLASHER}" "${partition}" "${image}" > "${LAST_STDOUT}" 2> "${LAST_STDERR}"
    LAST_STATUS=$?
}

run_without_sha256() {
    partition="$1"
    image="$2"
    target="$3"

    case_number=$((case_number + 1))
    LAST_STDOUT="${TMP_ROOT}/case-${case_number}.stdout"
    LAST_STDERR="${TMP_ROOT}/case-${case_number}.stderr"
    LAST_EVENTS="${TMP_ROOT}/case-${case_number}.events"
    : > "${LAST_EVENTS}"

    PATH="${NO_SHA_BIN}" \
    SM8550_FLASH_TEST_TARGET="${target}" \
    SM8550_FLASH_TEST_ALLOW_FILE_TARGET=1 \
    SM8550_FLASH_TEST_EVENT_LOG="${LAST_EVENTS}" \
    SM8550_FLASH_TEST_REAL_DD="${REAL_DD}" \
        /bin/sh "${FLASHER}" "${partition}" "${image}" > "${LAST_STDOUT}" 2> "${LAST_STDERR}"
    LAST_STATUS=$?
}

line_number() {
    text="$1"
    occurrence="$2"
    awk -v text="${text}" -v occurrence="${occurrence}" '
        index($0, text) {
            line = NR
            if (occurrence == "first") {
                print NR
                exit
            }
        }
        END {
            if (occurrence == "last" && line != "") {
                print line
            }
        }
    ' "${UPDATER}"
}

simulate_updater() {
    fail_operation="$1"
    operation_log="$2"
    system_unmaps=0
    vendor_unmaps=0
    : > "${operation_log}"

    while IFS= read -r line; do
        operation=''
        case "${line}" in
            *update_dynamic_partitions*dynamic_partitions_op_list*) operation='resize-dlkm-metadata' ;;
            *'assert(unmap_partition("system_dlkm"));'*)
                system_unmaps=$((system_unmaps + 1))
                if [ "${system_unmaps}" -eq 1 ]; then
                    operation='prepare-unmap:system_dlkm'
                else
                    operation='cleanup-unmap:system_dlkm'
                fi
                ;;
            *'assert(unmap_partition("vendor_dlkm"));'*)
                vendor_unmaps=$((vendor_unmaps + 1))
                if [ "${vendor_unmaps}" -eq 1 ]; then
                    operation='prepare-unmap:vendor_dlkm'
                else
                    operation='cleanup-unmap:vendor_dlkm'
                fi
                ;;
            *'assert(map_partition("system_dlkm"));'*) operation='map:system_dlkm' ;;
            *'assert(map_partition("vendor_dlkm"));'*) operation='map:vendor_dlkm' ;;
            *'package_extract_file("files/system_dlkm.img"'*) operation='extract:system_dlkm' ;;
            *'package_extract_file("files/vendor_dlkm.img"'*) operation='extract:vendor_dlkm' ;;
            *'assert(package_extract_file("files/vendor_boot.img"'*) operation='extract:vendor_boot' ;;
            *'assert(package_extract_file("files/boot.img"'*) operation='extract:boot' ;;
            *'run_program('*'"system_dlkm", "/tmp/system_dlkm.img") == "0"'*) operation='flash:system_dlkm' ;;
            *'run_program('*'"vendor_dlkm", "/tmp/vendor_dlkm.img") == "0"'*) operation='flash:vendor_dlkm' ;;
            *'assert(run_program('*'"vendor_boot", "/tmp/vendor_boot.img") == "0");'*) operation='flash:vendor_boot' ;;
            *'assert(run_program('*'"boot", "/tmp/boot.img") == "0");'*) operation='flash:boot' ;;
        esac

        if [ -n "${operation}" ]; then
            printf '%s\n' "${operation}" >> "${operation_log}"
            if [ "${operation}" = "${fail_operation}" ]; then
                return 1
            fi
            case "${operation}" in
                flash:system_dlkm|flash:vendor_dlkm)
                    if updater_has_failure_cleanup "${operation#flash:}"; then
                        printf 'cleanup-unmap:%s\n' "${operation#flash:}" >> "${operation_log}"
                    fi
                    ;;
            esac
        fi
    done < "${UPDATER}"

    return 0
}

updater_has_failure_cleanup() {
    partition="$1"
    updater_compact="$(tr '\n' ' ' < "${UPDATER}")"
    case "${partition}" in
        system_dlkm)
            case "${updater_compact}" in
                *'unmap_partition("system_dlkm")'*'abort("system_dlkm flash failed")'*)
                    return 0
                    ;;
            esac
            ;;
        vendor_dlkm)
            case "${updater_compact}" in
                *'unmap_partition("vendor_dlkm")'*'abort("vendor_dlkm flash failed")'*)
                    return 0
                    ;;
            esac
            ;;
    esac
    return 1
}

simulate_failed_flash_cleanup() {
    fail_operation="$1"
    operation_log="$2"
    system_mapped=0
    vendor_mapped=0
    : > "${operation_log}"

    while IFS= read -r line; do
        operation=''
        case "${line}" in
            *update_dynamic_partitions*dynamic_partitions_op_list*) operation='resize-dlkm-metadata' ;;
            *'assert(unmap_partition("system_dlkm"));'*)
                operation='prepare-unmap:system_dlkm'
                ;;
            *'assert(unmap_partition("vendor_dlkm"));'*)
                operation='prepare-unmap:vendor_dlkm'
                ;;
            *'assert(map_partition("system_dlkm"));'*) operation='map:system_dlkm' ;;
            *'assert(map_partition("vendor_dlkm"));'*) operation='map:vendor_dlkm' ;;
            *'package_extract_file("files/system_dlkm.img"'*) operation='extract:system_dlkm' ;;
            *'package_extract_file("files/vendor_dlkm.img"'*) operation='extract:vendor_dlkm' ;;
            *'run_program('*'"system_dlkm", "/tmp/system_dlkm.img") == "0"'*) operation='flash:system_dlkm' ;;
            *'run_program('*'"vendor_dlkm", "/tmp/vendor_dlkm.img") == "0"'*) operation='flash:vendor_dlkm' ;;
        esac

        [ -n "${operation}" ] || continue
        printf '%s\n' "${operation}" >> "${operation_log}"
        case "${operation}" in
            prepare-unmap:system_dlkm) system_mapped=0 ;;
            prepare-unmap:vendor_dlkm) vendor_mapped=0 ;;
            map:system_dlkm) system_mapped=1 ;;
            map:vendor_dlkm) vendor_mapped=1 ;;
            flash:system_dlkm|flash:vendor_dlkm)
                partition="${operation#flash:}"
                if [ "${operation}" = "${fail_operation}" ]; then
                    if updater_has_failure_cleanup "${partition}"; then
                        if [ "${partition}" = 'system_dlkm' ]; then
                            system_mapped=0
                        else
                            vendor_mapped=0
                        fi
                        printf 'cleanup-unmap:%s\n' "${partition}" >> "${operation_log}"
                        printf 'abort:%s\n' "${partition}" >> "${operation_log}"
                    fi
                    printf 'state:system_dlkm=%s\n' \
                        "$( [ "${system_mapped}" -eq 0 ] && printf unmapped || printf mapped )" >> "${operation_log}"
                    printf 'state:vendor_dlkm=%s\n' \
                        "$( [ "${vendor_mapped}" -eq 0 ] && printf unmapped || printf mapped )" >> "${operation_log}"
                    return 1
                fi
                if [ "${partition}" = 'system_dlkm' ]; then
                    system_mapped=0
                else
                    vendor_mapped=0
                fi
                printf 'cleanup-unmap:%s\n' "${partition}" >> "${operation_log}"
                ;;
        esac
    done < "${UPDATER}"

    printf 'state:system_dlkm=%s\n' \
        "$( [ "${system_mapped}" -eq 0 ] && printf unmapped || printf mapped )" >> "${operation_log}"
    printf 'state:vendor_dlkm=%s\n' \
        "$( [ "${vendor_mapped}" -eq 0 ] && printf unmapped || printf mapped )" >> "${operation_log}"
    return 0
}

run_baseline_tests() {
    image="${TMP_ROOT}/vendor-happy.img"
    target="${TMP_ROOT}/vendor-happy.target"
    make_image "${image}" 8192 'vendor-dlkm-characterization'
    expected_hash="$(sha256sum "${image}" | awk '{ print $1 }')"
    make_target "${target}" 16384
    run_with_target vendor_dlkm "${image}" "${target}" '' 0 '' 0
    if [ "${LAST_STATUS}" -eq 0 ] &&
        [ "$(hash_prefix "${target}" 8192)" = "${expected_hash}" ] &&
        grep -Fq 'vendor_dlkm readback verified:' "${LAST_STDERR}" &&
        [ ! -e "${image}" ]; then
        pass 'vendor_dlkm regular-file flash writes, verifies, and removes its image'
    else
        fail 'vendor_dlkm regular-file flash writes, verifies, and removes its image'
    fi

    image="${TMP_ROOT}/unsupported.img"
    target="${TMP_ROOT}/unsupported.target"
    make_image "${image}" 4096 'unsupported-partition'
    make_target "${target}" 8192
    before_hash="$(sha256sum "${target}" | awk '{ print $1 }')"
    run_with_target userdata "${image}" "${target}" '' 0 '' 0
    if [ "${LAST_STATUS}" -eq 10 ] &&
        grep -Fq 'unsupported partition: userdata' "${LAST_STDERR}" &&
        [ "$(sha256sum "${target}" | awk '{ print $1 }')" = "${before_hash}" ]; then
        pass 'unsupported partition fails with exit 10 before writing'
    else
        fail 'unsupported partition fails with exit 10 before writing'
    fi

    vendor_map="$(line_number 'assert(map_partition("vendor_dlkm"));' first)"
    vendor_extract="$(line_number 'package_extract_file("files/vendor_dlkm.img"' first)"
    vendor_flash="$(line_number '"vendor_dlkm", "/tmp/vendor_dlkm.img") == "0"' first)"
    vendor_unmap="$(line_number 'unmap_partition("vendor_dlkm")' last)"
    vendor_boot_flash="$(line_number '"vendor_boot", "/tmp/vendor_boot.img") == "0"' first)"
    boot_flash="$(line_number '"boot", "/tmp/boot.img") == "0"' first)"
    if [ -n "${vendor_map}" ] &&
        [ "${vendor_map}" -lt "${vendor_extract}" ] &&
        [ "${vendor_extract}" -lt "${vendor_flash}" ] &&
        [ "${vendor_flash}" -lt "${vendor_unmap}" ] &&
        [ "${vendor_unmap}" -lt "${vendor_boot_flash}" ] &&
        [ "${vendor_boot_flash}" -lt "${boot_flash}" ] &&
        grep -Fq '/dev/block/mapper/${PARTITION}' "${FLASHER}"; then
        pass 'vendor updater maps, extracts, flashes, unmaps, then leaves boot last'
    else
        fail 'vendor updater maps, extracts, flashes, unmaps, then leaves boot last'
    fi
}

updater_system_contract_is_valid() {
    dynamic_resize="$(line_number 'assert(update_dynamic_partitions(' first)"
    system_prepare="$(line_number 'assert(unmap_partition("system_dlkm"));' first)"
    system_map="$(line_number 'assert(map_partition("system_dlkm"));' first)"
    system_extract="$(line_number 'package_extract_file("files/system_dlkm.img"' first)"
    system_flash="$(line_number '"system_dlkm", "/tmp/system_dlkm.img") == "0"' first)"
    system_cleanup="$(line_number 'unmap_partition("system_dlkm")' last)"
    vendor_prepare="$(line_number 'assert(unmap_partition("vendor_dlkm"));' first)"
    vendor_map="$(line_number 'assert(map_partition("vendor_dlkm"));' first)"
    vendor_extract="$(line_number 'package_extract_file("files/vendor_dlkm.img"' first)"
    vendor_flash="$(line_number '"vendor_dlkm", "/tmp/vendor_dlkm.img") == "0"' first)"
    vendor_cleanup="$(line_number 'unmap_partition("vendor_dlkm")' last)"
    vendor_boot_flash="$(line_number '"vendor_boot", "/tmp/vendor_boot.img") == "0"' first)"
    boot_flash="$(line_number '"boot", "/tmp/boot.img") == "0"' first)"

    [ -n "${dynamic_resize}" ] &&
        [ -n "${system_prepare}" ] &&
        [ "${dynamic_resize}" -lt "${system_prepare}" ] &&
        [ "${system_prepare}" -lt "${system_map}" ] &&
        [ "${system_map}" -lt "${system_extract}" ] &&
        [ "${system_extract}" -lt "${system_flash}" ] &&
        [ "${system_flash}" -lt "${system_cleanup}" ] &&
        [ "${system_cleanup}" -lt "${vendor_prepare}" ] &&
        [ "${vendor_prepare}" -lt "${vendor_map}" ] &&
        [ "${vendor_map}" -lt "${vendor_extract}" ] &&
        [ "${vendor_extract}" -lt "${vendor_flash}" ] &&
        [ "${vendor_flash}" -lt "${vendor_cleanup}" ] &&
        [ "${vendor_cleanup}" -lt "${vendor_boot_flash}" ] &&
        [ "${vendor_boot_flash}" -lt "${boot_flash}" ] &&
        updater_has_failure_cleanup system_dlkm &&
        updater_has_failure_cleanup vendor_dlkm &&
        grep -Fqi 'no rollback after' "${UPDATER}"
}

updater_has_dynamic_resize_support() {
    command -v strings >/dev/null 2>&1 || return 1
    strings "${UPDATE_BINARY}" | grep -Fq 'update_dynamic_partitions' ||
        return 1
    strings "${UPDATE_BINARY}" | grep -Fxq 'resize'
}

expect_status() {
    expected_status="$1"
    diagnostic="$2"
    label="$3"
    if [ "${LAST_STATUS}" -eq "${expected_status}" ] &&
        grep -Fq "${diagnostic}" "${LAST_STDERR}"; then
        pass "${label}"
    else
        fail "${label}"
    fi
}

helper_requires_real_target_capacity() {
    grep -Fq 'required recovery command not found: blockdev' "${FLASHER}" &&
        grep -Fq 'could not determine target capacity: ${TARGET}' "${FLASHER}" &&
        ! grep -Fq 'capacity verification skipped' "${FLASHER}"
}

run_system_tests() {
    if updater_system_contract_is_valid; then
        pass 'updater resizes DLKM metadata before map-extract-flash-unmap order with boot last'
    else
        fail 'updater resizes DLKM metadata before map-extract-flash-unmap order with boot last'
    fi

    if updater_has_dynamic_resize_support; then
        pass 'bundled update-binary supports dynamic partition resize operations'
    else
        fail 'bundled update-binary supports dynamic partition resize operations'
    fi

    if helper_requires_real_target_capacity; then
        pass 'real-target capacity verification is mandatory and cannot be skipped'
    else
        fail 'real-target capacity verification is mandatory and cannot be skipped'
    fi

    image="${TMP_ROOT}/system-happy.img"
    target="${TMP_ROOT}/system-happy.target"
    make_image "${image}" 8192 'system-dlkm-happy'
    expected_hash="$(sha256sum "${image}" | awk '{ print $1 }')"
    make_target "${target}" 16384
    run_with_target system_dlkm "${image}" "${target}" '' 0 '' 0
    if [ "${LAST_STATUS}" -eq 0 ] &&
        [ "$(hash_prefix "${target}" 8192)" = "${expected_hash}" ] &&
        grep -Fq 'system_dlkm readback verified:' "${LAST_STDERR}" &&
        [ ! -e "${image}" ]; then
        pass 'system_dlkm regular-file happy path verifies readback'
    else
        fail 'system_dlkm regular-file happy path verifies readback'
    fi

    image="${TMP_ROOT}/missing-sha256.img"
    target="${TMP_ROOT}/missing-sha256.target"
    make_image "${image}" 4096 'missing-sha256'
    make_target "${target}" 8192
    before_hash="$(sha256sum "${target}" | awk '{ print $1 }')"
    run_without_sha256 system_dlkm "${image}" "${target}"
    if [ "${LAST_STATUS}" -eq 14 ] &&
        grep -Fq 'required recovery command not found: sha256sum' "${LAST_STDERR}" &&
        ! grep -Fq 'flash complete' "${LAST_STDERR}" &&
        ! grep -Fq 'dd-write' "${LAST_EVENTS}" &&
        [ "$(sha256sum "${target}" | awk '{ print $1 }')" = "${before_hash}" ] &&
        [ -e "${image}" ]; then
        pass 'missing sha256sum fails before writing without a completion message'
    else
        fail 'missing sha256sum fails before writing without a completion message'
    fi

    image="${TMP_ROOT}/missing-target.img"
    make_image "${image}" 4096 'missing-target'
    run_without_target system_dlkm "${image}"
    expect_status 12 'system_dlkm block device was not found' \
        'missing system_dlkm target fails with exit 12'

    image="${TMP_ROOT}/undersize.img"
    target="${TMP_ROOT}/undersize.target"
    make_image "${image}" 8192 'undersize-target'
    make_target "${target}" 4096
    run_with_target system_dlkm "${image}" "${target}" '' 0 '' 0
    expect_status 16 'is larger than target' \
        'undersize system_dlkm target fails with exit 16'

    image="${TMP_ROOT}/misaligned.img"
    target="${TMP_ROOT}/misaligned.target"
    make_image "${image}" 4097 'misaligned-image'
    make_target "${target}" 8192
    run_with_target system_dlkm "${image}" "${target}" '' 0 '' 0
    expect_status 15 'image size is not 4096-byte aligned' \
        'misaligned system_dlkm image fails with exit 15'

    image="${TMP_ROOT}/dd-failure.img"
    target="${TMP_ROOT}/dd-failure.target"
    make_image "${image}" 4096 'dd-failure'
    make_target "${target}" 8192
    before_hash="$(sha256sum "${target}" | awk '{ print $1 }')"
    run_with_target system_dlkm "${image}" "${target}" write-fail 0 '' 0
    if [ "${LAST_STATUS}" -eq 18 ] &&
        grep -Fq 'dd failed while writing system_dlkm' "${LAST_STDERR}" &&
        [ "$(sha256sum "${target}" | awk '{ print $1 }')" = "${before_hash}" ]; then
        pass 'system_dlkm dd failure returns exit 18 without changing target'
    else
        fail 'system_dlkm dd failure returns exit 18 without changing target'
    fi

    image="${TMP_ROOT}/sync-failure.img"
    target="${TMP_ROOT}/sync-failure.target"
    make_image "${image}" 4096 'sync-failure'
    make_target "${target}" 8192
    run_with_target system_dlkm "${image}" "${target}" '' 1 '' 0
    expect_status 19 'sync failed after writing system_dlkm' \
        'system_dlkm sync failure returns exit 19'

    image="${TMP_ROOT}/readback-mismatch.img"
    target="${TMP_ROOT}/readback-mismatch.target"
    make_image "${image}" 4096 'readback-mismatch'
    make_target "${target}" 8192
    run_with_target system_dlkm "${image}" "${target}" readback-mismatch 0 '' 0
    expect_status 17 'system_dlkm readback hash mismatch' \
        'system_dlkm readback mismatch returns exit 17'

    image="${TMP_ROOT}/mounted-system.img"
    target="${TMP_ROOT}/mounted-system.target"
    mounts="${TMP_ROOT}/mounted-system.mounts"
    make_image "${image}" 4096 'mounted-system'
    make_target "${target}" 8192
    printf '%s\n' \
        '/dev/block/mapper/system_dlkm /system_dlkm erofs ro 0 0' > "${mounts}"
    run_with_target system_dlkm "${image}" "${target}" '' 0 "${mounts}" 0
    first_event="$(sed -n '1p' "${LAST_EVENTS}")"
    second_event="$(sed -n '2p' "${LAST_EVENTS}")"
    if [ "${LAST_STATUS}" -eq 0 ] &&
        [ "${first_event}" = 'umount:/system_dlkm' ] &&
        [ "${second_event}" = 'dd-write' ]; then
        pass 'mounted system_dlkm is unmounted before its write'
    else
        fail 'mounted system_dlkm is unmounted before its write'
    fi

    image="${TMP_ROOT}/unmount-failure.img"
    target="${TMP_ROOT}/unmount-failure.target"
    make_image "${image}" 4096 'unmount-failure'
    make_target "${target}" 8192
    run_with_target system_dlkm "${image}" "${target}" '' 0 "${mounts}" 1
    expect_status 13 'failed to unmount /system_dlkm' \
        'mounted system_dlkm unmount failure returns exit 13'

    operation_log="${TMP_ROOT}/updater-happy.operations"
    if simulate_updater '' "${operation_log}" &&
        cmp -s "${operation_log}" "${SCRIPT_DIR}/recovery_updater_operations.expected"; then
        pass 'mocked updater completes the four-image asserted operation sequence'
    else
        fail 'mocked updater completes the four-image asserted operation sequence'
    fi

    operation_log="${TMP_ROOT}/updater-map-failure.operations"
    if ! simulate_updater 'map:system_dlkm' "${operation_log}" &&
        ! grep -Fq 'flash:' "${operation_log}"; then
        pass 'mocked system_dlkm mapping failure stops before any write'
    else
        fail 'mocked system_dlkm mapping failure stops before any write'
    fi

    operation_log="${TMP_ROOT}/updater-system-flash-failure.operations"
    if ! simulate_failed_flash_cleanup 'flash:system_dlkm' "${operation_log}" &&
        cmp -s "${operation_log}" "${SCRIPT_DIR}/recovery_updater_failure_cleanup.expected"; then
        pass 'failed system_dlkm flash unmaps before aborting with both mappings clear'
    else
        fail 'failed system_dlkm flash unmaps before aborting with both mappings clear'
    fi

    operation_log="${TMP_ROOT}/updater-vendor-flash-failure.operations"
    if ! simulate_failed_flash_cleanup 'flash:vendor_dlkm' "${operation_log}" &&
        cmp -s "${operation_log}" "${SCRIPT_DIR}/recovery_updater_vendor_failure_cleanup.expected"; then
        pass 'failed vendor_dlkm flash unmaps before aborting with both mappings clear'
    else
        fail 'failed vendor_dlkm flash unmaps before aborting with both mappings clear'
    fi
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

printf 'recovery tests: %d passed, %d failed\n' "${passes}" "${failures}"
[ "${failures}" -eq 0 ]
