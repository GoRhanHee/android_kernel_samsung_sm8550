#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_DIR="${SOURCE_DIR:-${SCRIPT_DIR}}"
readonly KERNEL_PLATFORM="${SOURCE_DIR}/kernel_platform"
readonly TOOLCHAIN_URL="${TOOLCHAIN_URL:-https://github.com/GoRhanHee/samsung_sm8550_toolchain/releases/download/toolchain/toolchain.tar.xz}"
readonly CLANG_BIN="${KERNEL_PLATFORM}/prebuilts/clang/host/linux-x86/clang-r450784e/bin/clang"
readonly KSU_SETUP_URL="https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh"
readonly JOBS="${JOBS:-$(nproc)}"
export LTO="${LTO:-thin}"

BUILD_TARGET=""
MODEL=""
DEVICE_DISPLAY_NAME=""
PROJECT_NAME=""
REGION=""
CARRIER=""
CHIPSET_NAME=""
TARGET_PRODUCT=""
TARGET_BOARD_PLATFORM=""
STOCK_VENDOR_BOOT_URL=""
STOCK_VENDOR_DLKM_URL=""
STOCK_SYSTEM_DLKM_URL=""
SEC_PROJECT_CONFIG=""
WLAN_PROFILE=""
WLAN_EXT_MODULE=""
WLAN_BUILT_MODULE=""
WLAN_PACKAGED_MODULE=""
ANDROID_BUILD_TOP=""
ANDROID_PRODUCT_OUT=""
ANDROID_KERNEL_OUT=""
OUT_DIR=""
DIST_DIR=""
PACKAGE_DIR=""
TARGET_TEMP_DIR=""
TARGET_DOWNLOAD_DIR=""
TARGET_UNPACK_DIR=""
PACKAGING_WORK_DIR=""
PACKAGING_PREBUILTS_DIR=""
DOWNLOAD_DIR=""
UNPACK_DIR=""
FLASHABLE_ZIP=""
CUSTOM_SYSTEM_DLKM_IMAGE=""
TMPDIR=""
DLKM_EXTRACTED_ROOT=""
COMMON_HEAD_BEFORE=""
COMMON_STATUS_BEFORE=""
KSU_SETUP_SCRIPT=""
KSU_RESTORE_PATCH=""
KSU_IMPORT_STARTED=0
KSU_REUSE_EXISTING=0

select_wlan_profile() {
    local project_config="${KERNEL_PLATFORM}/msm-kernel/arch/arm64/configs/vendor/${SEC_PROJECT_CONFIG}_project.config"

    [[ -f "${project_config}" ]] ||
        die "project config not found: ${project_config}"

    WLAN_PROFILE="kiwi_v2"
    if grep -Eq '^CONFIG_SEC_(DM1Q|DM2Q|Q5Q)_PROJECT=y$' "${project_config}"; then
        WLAN_PROFILE="qca6490"
    fi

    WLAN_EXT_MODULE="../vendor/qcom/opensource/wlan/qcacld-3.0/.${WLAN_PROFILE}"
    WLAN_BUILT_MODULE="${WLAN_PROFILE}.ko"
    WLAN_PACKAGED_MODULE="qca_cld3_${WLAN_PROFILE}.ko"
}

