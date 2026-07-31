#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_DIR="${SOURCE_DIR:-${SCRIPT_DIR}}"
readonly KERNEL_PLATFORM="${SOURCE_DIR}/kernel_platform"
readonly TOOLCHAIN_URL="${TOOLCHAIN_URL:-https://github.com/GoRhanHee/samsung_sm8550_toolchain/releases/download/toolchain/toolchain.tar.xz}"
readonly CLANG_BIN="${KERNEL_PLATFORM}/prebuilts/clang/host/linux-x86/clang-r450784e/bin/clang"
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
STOCK_KERNEL_URL=""
STOCK_VENDOR_DLKM_URL=""
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
TMPDIR=""
COMMON_HEAD_BEFORE=""
COMMON_STATUS_BEFORE=""

select_wlan_profile() {
    local project_config="${KERNEL_PLATFORM}/msm-kernel/arch/arm64/configs/vendor/${SEC_PROJECT_CONFIG}_project.config"

    [[ -f "${project_config}" ]] ||
        die "project config not found: ${project_config}"

    WLAN_PROFILE="kiwi_v2"
    if grep -Fxq "CONFIG_SEC_Q5Q_PROJECT=y" "${project_config}"; then
        WLAN_PROFILE="qca6490"
    fi

    WLAN_EXT_MODULE="../vendor/qcom/opensource/wlan/qcacld-3.0/.${WLAN_PROFILE}"
    WLAN_BUILT_MODULE="${WLAN_PROFILE}.ko"
    WLAN_PACKAGED_MODULE="qca_cld3_${WLAN_PROFILE}.ko"
}

usage() {
    cat <<EOF
Usage:
  ${SCRIPT_NAME} dm3q full
  ${SCRIPT_NAME} q5q full
  ${SCRIPT_NAME} -h
  ${SCRIPT_NAME} --help
  ${SCRIPT_NAME} help

Devices:
  dm3q  Samsung Galaxy S23 Ultra (SM-S918N)
  q5q   Samsung Galaxy Z Fold5 (SM-F946N)

Examples:
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
        dm3q)
            BUILD_TARGET="dm3q_kor_singlex"
            MODEL="dm3q"
            DEVICE_DISPLAY_NAME="Galaxy S23 Ultra"
            STOCK_KERNEL_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/S918NKSS8FZF1_KOO_OKR/S918NKSS8FZF1_kernel.tar"
            STOCK_VENDOR_DLKM_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/S918NKSS8FZF1_KOO_OKR/S918NKSS8FZF1_vendor_dlkm.zip"
            ;;
        q5q)
            BUILD_TARGET="q5q_kor_singlex"
            MODEL="q5q"
            DEVICE_DISPLAY_NAME="Galaxy Z Fold5"
            STOCK_KERNEL_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/F946NKSS6GZF2_KOO_OKR/F946NKSS6GZF2_kernel.tar"
            STOCK_VENDOR_DLKM_URL="https://github.com/GoRhanHee/Firmware_Samsung/releases/download/F946NKSS6GZF2_KOO_OKR/F946NKSS6GZF2_vendor_dlkm.zip"
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
    TMPDIR="${PACKAGING_WORK_DIR}/process-tmp"

    export BUILD_TARGET MODEL DEVICE_DISPLAY_NAME PROJECT_NAME REGION CARRIER
    export CHIPSET_NAME TARGET_PRODUCT TARGET_BOARD_PLATFORM
    export STOCK_KERNEL_URL STOCK_VENDOR_DLKM_URL SEC_PROJECT_CONFIG
    export WLAN_PROFILE WLAN_EXT_MODULE WLAN_BUILT_MODULE WLAN_PACKAGED_MODULE
    export ANDROID_BUILD_TOP ANDROID_PRODUCT_OUT ANDROID_KERNEL_OUT
    export OUT_DIR DIST_DIR TMPDIR
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
        "STOCK_KERNEL_URL=${STOCK_KERNEL_URL}" \
        "STOCK_VENDOR_DLKM_URL=${STOCK_VENDOR_DLKM_URL}" \
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
        echo "[KernelSU] Reusing the checked-in integration"
    else
        echo "[KernelSU] No checked-in integration; leaving common unchanged"
    fi

    trap verify_common_unchanged EXIT
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
}

