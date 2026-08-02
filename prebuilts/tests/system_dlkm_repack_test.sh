#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly PACKAGER="${REPO_ROOT}/prebuilts/build_system_dlkm.sh"
readonly FIXTURES="$(mktemp -d)"
readonly RELEASE="5.15.209-android13-8-fixture-ab"
readonly STOCK_UUID="2b92cbbe-4b7a-57ae-9ea3-b6ccf6512b74"
trap 'rm -rf -- "${FIXTURES}"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

run_system_metadata_orchestration() {
    local workspace="$1"
    local extracted_root="${workspace}/prebuilts/system_dlkm_unpack/EXTRACTED_IMAGES/extracted_system_dlkm"

    DLKM_TEST_DIST_DIR="${workspace}/dist" \
    DLKM_TEST_PACKAGING_PREBUILTS_DIR="${workspace}/prebuilts" \
    DLKM_TEST_STOCK_SYSTEM_DLKM_URL="${workspace}/stock-system_dlkm.img" \
    SOURCE_DIR="${REPO_ROOT}" \
    DLKM_TEST_EXTRACTED_ROOT="${extracted_root}" \
        bash -c '
        set -Eeuo pipefail
        source <(sed -e "\$d" "$1")
        DIST_DIR="${DLKM_TEST_DIST_DIR}"
        PACKAGING_PREBUILTS_DIR="${DLKM_TEST_PACKAGING_PREBUILTS_DIR}"
        STOCK_SYSTEM_DLKM_URL="${DLKM_TEST_STOCK_SYSTEM_DLKM_URL}"
        EXTRACTED_ROOT="${DLKM_TEST_EXTRACTED_ROOT}"
        extract_dlkm_image() {
            [[ "$1" == system_dlkm ]] || return 97
            [[ "$2" == "${STOCK_SYSTEM_DLKM_URL}" ]] || return 98
            DLKM_EXTRACTED_ROOT="${EXTRACTED_ROOT}"
        }
        unpack_system_dlkm
    ' _ "${REPO_ROOT}/build.sh"
}

write_mock_tools() {
    local workspace="$1"
    local fake_bin="${workspace}/fake-bin"
    local cooker="${workspace}/prebuilts/LKM_Tools/03.prepare_vendor_dlkm.sh"
    local toolchain="${workspace}/kernel_platform/prebuilts/clang/host/linux-x86/clang-r450784e/bin"

    mkdir -p "${fake_bin}" "${toolchain}"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'printf "argc=%s\n" "$#" >"${DLKM_TEST_ARGS}"' \
        'index=1' \
        'for arg in "$@"; do printf "arg%s=%s\n" "${index}" "${arg}" >>"${DLKM_TEST_ARGS}"; index=$((index + 1)); done' \
        'output="$6"' \
        'rm -rf -- "${output}"' \
        'mkdir -p "${output}"' \
        'printf "CUSTOM-MODULE\n" >"${output}/custom.ko"' \
        'printf "custom.ko:\n" >"${output}/modules.dep"' \
        'printf "custom.ko\nfallback.ko\n" >"${output}/modules.load"' \
        'printf "fallback.ko\n" >"${output}/missing_modules.txt"' \
        >"${cooker}"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${toolchain}/llvm-strip"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${toolchain}/llvm-objcopy"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        '[[ "$1" == "-F" ]]' \
        'field="$2"' \
        'module="${!#}"' \
        'is_stock=0' \
        '[[ "$(basename "${module}")" == fallback.ko ]] && is_stock=1' \
        'case "${field}" in' \
        '  vermagic)' \
        '    if [[ "${DLKM_TEST_MODE}" == incompatible-vermagic && "${is_stock}" == 1 ]]; then printf "5.15.189-stock SMP\n"; else printf "5.15.209-custom SMP\n"; fi ;;' \
        '  signer)' \
        '    if [[ "${DLKM_TEST_MODE}" == incompatible-signature && "${is_stock}" == 1 ]]; then printf "Stock signer\n"; else printf "Custom signer\n"; fi ;;' \
        '  sig_key) printf "fixture-key\n" ;;' \
        '  sig_hashalgo) printf "sha256\n" ;;' \
        '  *) exit 1 ;;' \
        'esac' \
        >"${fake_bin}/modinfo"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "u:object_r:system_dlkm_file:s0"' \
        >"${fake_bin}/getfattr"
    chmod +x \
        "${cooker}" "${toolchain}/llvm-strip" "${toolchain}/llvm-objcopy" \
        "${fake_bin}/modinfo" "${fake_bin}/getfattr"
}