usage() {
    cat <<EOF
Usage:
  ${SCRIPT_NAME} dm1q full
  ${SCRIPT_NAME} dm2q full
  ${SCRIPT_NAME} dm3q full
  ${SCRIPT_NAME} q5q full
  ${SCRIPT_NAME} -h
  ${SCRIPT_NAME} --help
  ${SCRIPT_NAME} help

Devices:
  dm1q  Samsung Galaxy S23 (SM-S911N)
  dm2q  Samsung Galaxy S23+ (SM-S916N)
  dm3q  Samsung Galaxy S23 Ultra (SM-S918N)
  q5q   Samsung Galaxy Z Fold5 (SM-F946N)

Examples:
  ${SCRIPT_NAME} dm1q full
  ${SCRIPT_NAME} dm2q full
  ${SCRIPT_NAME} dm3q full
  ${SCRIPT_NAME} q5q full

Environment overrides:
  SOURCE_DIR       Kernel source directory (default: ${SOURCE_DIR})
  JOBS             Parallel build jobs (default: ${JOBS})
  FULL_OUT_DIR     Base directory for target-specific full-build output
  TOOLCHAIN_URL    Samsung toolchain archive URL
  LTO              LTO mode: none, thin or full (default: ${LTO})
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

select_device_profile() {
    local device="$1"
    local output_base
    local run_key="${BUILD_RUN_KEY:-run-${BASHPID}}"

    case "${device}" in
        dm1q)
            BUILD_TARGET="dm1q_kor_singlex"
            MODEL="dm1q"
            DEVICE_DISPLAY_NAME="Galaxy S23"
            STOCK_VENDOR_BOOT_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/S911NKSS8FZG1_KOO_OKR/vendor_boot.img"
            STOCK_VENDOR_DLKM_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/S911NKSS8FZG1_KOO_OKR/vendor_dlkm.img"
            STOCK_SYSTEM_DLKM_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/S911NKSS8FZG1_KOO_OKR/system_dlkm.img"
            ;;
        dm2q)
            BUILD_TARGET="dm2q_kor_singlex"
            MODEL="dm2q"
            DEVICE_DISPLAY_NAME="Galaxy S23+"
            STOCK_VENDOR_BOOT_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/S916NKSS8FZG1_KOO_OKR/vendor_boot.img"
            STOCK_VENDOR_DLKM_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/S916NKSS8FZG1_KOO_OKR/vendor_dlkm.img"
            STOCK_SYSTEM_DLKM_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/S916NKSS8FZG1_KOO_OKR/system_dlkm.img"
            ;;
        dm3q)
            BUILD_TARGET="dm3q_kor_singlex"
            MODEL="dm3q"
            DEVICE_DISPLAY_NAME="Galaxy S23 Ultra"
            STOCK_VENDOR_BOOT_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/S918NKSS8FZG1_KOO_OKR/vendor_boot.img"
            STOCK_VENDOR_DLKM_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/S918NKSS8FZG1_KOO_OKR/vendor_dlkm.img"
            STOCK_SYSTEM_DLKM_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/S918NKSS8FZG1_KOO_OKR/system_dlkm.img"
            ;;
        q5q)
            BUILD_TARGET="q5q_kor_singlex"
            MODEL="q5q"
            DEVICE_DISPLAY_NAME="Galaxy Z Fold5"
            STOCK_VENDOR_BOOT_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/F946NKSS6GZG3_KOO_OKR/vendor_boot.img"
            STOCK_VENDOR_DLKM_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/F946NKSS6GZG3_KOO_OKR/vendor_dlkm.img"
            STOCK_SYSTEM_DLKM_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/F946NKSS6GZG3_KOO_OKR/system_dlkm.img"
            ;;
        *)
            return 2
            ;;
    esac

    PROJECT_NAME="${MODEL}"
    SEC_PROJECT_CONFIG="${MODEL}"
    select_wlan_profile
    REGION="kor"
    CARRIER="singlex"
    CHIPSET_NAME="kalama"
    TARGET_PRODUCT="gki"
    TARGET_BOARD_PLATFORM="gki"
    ANDROID_BUILD_TOP="${SOURCE_DIR}"
    output_base="${FULL_OUT_DIR:-${ANDROID_BUILD_TOP}/out}"
    ANDROID_PRODUCT_OUT="${output_base}/${MODEL}/target/product/${MODEL}"
    OUT_DIR="${output_base}/${MODEL}/msm-${CHIPSET_NAME}-${CHIPSET_NAME}-${TARGET_PRODUCT}"
    ANDROID_KERNEL_OUT="${OUT_DIR}/android-kernel-out"
    DIST_DIR="${OUT_DIR}/dist"
    PACKAGE_DIR="${OUT_DIR}/packaged"
    TARGET_TEMP_DIR="${OUT_DIR}/tmp"
    TARGET_DOWNLOAD_DIR="${OUT_DIR}/downloads"
    TARGET_UNPACK_DIR="${OUT_DIR}/unpack"
    PACKAGING_WORK_DIR="${TARGET_TEMP_DIR}/${run_key}"
    PACKAGING_PREBUILTS_DIR="${PACKAGING_WORK_DIR}/prebuilts"
    DOWNLOAD_DIR="${TARGET_DOWNLOAD_DIR}/${run_key}"
    UNPACK_DIR="${TARGET_UNPACK_DIR}/${run_key}"
    FLASHABLE_ZIP="${PACKAGE_DIR}/${MODEL}-kernel-recovery-flashable.zip"
    CUSTOM_SYSTEM_DLKM_IMAGE="${PACKAGING_WORK_DIR}/system_dlkm.img"
    TMPDIR="${PACKAGING_WORK_DIR}/process-tmp"

    export BUILD_TARGET MODEL DEVICE_DISPLAY_NAME PROJECT_NAME REGION CARRIER
    export CHIPSET_NAME TARGET_PRODUCT TARGET_BOARD_PLATFORM
    export STOCK_VENDOR_BOOT_URL STOCK_VENDOR_DLKM_URL STOCK_SYSTEM_DLKM_URL
    export SEC_PROJECT_CONFIG
    export WLAN_PROFILE WLAN_EXT_MODULE WLAN_BUILT_MODULE WLAN_PACKAGED_MODULE
    export ANDROID_BUILD_TOP ANDROID_PRODUCT_OUT ANDROID_KERNEL_OUT
    export OUT_DIR DIST_DIR CUSTOM_SYSTEM_DLKM_IMAGE TMPDIR
}