prepare_packaging_tools() {
    local prebuilts_dir="${PACKAGING_PREBUILTS_DIR}"
    local image_tools_dir="${prebuilts_dir}/vendor_dlkm_unpack"
    local image_tools_commit="46a3c6a2b4413bc4570836ae0e3ab2d9de0c15e2"

    require_packaging_command git
    require_packaging_command wget
    require_packaging_command tar
    require_packaging_command lz4
    require_packaging_command unzip
    require_packaging_command zip

    git clone --depth=1 \
        https://github.com/ravindu644/LKM_Tools.git \
        "${prebuilts_dir}/LKM_Tools"
    git clone --depth=1 \
        https://github.com/cfig/Android_boot_image_editor.git \
        "${prebuilts_dir}/vendor_boot_unpack"
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
    local vboot_tar="${DOWNLOAD_DIR}/stock-kernel.tar"
    local extract_dir="${UNPACK_DIR}/vendor-boot"
    local editor_dir="${PACKAGING_PREBUILTS_DIR}/vendor_boot_unpack"
    local stock_image="${PACKAGING_WORK_DIR}/vendor_boot.stock.img"
    local vendor_boot_lz4
    local modules_dir

    wget -q --show-progress \
        -O "${vboot_tar}" "${STOCK_KERNEL_URL}"
    mkdir -p "${extract_dir}"
    tar -xf "${vboot_tar}" -C "${extract_dir}"

    vendor_boot_lz4="$({ find "${extract_dir}" -type f -name 'vendor_boot.img.lz4' -print -quit; })"
    [[ -n "${vendor_boot_lz4}" ]] || die "vendor_boot.img.lz4 not found"

    lz4 -d -f \
        "${vendor_boot_lz4}" \
        "${stock_image}"

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

unpack_vendor_dlkm() {
    local vdlkm_zip="${DOWNLOAD_DIR}/stock-vendor-dlkm.zip"
    local extract_dir="${UNPACK_DIR}/vendor-dlkm"
    local image_tools_dir="${PACKAGING_PREBUILTS_DIR}/vendor_dlkm_unpack"
    local vdlkm_img
    local modules_dir
    local output_dir="${image_tools_dir}/EXTRACTED_IMAGES/extracted_vendor_dlkm"
    local rootless_marker="${image_tools_dir}/.rootless-erofs-extract"
    local config_file="${image_tools_dir}/CONFIGS/vendor_dlkm_unpack.conf"

    wget -q --show-progress \
        -O "${vdlkm_zip}" "${STOCK_VENDOR_DLKM_URL}"
    mkdir -p "${extract_dir}"
    unzip -q -o "${vdlkm_zip}" -d "${extract_dir}"

    vdlkm_img="$({ find "${extract_dir}" -type f -name 'vendor_dlkm.img' -print -quit; })"
    [[ -n "${vdlkm_img}" ]] || die "vendor_dlkm.img not found in vendor_dlkm archive"

    mkdir -p "${image_tools_dir}/INPUT_IMAGES" "${image_tools_dir}/CONFIGS"
    cp "${vdlkm_img}" \
        "${image_tools_dir}/INPUT_IMAGES/vendor_dlkm.img"
    printf '%s\n' \
        'ACTION=unpack' \
        'INPUT_IMAGE=vendor_dlkm.img' \
        'EXTRACT_DIR=extracted_vendor_dlkm' \
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
        echo "[packaging] Extracting vendor_dlkm with fsck.erofs"
        mkdir -p "${output_dir}" "${image_tools_dir}/REPACKED_IMAGES"
        fsck.erofs \
            --extract="${output_dir}" \
            --xattrs \
            --no-preserve-owner \
            --no-preserve-perms \
            "${image_tools_dir}/INPUT_IMAGES/vendor_dlkm.img"
        touch "${rootless_marker}"
    fi

    modules_dir="${output_dir}/lib/modules"
    write_module_metadata \
        "${modules_dir}" \
        "${PACKAGING_PREBUILTS_DIR}/LKM_Tools/vendor_dlkm"
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

collect_packaged_images() {
    local boot_image="${DIST_DIR}/boot.img"
    local vendor_boot_image="${PACKAGING_WORK_DIR}/vendor_boot.img"
    local vendor_dlkm_image="${PACKAGING_WORK_DIR}/vendor_dlkm.img"

    [[ -f "${boot_image}" ]] || die "built boot.img not found: ${boot_image}"
    [[ -f "${vendor_boot_image}" ]] ||
        die "rebuilt vendor_boot.img not found: ${vendor_boot_image}"
    [[ -f "${vendor_dlkm_image}" ]] ||
        die "rebuilt vendor_dlkm.img not found: ${vendor_dlkm_image}"

    mkdir -p "${PACKAGE_DIR}"
    cp "${boot_image}" "${PACKAGE_DIR}/boot.img"
    cp "${vendor_boot_image}" "${PACKAGE_DIR}/vendor_boot.img"
    cp "${vendor_dlkm_image}" "${PACKAGE_DIR}/vendor_dlkm.img"
    cp "${vendor_boot_image}" "${DIST_DIR}/vendor_boot.img"
    cp "${vendor_dlkm_image}" "${DIST_DIR}/vendor_dlkm.img"

    "${SOURCE_DIR}/prebuilts/make_flashable_zip.sh" \
        "${FLASHABLE_ZIP}" \
        "${PACKAGE_DIR}" \
        "${DEVICE_DISPLAY_NAME}"
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
    prepare_toolchain
    build_full
    prepare_packaging_tools
    unpack_vendor_boot
    unpack_vendor_dlkm
    build_vendor_boot
    build_vendor_dlkm
    collect_packaged_images
}

main "$@"