make_workspace() {
    local name="$1"
    local workspace="${FIXTURES}/${name}"
    local image_tools="${workspace}/prebuilts/system_dlkm_unpack"
    local extracted="${image_tools}/EXTRACTED_IMAGES/extracted_system_dlkm"
    local modules="${extracted}/lib/modules/${RELEASE}"
    local stock_image="${image_tools}/INPUT_IMAGES/system_dlkm.img"
    local raw_size
    local capacity

    mkdir -p \
        "${modules}" "${extracted}/etc" \
        "${image_tools}/INPUT_IMAGES" "${image_tools}/CONFIGS" \
        "${image_tools}/REPACKED_IMAGES" \
        "${workspace}/prebuilts/LKM_Tools/system_dlkm" \
        "${workspace}/dist/staging/lib/modules/${RELEASE}" \
        "${workspace}/out"
    cp -- "${REPO_ROOT}/prebuilts/system_dlkm_file_contexts" \
        "${workspace}/prebuilts/system_dlkm_file_contexts"
    printf 'ro.build.version.release=fixture\n' >"${extracted}/etc/build.prop"
    printf 'STOCK-CUSTOM\n' >"${modules}/custom.ko"
    printf 'STOCK-FALLBACK\n' >"${modules}/fallback.ko"
    printf '/system/lib/modules/%s/custom.ko:\n/system/lib/modules/%s/fallback.ko:\n' \
        "${RELEASE}" "${RELEASE}" >"${modules}/modules.dep"
    printf 'stock alias metadata\n' >"${modules}/modules.alias"
    printf '/system/lib/modules/%s/custom.ko\n/system/lib/modules/%s/fallback.ko\n' \
        "${RELEASE}" "${RELEASE}" >"${modules}/modules.load"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'mkdir -p "$2"' \
        'sed -n "s/:.*//p" "$1" >"$2/modules_list.txt"' \
        >"${workspace}/prebuilts/LKM_Tools/01.module_dep.sh"
    chmod +x "${workspace}/prebuilts/LKM_Tools/01.module_dep.sh"
    printf 'blocklist blocked.ko\n' \
        >"${workspace}/dist/system_dlkm.modules.blocklist"
    printf 'CUSTOM-REFERENCE\n' \
        >"${workspace}/dist/staging/lib/modules/${RELEASE}/reference.ko"
    printf 'fixture System.map\n' >"${workspace}/dist/System.map"

    run_system_metadata_orchestration "${workspace}"

    mkfs.erofs --quiet --all-root -U"${STOCK_UUID}" \
        --file-contexts="${REPO_ROOT}/prebuilts/system_dlkm_file_contexts" \
        "${stock_image}" "${extracted}"
    raw_size="$(stat -c %s -- "${stock_image}")"
    capacity=$((raw_size + 8192))
    truncate -s "${capacity}" -- "${stock_image}"
    printf 'AVBf' | dd of="${stock_image}" bs=1 seek=$((capacity - 64)) \
        conv=notrunc status=none
    touch "${image_tools}/.rootless-erofs-extract"
    write_mock_tools "${workspace}"
    printf '%s\n' "${workspace}"
}

run_packager() {
    local workspace="$1"
    local mode="$2"
    local log="$3"
    local args_log="${workspace}/cooker.args"

    DLKM_TEST_ARGS="${args_log}" \
    DLKM_TEST_MODE="${mode}" \
    PATH="${workspace}/fake-bin:${PATH}" \
    SCRIPT_DIR="${workspace}" \
    DIST_DIR="${workspace}/dist" \
    OUT_DIR="${workspace}/out" \
        bash "${PACKAGER}" >"${log}" 2>&1
}

happy_workspace="$(make_workspace happy)"
run_packager "${happy_workspace}" compatible "${FIXTURES}/happy.log"
output="${happy_workspace}/system_dlkm.img"
stock="${happy_workspace}/prebuilts/system_dlkm_unpack/INPUT_IMAGES/system_dlkm.img"
cmp -- "${happy_workspace}/dist/system_dlkm.modules.blocklist" \
    "${happy_workspace}/prebuilts/LKM_Tools/system_dlkm/modules.blocklist" ||
    fail "system blocklist did not come from the build orchestration"