print_device_profile() {
    printf '%s\n' \
        "BUILD_TARGET=${BUILD_TARGET}" \
        "MODEL=${MODEL}" \
        "DEVICE_DISPLAY_NAME=${DEVICE_DISPLAY_NAME}" \
        "PROJECT_NAME=${PROJECT_NAME}" \
        "CHIPSET_NAME=${CHIPSET_NAME}" \
        "TARGET_PRODUCT=${TARGET_PRODUCT}" \
        "TARGET_BOARD_PLATFORM=${TARGET_BOARD_PLATFORM}" \
        "REGION=${REGION}" \
        "CARRIER=${CARRIER}" \
        "STOCK_VENDOR_BOOT_URL=${STOCK_VENDOR_BOOT_URL}" \
        "STOCK_VENDOR_DLKM_URL=${STOCK_VENDOR_DLKM_URL}" \
        "STOCK_SYSTEM_DLKM_URL=${STOCK_SYSTEM_DLKM_URL}" \
        "SEC_PROJECT_CONFIG=${SEC_PROJECT_CONFIG}" \
        "WLAN_PROFILE=${WLAN_PROFILE}" \
        "WLAN_EXT_MODULE=${WLAN_EXT_MODULE}" \
        "WLAN_BUILT_MODULE=${WLAN_BUILT_MODULE}" \
        "WLAN_PACKAGED_MODULE=${WLAN_PACKAGED_MODULE}" \
        "OUT_DIR=${OUT_DIR}" \
        "ANDROID_KERNEL_OUT=${ANDROID_KERNEL_OUT}" \
        "DIST_DIR=${DIST_DIR}" \
        "PACKAGE_DIR=${PACKAGE_DIR}" \
        "TEMP_DIR=${PACKAGING_WORK_DIR}" \
        "TMPDIR=${TMPDIR}" \
        "DOWNLOAD_DIR=${DOWNLOAD_DIR}" \
        "UNPACK_DIR=${UNPACK_DIR}" \
        "CUSTOM_SYSTEM_DLKM_IMAGE=${CUSTOM_SYSTEM_DLKM_IMAGE}" \
        "FLASHABLE_ZIP=${FLASHABLE_ZIP}"
}

record_common_state() {
    local common_dir="${KERNEL_PLATFORM}/common"
    local top_level

    require_command git
    [[ -e "${common_dir}/.git" ]] ||
        die "common submodule is not initialized: ${common_dir}"
    [[ -n "$(find -H "${common_dir}" -mindepth 1 -maxdepth 1 ! -name .git -print -quit)" ]] ||
        die "common submodule is empty: ${common_dir}"
    top_level="$(git -C "${common_dir}" rev-parse --show-toplevel 2>/dev/null)" ||
        die "common submodule is not initialized: ${common_dir}"
    [[ "${top_level}" -ef "${common_dir}" ]] ||
        die "common submodule is not initialized: ${common_dir}"

    COMMON_HEAD_BEFORE="$(git -C "${common_dir}" rev-parse HEAD)"
    COMMON_STATUS_BEFORE="$(
        git -C "${common_dir}" status --porcelain=v1 --untracked-files=all
    )"
    [[ -z "${COMMON_STATUS_BEFORE}" ]] ||
        die "common submodule must be clean before the build"

    if [[ -d "${common_dir}/KernelSU-Next" ||
          -d "${common_dir}/KernelSU" ||
          -e "${common_dir}/drivers/kernelsu" ]]; then
        KSU_REUSE_EXISTING=1
        echo "[KernelSU] Reusing the checked-in integration"
    else
        echo "[KernelSU-Next] A temporary dev-branch integration will be imported"
    fi

    trap cleanup_common EXIT
}

import_kernelsu_next() {
    local common_dir="${KERNEL_PLATFORM}/common"
    local changed_file

    if (( KSU_REUSE_EXISTING == 1 )); then
        return 0
    fi

    require_command bash
    require_command curl
    require_command git

    KSU_SETUP_SCRIPT="${PACKAGING_WORK_DIR}/kernelsu-next-setup.sh"
    KSU_RESTORE_PATCH="${PACKAGING_WORK_DIR}/kernelsu-next-common.patch"

    echo "[KernelSU-Next] Downloading the official setup script"
    curl -fLSs --retry 3 -o "${KSU_SETUP_SCRIPT}" "${KSU_SETUP_URL}"

    KSU_IMPORT_STARTED=1
    echo "[KernelSU-Next] Importing dev branch"
    (
        cd "${common_dir}"
        bash "${KSU_SETUP_SCRIPT}" dev
    )

    git -C "${common_dir}" diff --binary --full-index > "${KSU_RESTORE_PATCH}"
    [[ -s "${KSU_RESTORE_PATCH}" ]] ||
        die "KernelSU-Next setup did not modify the common kernel"

    while IFS= read -r changed_file; do
        case "${changed_file}" in
            drivers/Kconfig|drivers/Makefile)
                ;;
            *)
                die "KernelSU-Next setup changed an unexpected tracked file: ${changed_file}"
                ;;
        esac
    done < <(git -C "${common_dir}" diff --name-only)

    [[ -L "${common_dir}/drivers/kernelsu" ]] ||
        die "KernelSU-Next setup did not create drivers/kernelsu"
    [[ -d "${common_dir}/KernelSU-Next" ]] ||
        die "KernelSU-Next setup did not clone KernelSU-Next"

    echo "[KernelSU-Next] Restore patch: ${KSU_RESTORE_PATCH}"
}

validate_msm_state() {
    local msm_dir="${KERNEL_PLATFORM}/msm-kernel"
    local top_level
    local head
    local configured_branch
    local tracking_ref
    local tracking_head
    local status

    [[ -e "${msm_dir}/.git" ]] ||
        die "msm-kernel submodule is not initialized: ${msm_dir}"
    [[ -n "$(find "${msm_dir}" -mindepth 1 -maxdepth 1 ! -name .git -print -quit)" ]] ||
        die "msm-kernel submodule is empty: ${msm_dir}"
    top_level="$(git -C "${msm_dir}" rev-parse --show-toplevel 2>/dev/null)" ||
        die "msm-kernel submodule is not initialized: ${msm_dir}"
    [[ "${top_level}" == "${msm_dir}" ]] ||
        die "msm-kernel submodule is not initialized: ${msm_dir}"

    head="$(git -C "${msm_dir}" rev-parse --verify HEAD)"
    status="$(
        git -C "${msm_dir}" status --porcelain=v1 --untracked-files=all
    )"
    [[ -z "${status}" ]] ||
        die "msm-kernel submodule must be clean before the build"

    configured_branch="$(
        git -C "${SOURCE_DIR}" config -f .gitmodules \
            --get submodule.kernel_platform/msm-kernel.branch 2>/dev/null || true
    )"
    tracking_ref="refs/remotes/origin/${configured_branch}"
    if [[ -n "${configured_branch}" ]] &&
       git -C "${msm_dir}" show-ref --verify --quiet "${tracking_ref}"; then
        tracking_head="$(git -C "${msm_dir}" rev-parse "${tracking_ref}")"
        [[ "${head}" == "${tracking_head}" ]] ||
            die "msm-kernel HEAD does not match ${tracking_ref}"
        echo "[submodule] msm-kernel ${head} matches ${tracking_ref}"
    else
        echo "[submodule] msm-kernel ${head} is initialized and clean"
    fi
}

verify_common_unchanged() {
    local common_dir="${KERNEL_PLATFORM}/common"
    local head_after
    local status_after

    [[ -n "${COMMON_HEAD_BEFORE}" ]] || return 0
    head_after="$(git -C "${common_dir}" rev-parse HEAD 2>/dev/null)" || {
        echo "error: common submodule became unavailable during the build" >&2
        return 1
    }
    status_after="$(
        git -C "${common_dir}" status --porcelain=v1 --untracked-files=all
    )" || {
        echo "error: common submodule status could not be read after the build" >&2
        return 1
    }

    if [[ "${head_after}" != "${COMMON_HEAD_BEFORE}" ||
          "${status_after}" != "${COMMON_STATUS_BEFORE}" ]]; then
        echo "error: the build changed kernel_platform/common" >&2
        return 1
    fi
}

cleanup_kernelsu_next() {
    local common_dir="${KERNEL_PLATFORM}/common"
    local kernelsu_dir="${KERNEL_PLATFORM}/common/KernelSU-Next"
    local kernelsu_link="${KERNEL_PLATFORM}/common/drivers/kernelsu"
    local fallback_patch="${PACKAGING_WORK_DIR}/kernelsu-next-common-fallback.patch"
    local cleanup_status=0

    (( KSU_IMPORT_STARTED == 1 )) || return 0

    echo "[KernelSU-Next] Restoring common kernel state"
    if [[ -s "${KSU_RESTORE_PATCH}" ]]; then
        git -C "${common_dir}" apply --reverse "${KSU_RESTORE_PATCH}" ||
            cleanup_status=1
    elif ! git -C "${common_dir}" diff --quiet; then
        git -C "${common_dir}" diff --binary --full-index > "${fallback_patch}"
        git -C "${common_dir}" apply --reverse "${fallback_patch}" ||
            cleanup_status=1
    fi

    if [[ -L "${kernelsu_link}" ]]; then
        rm -- "${kernelsu_link}" || cleanup_status=1
    elif [[ -e "${kernelsu_link}" ]]; then
        echo "error: refusing to remove non-symlink path: ${kernelsu_link}" >&2
        cleanup_status=1
    fi

    if [[ -L "${kernelsu_dir}" ]]; then
        echo "error: refusing to recursively remove symlink: ${kernelsu_dir}" >&2
        cleanup_status=1
    elif [[ -d "${kernelsu_dir}" ]]; then
        rm -rf -- "${kernelsu_dir}" || cleanup_status=1
    elif [[ -e "${kernelsu_dir}" ]]; then
        echo "error: refusing to remove unexpected path: ${kernelsu_dir}" >&2
        cleanup_status=1
    fi

    KSU_IMPORT_STARTED=0
    return "${cleanup_status}"
}

cleanup_common() {
    local build_status=$?
    local cleanup_status=0

    trap - EXIT
    cleanup_kernelsu_next || cleanup_status=1
    verify_common_unchanged || cleanup_status=1

    if (( cleanup_status != 0 )); then
        echo "error: failed to restore kernel_platform/common" >&2
        return 1
    fi
    return "${build_status}"
}

prepare_toolchain() {
    if [[ -x "${CLANG_BIN}" ]]; then
        echo "[toolchain] Using ${CLANG_BIN}"
        return
    fi

    require_command wget
    require_command tar

    local archive
    mkdir -p "${DOWNLOAD_DIR}"
    archive="$(mktemp "${DOWNLOAD_DIR}/sm8550-toolchain.XXXXXX.tar.xz")"

    echo "[toolchain] Downloading ${TOOLCHAIN_URL}"
    wget -q --show-progress --progress=dot:giga \
        -O "${archive}" "${TOOLCHAIN_URL}"

    echo "[toolchain] Extracting prebuilts into ${KERNEL_PLATFORM}"
    tar -xf "${archive}" -C "${KERNEL_PLATFORM}" \
        --strip-components=1 toolchain/prebuilts
    rm -f "${archive}"

    [[ -x "${CLANG_BIN}" ]] || \
        die "clang-r450784e was not found after extracting the toolchain"
}