[[ -s "${output}" ]] || fail "system entry point did not write SCRIPT_DIR/system_dlkm.img"
[[ "$(stat -c %s -- "${output}")" == "$(stat -c %s -- "${stock}")" ]] ||
    fail "rebuilt system image does not exactly match stock capacity"
[[ "$(dump.erofs -s "${output}" | awk '/Filesystem UUID:/ { print $NF; exit }')" == \
    "${STOCK_UUID}" ]] || fail "rebuilt system image lost the stock UUID"
[[ "$(od -An -tx1 -j $(( $(stat -c %s -- "${output}") - 64 )) \
    -N 4 -- "${output}" | tr -d ' \n')" != 41564266 ]] ||
    fail "rebuilt system image copied the stock AVB footer"
inspect="${FIXTURES}/inspect"
mkdir -p "${inspect}"
fsck.erofs -p --xattrs --extract="${inspect}" \
    --no-preserve-owner --no-preserve-perms "${output}" >/dev/null
rebuilt_modules="${inspect}/lib/modules/${RELEASE}"
grep -Fqx 'CUSTOM-MODULE' "${rebuilt_modules}/custom.ko" ||
    fail "stock module replaced the preferred custom module"
grep -Fqx 'STOCK-FALLBACK' "${rebuilt_modules}/fallback.ko" ||
    fail "compatible stock fallback was not restored"
grep -Fqx 'stock alias metadata' "${rebuilt_modules}/modules.alias" ||
    fail "stock non-.ko metadata was not preserved"
grep -Fqx 'custom.ko' "${rebuilt_modules}/modules.load" || fail "modules.load missing custom module"
grep -Fqx 'fallback.ko' "${rebuilt_modules}/modules.load" || fail "modules.load missing fallback"
grep -Fqx 'fallback.ko:' "${rebuilt_modules}/modules.dep" ||
    fail "system fallback dependency path was not normalized"
! grep -Fq '/vendor/lib/modules' "${rebuilt_modules}/modules.dep" ||
    fail "vendor-only module path leaked into system metadata"

args_log="${happy_workspace}/cooker.args"
grep -Fqx 'argc=9' "${args_log}" || fail "LKM_Tools contract did not receive nine arguments"
grep -Fqx "arg6=${happy_workspace}/prebuilts/system_dlkm_unpack/EXTRACTED_IMAGES/extracted_system_dlkm/lib/modules/${RELEASE}" \
    "${args_log}" || fail "cooker did not receive the versioned system module root"
grep -Fqx 'arg7=' "${args_log}" || fail "system cooker received a vendor_boot prune list"
grep -Fqx 'arg8=' "${args_log}" || fail "system cooker received an unexpected extra module directory"
grep -Fqx "arg9=${happy_workspace}/prebuilts/LKM_Tools/system_dlkm/modules.blocklist" \
    "${args_log}" || fail "nonempty system blocklist was not passed"

missing_workspace="$(make_workspace missing-system-workspace)"
mv -- "${missing_workspace}/prebuilts/system_dlkm_unpack" \
    "${missing_workspace}/prebuilts/vendor_dlkm_unpack"
printf 'STALE-OUTPUT\n' >"${missing_workspace}/system_dlkm.img"
set +e
run_packager "${missing_workspace}" compatible "${FIXTURES}/missing-system-workspace.log"
missing_status=$?
set -e
[[ "${missing_status}" == 1 ]] || fail "missing system_dlkm_unpack workspace was accepted"
grep -Fq \
    "extracted system_dlkm root not found: ${missing_workspace}/prebuilts/system_dlkm_unpack/EXTRACTED_IMAGES/extracted_system_dlkm" \
    "${FIXTURES}/missing-system-workspace.log" ||
    fail "missing system workspace diagnostic did not name system_dlkm_unpack"
[[ ! -e "${missing_workspace}/system_dlkm.img" ]] ||
    fail "missing system workspace emitted a final image"