build_full() {
    export TARGET_BUILD_VARIANT="${TARGET_BUILD_VARIANT:-user}"
    export MERGE_CONFIG="${ANDROID_BUILD_TOP}/kernel_platform/common/scripts/kconfig/merge_config.sh"

    if [[ -e "${OUT_DIR}/host/bin/ufdt_apply_overlay" ]]; then
        chmod u+w "${OUT_DIR}/host/bin/ufdt_apply_overlay"
    fi

    export KBUILD_EXTRA_SYMBOLS="${OUT_DIR%/*}/vendor/qcom/opensource/mmrm-driver/Module.symvers \
        ${OUT_DIR%/*}/vendor/qcom/opensource/mm-drivers/hw_fence/Module.symvers \
        ${OUT_DIR%/*}/vendor/qcom/opensource/mm-drivers/sync_fence/Module.symvers \
        ${OUT_DIR%/*}/vendor/qcom/opensource/mm-drivers/msm_ext_display/Module.symvers \
        ${OUT_DIR%/*}/vendor/qcom/opensource/securemsm-kernel/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/graphics-kernel/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/datarmnet/core/Module.symvers \
		${OUT_DIR%/*}/${WLAN_EXT_MODULE#../}/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/wlan/platform/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/camera-kernel/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/eva-kernel/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/video-driver/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/display-drivers/msm/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/datarmnet-ext/aps/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/datarmnet-ext/wlan/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/datarmnet-ext/shs/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/datarmnet-ext/perf_tether/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/datarmnet-ext/perf/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/datarmnet-ext/sch/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/datarmnet-ext/offload/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/bt-kernel/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/dataipa/drivers/platform/msm/Module.symvers \
		${OUT_DIR%/*}/vendor/qcom/opensource/audio-kernel/Module.symvers \
        "

    export MODNAME="audio_dlkm"
    export KBUILD_EXT_MODULES="../vendor/qcom/opensource/mm-drivers/msm_ext_display \
        ../vendor/qcom/opensource/mm-drivers/sync_fence \
        ../vendor/qcom/opensource/mm-drivers/hw_fence \
        ../vendor/qcom/opensource/mmrm-driver \
        ../vendor/qcom/opensource/securemsm-kernel \
        ../vendor/qcom/opensource/display-drivers/msm \
        ../vendor/qcom/opensource/audio-kernel \
        ../vendor/qcom/opensource/camera-kernel \
        ../vendor/qcom/opensource/video-driver \
        ../vendor/qcom/opensource/graphics-kernel \
        ../vendor/qcom/opensource/dataipa/drivers/platform/msm \
        ../vendor/qcom/opensource/datarmnet/core \
        ../vendor/qcom/opensource/datarmnet-ext/aps \
        ../vendor/qcom/opensource/datarmnet-ext/offload \
        ../vendor/qcom/opensource/datarmnet-ext/shs \
        ../vendor/qcom/opensource/datarmnet-ext/sch \
        ../vendor/qcom/opensource/datarmnet-ext/perf \
        ../vendor/qcom/opensource/datarmnet-ext/perf_tether \
        ../vendor/qcom/opensource/datarmnet-ext/wlan \
        ../vendor/qcom/opensource/eva-kernel \
        ../vendor/qcom/opensource/wlan/platform \
        ../vendor/qcom/opensource/bt-kernel \
        ${WLAN_EXT_MODULE} \
    "  

    echo "[full] BUILD_TARGET=${BUILD_TARGET}"
    echo "[full] MODEL=${MODEL}"
    echo "[full] OUT_DIR=${OUT_DIR}"

    mkdir -p "${ANDROID_PRODUCT_OUT}"

    (
        cd "${SOURCE_DIR}"
        RECOMPILE_KERNEL=1 \
            ./kernel_platform/build/android/prepare_vendor.sh sec "${TARGET_PRODUCT}"
    )

    [[ -f "${DIST_DIR}/${WLAN_BUILT_MODULE}" ]] ||
        die "built WLAN module not found: ${DIST_DIR}/${WLAN_BUILT_MODULE}"
    cp "${DIST_DIR}/${WLAN_BUILT_MODULE}" \
        "${DIST_DIR}/${WLAN_PACKAGED_MODULE}"

    echo "[full] Artifacts: ${OUT_DIR}/dist"
}

require_packaging_command() {
    require_command "$1"
}

run_privileged() {
    if (( EUID == 0 )); then
        "$@"
    elif sudo -n true 2>/dev/null; then
        sudo "$@"
    else
        env AIT_ALLOW_ROOTLESS_FUSE=1 "$@"
    fi
}

prepare_target_workspace() {
    local clang_parent="${PACKAGING_WORK_DIR}/kernel_platform/prebuilts/clang/host/linux-x86"
    local resolved_android_kernel_out
    local resolved_out_dir
    local resolved_packaging_work_dir
    local resolved_tmpdir

    [[ "${ANDROID_KERNEL_OUT}" == "${OUT_DIR}/"* ]] ||
        die "ANDROID_KERNEL_OUT must be target-scoped beneath OUT_DIR"
    [[ "${TMPDIR}" == "${PACKAGING_WORK_DIR}/"* ]] ||
        die "TMPDIR must be scoped beneath the packaging workspace"

    for path in "${PACKAGING_WORK_DIR}" "${DOWNLOAD_DIR}" "${UNPACK_DIR}"; do
        [[ ! -e "${path}" ]] ||
            die "target workspace already exists: ${path}"
    done

    mkdir -p \
        "${ANDROID_KERNEL_OUT}" \
        "${PACKAGING_PREBUILTS_DIR}" \
        "${DOWNLOAD_DIR}" \
        "${UNPACK_DIR}" \
        "${TMPDIR}" \
        "${clang_parent}"

    resolved_out_dir="$(readlink -f "${OUT_DIR}")"
    resolved_android_kernel_out="$(readlink -f "${ANDROID_KERNEL_OUT}")"
    resolved_packaging_work_dir="$(readlink -f "${PACKAGING_WORK_DIR}")"
    resolved_tmpdir="$(readlink -f "${TMPDIR}")"
    [[ "${resolved_android_kernel_out}" == "${resolved_out_dir}/"* ]] ||
        die "ANDROID_KERNEL_OUT resolves outside OUT_DIR"
    [[ "${resolved_tmpdir}" == "${resolved_packaging_work_dir}/"* ]] ||
        die "TMPDIR resolves outside the packaging workspace"

    echo "[paths] ANDROID_KERNEL_OUT=${ANDROID_KERNEL_OUT}"
    echo "[paths] TMPDIR=${TMPDIR}"

    ln -s \
        "${KERNEL_PLATFORM}/prebuilts/clang/host/linux-x86/clang-r450784e" \
        "${clang_parent}/clang-r450784e"
    ln -s \
        "${SOURCE_DIR}/prebuilts/patch_vendor_dlkm_fstab.sh" \
        "${PACKAGING_PREBUILTS_DIR}/patch_vendor_dlkm_fstab.sh"
    ln -s \
        "${SOURCE_DIR}/prebuilts/vendor_dlkm_file_contexts" \
        "${PACKAGING_PREBUILTS_DIR}/vendor_dlkm_file_contexts"
    ln -s \
        "${SOURCE_DIR}/prebuilts/vendor_dlkm_capacity.sh" \
        "${PACKAGING_PREBUILTS_DIR}/vendor_dlkm_capacity.sh"
    ln -s \
        "${SOURCE_DIR}/prebuilts/dlkm_capacity.sh" \
        "${PACKAGING_PREBUILTS_DIR}/dlkm_capacity.sh"
    ln -s \
        "${SOURCE_DIR}/prebuilts/build_dlkm.sh" \
        "${PACKAGING_PREBUILTS_DIR}/build_dlkm.sh"
    ln -s \
        "${SOURCE_DIR}/prebuilts/system_dlkm_file_contexts" \
        "${PACKAGING_PREBUILTS_DIR}/system_dlkm_file_contexts"
}

prepare_packaging_tools() {
    local prebuilts_dir="${PACKAGING_PREBUILTS_DIR}"
    local image_tools_dir
    local image_tools_commit="46a3c6a2b4413bc4570836ae0e3ab2d9de0c15e2"
    local lkm_tools_dir="${prebuilts_dir}/LKM_Tools"
    local lkm_tools_commit="a27baca7ba68348608b397ea0a4a307f84ff5e0c"

    require_packaging_command git
    require_packaging_command wget
    require_packaging_command zip

    git init -q "${lkm_tools_dir}"
    git -C "${lkm_tools_dir}" remote add origin \
        https://github.com/ravindu644/LKM_Tools.git
    git -C "${lkm_tools_dir}" fetch --depth=1 origin \
        "${lkm_tools_commit}"
    git -C "${lkm_tools_dir}" checkout -q --detach FETCH_HEAD
    git clone --depth=1 \
        https://github.com/cfig/Android_boot_image_editor.git \
        "${prebuilts_dir}/vendor_boot_unpack"
    for image_tools_dir in \
        "${prebuilts_dir}/vendor_dlkm_unpack" \
        "${prebuilts_dir}/system_dlkm_unpack"; do
        git init -q "${image_tools_dir}"
        git -C "${image_tools_dir}" remote add origin \
            https://github.com/ravindu644/Android_Image_Tools.git
        git -C "${image_tools_dir}" fetch --depth=1 origin \
            "${image_tools_commit}"
        git -C "${image_tools_dir}" checkout -q --detach FETCH_HEAD
        git -C "${image_tools_dir}" apply \
            "${SOURCE_DIR}/prebuilts/patches/android-image-tools-wait-checksum.patch"
        git -C "${image_tools_dir}" apply \
            "${SOURCE_DIR}/prebuilts/patches/android-image-tools-rootless-fuse.patch"
    done
}

write_module_metadata() {
    local modules_dir="$1"
    local metadata_dir="$2"
    local modules_dep="${modules_dir}/modules.dep"
    local modules_load="${modules_dir}/modules.load"

    [[ -f "${modules_dep}" ]] || die "modules.dep not found: ${modules_dep}"
    [[ -f "${modules_load}" ]] || die "modules.load not found: ${modules_load}"

    mkdir -p "${metadata_dir}"
    bash "${PACKAGING_PREBUILTS_DIR}/LKM_Tools/01.module_dep.sh" \
        "${modules_dep}" "${metadata_dir}"
    cp "${modules_load}" "${metadata_dir}/modules.load"
}