no_op_workspace="$(make_workspace no-op-repacker)"
run_packager "${no_op_workspace}" compatible "${FIXTURES}/no-op-rootless.log"
no_op_image_tools="${no_op_workspace}/prebuilts/system_dlkm_unpack"
no_op_repacked="${no_op_image_tools}/REPACKED_IMAGES/system_dlkm_repacked.img"
[[ -s "${no_op_repacked}" ]] || fail "rootless setup did not create a stale repacked image"
mv -- "${no_op_image_tools}/.rootless-erofs-extract" \
    "${no_op_image_tools}/.rootless-erofs-extract.disabled"
mkdir -p \
    "${no_op_image_tools}/EXTRACTED_IMAGES/extracted_system_dlkm/.repack_info"
printf 'MOUNT_METHOD=kernel\n' \
    >"${no_op_image_tools}/EXTRACTED_IMAGES/extracted_system_dlkm/.repack_info/metadata.txt"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'printf "NOOP_REPACKER_RAN\\n" >android_image_tools.noop-ran' \
    >"${no_op_image_tools}/android_image_tools.sh"
chmod +x "${no_op_image_tools}/android_image_tools.sh"
set +e
run_packager "${no_op_workspace}" compatible "${FIXTURES}/no-op-privileged.log"
no_op_status=$?
set -e
[[ "${no_op_status}" == 1 ]] || fail "no-op privileged repacker reused stale output"
grep -Fq \
    "rebuilt system_dlkm image is missing or empty: ${no_op_repacked}" \
    "${FIXTURES}/no-op-privileged.log" ||
    fail "no-op repacker failure omitted the missing-output diagnostic"
grep -Fqx 'NOOP_REPACKER_RAN' \
    "${no_op_image_tools}/android_image_tools.noop-ran" ||
    fail "privileged no-op repacker was not invoked"
[[ ! -e "${no_op_repacked}" ]] || fail "stale repacked image survived the no-op repack"
[[ ! -e "${no_op_workspace}/system_dlkm.img" ]] ||
    fail "no-op repack failure emitted a final image"

for mode in incompatible-vermagic incompatible-signature; do
    bad_workspace="$(make_workspace "${mode}")"
    set +e
    run_packager "${bad_workspace}" "${mode}" "${FIXTURES}/${mode}.log"
    status=$?
    set -e
    [[ "${status}" == 1 ]] || fail "${mode} stock fallback was accepted"
    grep -Fq 'incompatible stock fallback module fallback.ko' \
        "${FIXTURES}/${mode}.log" || fail "${mode} diagnostic omitted module name"
    if [[ "${mode}" == incompatible-vermagic ]]; then
        grep -Fq "vermagic '5.15.189-stock SMP' != custom '5.15.209-custom SMP'" \
            "${FIXTURES}/${mode}.log" || fail "vermagic diagnostic omitted values"
    else
        grep -Fq "signer 'Stock signer' != custom 'Custom signer'" \
            "${FIXTURES}/${mode}.log" || fail "signature diagnostic omitted values"
    fi
    [[ ! -e "${bad_workspace}/system_dlkm.img" ]] ||
        fail "${mode} failure emitted a final image"
done

if [[ -n "${DLKM_REPACK_ARTIFACT_DIR:-}" ]]; then
    mkdir -p "${DLKM_REPACK_ARTIFACT_DIR}"
    cp -- "${output}" "${DLKM_REPACK_ARTIFACT_DIR}/rebuilt-system_dlkm.img"
    cp -- "${stock}" "${DLKM_REPACK_ARTIFACT_DIR}/stock-fixture-system_dlkm.img"
    cp -- "${happy_workspace}/dist/system_dlkm.modules.blocklist" \
        "${DLKM_REPACK_ARTIFACT_DIR}/dist-system_dlkm.modules.blocklist"
    cp -- "${happy_workspace}/prebuilts/LKM_Tools/system_dlkm/modules.blocklist" \
        "${DLKM_REPACK_ARTIFACT_DIR}/workspace-system_dlkm.modules.blocklist"
    cp -- "${args_log}" "${DLKM_REPACK_ARTIFACT_DIR}/cooker.args"
    printf '%s\n' "${RELEASE}" >"${DLKM_REPACK_ARTIFACT_DIR}/module-release.txt"
fi

printf 'PASS mocked system EROFS repack and module compatibility fixture\n'