unpack_vendor_boot() {
    local editor_dir="${PACKAGING_PREBUILTS_DIR}/vendor_boot_unpack"
    local stock_image="${PACKAGING_WORK_DIR}/vendor_boot.stock.img"
    local modules_dir

    wget -q --show-progress \
        -O "${stock_image}" "${STOCK_VENDOR_BOOT_URL}"
    [[ -s "${stock_image}" ]] || die "vendor_boot.img download is empty"

    (
        cd "${editor_dir}"
        cp "${stock_image}" vendor_boot.img
        ./gradlew unpack
    )

    modules_dir="${editor_dir}/build/unzip_boot/root.1/lib/modules"
    write_module_metadata \
        "${modules_dir}" \
        "${PACKAGING_PREBUILTS_DIR}/LKM_Tools/vendor_boot"
}

extract_dlkm_image() {
    local partition="$1"
    local stock_url="$2"
    local image_tools_dir="${PACKAGING_PREBUILTS_DIR}/${partition}_unpack"
    local stock_image="${PACKAGING_WORK_DIR}/${partition}.stock.img"
    local output_dir="${image_tools_dir}/EXTRACTED_IMAGES/extracted_${partition}"
    local rootless_marker="${image_tools_dir}/.rootless-erofs-extract"
    local config_file="${image_tools_dir}/CONFIGS/${partition}_unpack.conf"

    case "${partition}" in
        vendor_dlkm|system_dlkm)
            ;;
        *)
            die "unsupported DLKM extraction partition: ${partition}"
            ;;
    esac

    wget -q --show-progress \
        -O "${stock_image}" "${stock_url}"
    [[ -s "${stock_image}" ]] || die "${partition}.img download is empty"

    mkdir -p "${image_tools_dir}/INPUT_IMAGES" "${image_tools_dir}/CONFIGS"
    cp "${stock_image}" \
        "${image_tools_dir}/INPUT_IMAGES/${partition}.img"
    printf '%s\n' \
        'ACTION=unpack' \
        "INPUT_IMAGE=${partition}.img" \
        "EXTRACT_DIR=extracted_${partition}" \
        > "${config_file}"

    if (( EUID == 0 )) || sudo -n true 2>/dev/null || \
        command -v erofsfuse >/dev/null 2>&1; then
        (
            cd "${image_tools_dir}"
            run_privileged ./android_image_tools.sh \
                --conf="${config_file}" --quiet
        )
        if (( EUID != 0 )) && sudo -n true 2>/dev/null; then
            sudo chown -R "$(id -u):$(id -g)" "${image_tools_dir}"
        fi
    else
        require_packaging_command fsck.erofs
        echo "[packaging] Extracting ${partition} with fsck.erofs"
        mkdir -p "${output_dir}" "${image_tools_dir}/REPACKED_IMAGES"
        fsck.erofs \
            --extract="${output_dir}" \
            --xattrs \
            --no-preserve-owner \
            --no-preserve-perms \
            "${image_tools_dir}/INPUT_IMAGES/${partition}.img"
        touch "${rootless_marker}"
    fi

    DLKM_EXTRACTED_ROOT="${output_dir}"
}

unpack_vendor_dlkm() {
    extract_dlkm_image vendor_dlkm "${STOCK_VENDOR_DLKM_URL}"
    write_module_metadata \
        "${DLKM_EXTRACTED_ROOT}/lib/modules" \
        "${PACKAGING_PREBUILTS_DIR}/LKM_Tools/vendor_dlkm"
}

find_system_module_root() {
    local modules_base="$1"
    local -a module_roots=()
    local module_root_name

    if [[ -d "${modules_base}" ]]; then
        mapfile -d '' module_roots < <(
            find "${modules_base}" -mindepth 1 -maxdepth 1 -type d -print0
        )
    fi
    (( ${#module_roots[@]} == 1 )) ||
        die "expected exactly one versioned system_dlkm module directory, found ${#module_roots[@]}"

    module_root_name="$(basename "${module_roots[0]}")"
    [[ "${module_root_name}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?[-._+[:alnum:]]*$ ]] ||
        die "invalid system_dlkm module directory: ${module_root_name}"
    printf '%s\n' "${module_roots[0]}"
}

unpack_system_dlkm() {
    local modules_dir
    local blocklist_source="${DIST_DIR}/system_dlkm.modules.blocklist"
    local blocklist_destination="${PACKAGING_PREBUILTS_DIR}/LKM_Tools/system_dlkm/modules.blocklist"

    extract_dlkm_image system_dlkm "${STOCK_SYSTEM_DLKM_URL}"
    modules_dir="$(find_system_module_root "${DLKM_EXTRACTED_ROOT}/lib/modules")"
    write_module_metadata \
        "${modules_dir}" \
        "${PACKAGING_PREBUILTS_DIR}/LKM_Tools/system_dlkm"
    rm -f -- "${blocklist_destination}"
    if [[ -s "${blocklist_source}" ]]; then
        cp -- "${blocklist_source}" "${blocklist_destination}"
    fi
}

build_vendor_boot() {
    env SCRIPT_DIR="${PACKAGING_WORK_DIR}" \
        DIST_DIR="${DIST_DIR}" \
        OUT_DIR="${OUT_DIR}" \
        "${SCRIPT_DIR}/prebuilts/build_vendor_boot.sh"
}

build_vendor_dlkm() {
    env SCRIPT_DIR="${PACKAGING_WORK_DIR}" \
        DIST_DIR="${DIST_DIR}" \
        OUT_DIR="${OUT_DIR}" \
        "${SCRIPT_DIR}/prebuilts/build_vendor_dlkm.sh"
}

build_system_dlkm() {
    env SCRIPT_DIR="${PACKAGING_WORK_DIR}" \
        DIST_DIR="${DIST_DIR}" \
        OUT_DIR="${OUT_DIR}" \
        "${SCRIPT_DIR}/prebuilts/build_system_dlkm.sh"
}

validate_collected_dlkm_capacity() {
    local partition="$1"
    local stock_image="$2"
    local rebuilt_image="$3"
    local helper="${SOURCE_DIR}/prebuilts/dlkm_capacity.sh"

    [[ -f "${helper}" ]] || die "DLKM capacity helper not found: ${helper}"
    (
        # shellcheck source=/dev/null
        source "${helper}"
        dlkm_capacity_validate \
            "${partition}" "${stock_image}" "${rebuilt_image}"
    )
}

create_flashable_zip() {
    "${SOURCE_DIR}/prebuilts/make_flashable_zip.sh" \
        "${FLASHABLE_ZIP}" \
        "${PACKAGE_DIR}" \
        "${DEVICE_DISPLAY_NAME}"
}

collect_packaged_images() {
    local boot_image="${DIST_DIR}/boot.img"
    local vendor_boot_image="${PACKAGING_WORK_DIR}/vendor_boot.img"
    local stock_vendor_dlkm_image="${PACKAGING_WORK_DIR}/vendor_dlkm.stock.img"
    local vendor_dlkm_image="${PACKAGING_WORK_DIR}/vendor_dlkm.img"
    local stock_system_dlkm_image="${PACKAGING_WORK_DIR}/system_dlkm.stock.img"
    local system_dlkm_image="${CUSTOM_SYSTEM_DLKM_IMAGE}"

    mkdir -p "${PACKAGE_DIR}"
    rm -f -- \
        "${PACKAGE_DIR}/boot.img" \
        "${PACKAGE_DIR}/vendor_boot.img" \
        "${PACKAGE_DIR}/vendor_dlkm.img" \
        "${PACKAGE_DIR}/system_dlkm.img" \
        "${FLASHABLE_ZIP}"

    [[ -f "${boot_image}" ]] || die "built boot.img not found: ${boot_image}"
    [[ -f "${vendor_boot_image}" ]] ||
        die "rebuilt vendor_boot.img not found: ${vendor_boot_image}"
    [[ -f "${stock_vendor_dlkm_image}" ]] ||
        die "stock vendor_dlkm.img not found: ${stock_vendor_dlkm_image}"
    [[ -f "${vendor_dlkm_image}" ]] ||
        die "rebuilt vendor_dlkm.img not found: ${vendor_dlkm_image}"
    [[ -f "${stock_system_dlkm_image}" ]] ||
        die "stock system_dlkm.img not found: ${stock_system_dlkm_image}"
    [[ -s "${system_dlkm_image}" ]] ||
        die "rebuilt system_dlkm.img not found or empty: ${system_dlkm_image}"
    [[ "${system_dlkm_image}" != "${DIST_DIR}/system_dlkm.img" ]] ||
        die "custom system_dlkm.img must not use the kernel DIST_DIR path"

    echo "[packaging] Validating vendor_dlkm capacity against stock image"
    validate_collected_dlkm_capacity vendor_dlkm \
        "${stock_vendor_dlkm_image}" \
        "${vendor_dlkm_image}" || return 1
    echo "[packaging] Validating system_dlkm capacity against stock image"
    validate_collected_dlkm_capacity system_dlkm \
        "${stock_system_dlkm_image}" \
        "${system_dlkm_image}" || return 1

    cp "${boot_image}" "${PACKAGE_DIR}/boot.img"
    cp "${vendor_boot_image}" "${PACKAGE_DIR}/vendor_boot.img"
    cp "${vendor_dlkm_image}" "${PACKAGE_DIR}/vendor_dlkm.img"
    cp "${system_dlkm_image}" "${PACKAGE_DIR}/system_dlkm.img"
    cp "${vendor_boot_image}" "${DIST_DIR}/vendor_boot.img"
    cp "${vendor_dlkm_image}" "${DIST_DIR}/vendor_dlkm.img"
    cp "${system_dlkm_image}" "${DIST_DIR}/system_dlkm.img"

    create_flashable_zip
}

main() {
    if [[ $# -eq 1 ]]; then
        case "$1" in
            -h|--help|help)
                usage
                return 0
                ;;
        esac
    fi

    if [[ $# -ne 2 || "$2" != "full" ]]; then
        usage >&2
        return 2
    fi
    if ! select_device_profile "$1"; then
        usage >&2
        return 2
    fi

    if [[ "${BUILD_SH_PROFILE_ONLY:-0}" == "1" ]]; then
        print_device_profile
        return 0
    fi

    record_common_state
    validate_msm_state
    prepare_target_workspace
    import_kernelsu_next
    prepare_toolchain
    build_full
    prepare_packaging_tools
    unpack_vendor_boot
    unpack_vendor_dlkm
    unpack_system_dlkm
    build_vendor_boot
    build_vendor_dlkm
    build_system_dlkm
    collect_packaged_images
}

main "$@"
