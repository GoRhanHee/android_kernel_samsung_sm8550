#!/usr/bin/env bash

set -Eeuo pipefail

export SCRIPT_NAME="$(basename "$0")"
export SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPTS_DIR="${SOURCE_DIR}/scripts"
export KERNEL_PLATFORM="${SOURCE_DIR}/kernel_platform"

export TOOLCHAIN_VERSION="r614150"
export TOOLCHAIN_URL="https://github.com/GoRhanHee/samsung_sm8550_toolchain/releases/download/clang23-ndk26d/toolchain-clang23-ndk26d.tar.xz"
export CLANG_TOOLCHAIN_DIR="${KERNEL_PLATFORM}/prebuilts/clang/host/linux-x86/clang-${TOOLCHAIN_VERSION}"
export CLANG_BIN="${CLANG_TOOLCHAIN_DIR}/bin/clang"
export KSU_NEXT_REF="1a879d6a866f80b1fa1c1009a2ffa747873cbb5e"
export KSU_SETUP_URL="https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/${KSU_NEXT_REF}/kernel/setup.sh"

export SUSFS_KSU_PATCH_FILE="${SOURCE_DIR}/patches/susfs/0001-kernelsu-next-3.4.0-susfs-2.3.0.patch"
export SUSFS_KERNEL_PATCH_FILE="${SOURCE_DIR}/patches/susfs/0002-susfs-2.3.0-android13-5.15.patch"
export FAKE_CONFIG_PATCH_FILE="${SOURCE_DIR}/patches/common/fake_config.patch"
export BASE_DEFCONFIG_FILE="${SOURCE_DIR}/custom_defconfigs/gorhanhee_defconfig"
export KSU_DEFCONFIG_FILE="${SOURCE_DIR}/custom_defconfigs/ksu_defconfig"
export SUSFS_DEFCONFIG_FILE="${SOURCE_DIR}/custom_defconfigs/susfs_defconfig"

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [vanilla|ksun|susfs]

  vanilla  Build without KernelSU-Next or SUSFS (default)
  ksun     Build with KernelSU-Next 3.4.0 (${KSU_NEXT_REF})
  susfs    Build with KernelSU-Next 3.4.0 and SUSFS 2.3.0
EOF
}

case "${1:-vanilla}" in
    -h|--help|help)
        usage
        exit 0
        ;;
    vanilla|plain|base)
        export KERNEL_MODE="vanilla"
        ;;
    ksun|ksu)
        export KERNEL_MODE="ksun"
        ;;
    susfs|ksu-susfs)
        export KERNEL_MODE="susfs"
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
(( $# <= 1 )) || { usage >&2; exit 2; }

# Universal build profile.  Child scripts receive configuration only through
# exported variables, so every phase can also be invoked independently.
export BUILD_TARGET="universal"
export MODEL="universal"
export PROJECT_NAME="universal"
export SEC_PROJECT_CONFIG="universal"
export REGION="universal"
export CARRIER="universal"
export CHIPSET_NAME="kalama"
export TARGET_PRODUCT="gki"
export TARGET_BOARD_PLATFORM="gki"
export TARGET_BUILD_VARIANT="user"
export ANDROID_BUILD_TOP="${SOURCE_DIR}"

export OUTPUT_BASE="${SOURCE_DIR}/out"
export OUT_DIR="${OUTPUT_BASE}/${MODEL}/msm-${CHIPSET_NAME}-${CHIPSET_NAME}-${TARGET_PRODUCT}-${KERNEL_MODE}"
export DIST_DIR="${OUT_DIR}/dist"
export GKI_OUT_DIR="${OUT_DIR}/gki_kernel"
export GKI_DIST_DIR="${GKI_OUT_DIR}/dist"
export PACKAGE_DIR="${OUT_DIR}/packaged"
export ANDROID_PRODUCT_OUT="${OUTPUT_BASE}/${MODEL}/${KERNEL_MODE}/target/product/${MODEL}"
export ANDROID_KERNEL_OUT="${OUT_DIR}/android-kernel-out"
export PACKAGING_WORK_DIR="${OUT_DIR}/tmp/run-${BASHPID}"
export DOWNLOAD_DIR="${OUT_DIR}/downloads/run-${BASHPID}"
export TMPDIR="${PACKAGING_WORK_DIR}/process-tmp"
export ANYKERNEL_PACKAGE="${PACKAGE_DIR}/GoRhanHee_Kernel-${CHIPSET_NAME}-${MODEL}-${KERNEL_MODE}-AnyKernel3.zip"

export GKI_CUSTOM_DEFCONFIG="${BASE_DEFCONFIG_FILE}"
export GKI_CUSTOM_DEFCONFIG_FRAGMENTS=""
if [[ "${KERNEL_MODE}" == "ksun" ]]; then
    export GKI_CUSTOM_DEFCONFIG_FRAGMENTS="${KSU_DEFCONFIG_FILE}"
elif [[ "${KERNEL_MODE}" == "susfs" ]]; then
    export GKI_CUSTOM_DEFCONFIG_FRAGMENTS="${KSU_DEFCONFIG_FILE} ${SUSFS_DEFCONFIG_FILE}"
fi

# Kernel build settings shared by the standalone common and MSM phases.
export JOBS="$(nproc)"
export SKIP_MRPROPER="1"
export LTO="thin"
export HERMETIC_TOOLCHAIN="0"
export KMI_SYMBOL_LIST_STRICT_MODE="0"
export TRIM_NONLISTED_KMI="0"
export CONFIG_FAKE_DISABLE="CONFIG_BBG CONFIG_NTSYNC CONFIG_TCP_CONG_BBR3 CONFIG_IP6_NF_NAT"
export ABI_DEFINITION=""
export BUILD_BOOT_IMG="1"
export SKIP_VENDOR_BOOT="1"
export MKBOOTIMG_PATH="${KERNEL_PLATFORM}/tools/mkbootimg/mkbootimg.py"
export KERNEL_BINARY="Image"
export BOOT_IMAGE_HEADER_VERSION="4"
export AVB_SIGN_BOOT_IMG="1"
export AVB_BOOT_PARTITION_SIZE="100663296"
export AVB_BOOT_KEY="${KERNEL_PLATFORM}/tools/mkbootimg/gki/testdata/testkey_rsa4096.pem"
export AVB_BOOT_ALGORITHM="SHA256_RSA4096"
export AVB_BOOT_PARTITION_NAME="boot"
export MKBOOTIMG_EXTRA_ARGS="--os_version 13.0.0 --os_patch_level 2099-12-31 --pagesize 4096"
export MERGE_CONFIG="${KERNEL_PLATFORM}/common/scripts/kconfig/merge_config.sh"
export GKI_BUILD_CONFIG_FRAGMENT="${SOURCE_DIR}/prebuilts/gki_toolchain.config"

export TZ="Asia/Seoul"
export LC_ALL="C"
export KBUILD_BUILD_USER="GoRhanHee"
export KBUILD_BUILD_HOST="SM8550-Kernel"
export KBUILD_BUILD_TIMESTAMP="$(date)"
export KBUILD_BUILD_VERSION="1"

export MODNAME="audio_dlkm"
export KBUILD_EXT_MODULES="../vendor/qcom/opensource/mm-drivers/msm_ext_display
../vendor/qcom/opensource/mm-drivers/sync_fence
../vendor/qcom/opensource/mm-drivers/hw_fence
../vendor/qcom/opensource/mmrm-driver
../vendor/qcom/opensource/securemsm-kernel
../vendor/qcom/opensource/display-drivers/msm
../vendor/qcom/opensource/audio-kernel
../vendor/qcom/opensource/camera-kernel
../vendor/qcom/opensource/video-driver
../vendor/qcom/opensource/graphics-kernel
../vendor/qcom/opensource/dataipa/drivers/platform/msm
../vendor/qcom/opensource/datarmnet/core
../vendor/qcom/opensource/datarmnet-ext/aps
../vendor/qcom/opensource/datarmnet-ext/offload
../vendor/qcom/opensource/datarmnet-ext/shs
../vendor/qcom/opensource/datarmnet-ext/sch
../vendor/qcom/opensource/datarmnet-ext/perf
../vendor/qcom/opensource/datarmnet-ext/perf_tether
../vendor/qcom/opensource/datarmnet-ext/wlan
../vendor/qcom/opensource/eva-kernel
../vendor/qcom/opensource/wlan/platform
../vendor/qcom/opensource/bt-kernel
../vendor/qcom/opensource/wlan/qcacld-3.0/.qca6490
../vendor/qcom/opensource/wlan/qcacld-3.0/.kiwi_v2"
export KBUILD_EXTRA_SYMBOLS="${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/mmrm-driver/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/mm-drivers/hw_fence/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/mm-drivers/sync_fence/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/mm-drivers/msm_ext_display/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/securemsm-kernel/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/graphics-kernel/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/datarmnet/core/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/wlan/qcacld-3.0/.qca6490/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/wlan/qcacld-3.0/.kiwi_v2/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/wlan/platform/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/camera-kernel/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/eva-kernel/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/video-driver/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/display-drivers/msm/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/datarmnet-ext/aps/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/datarmnet-ext/wlan/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/datarmnet-ext/shs/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/datarmnet-ext/perf_tether/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/datarmnet-ext/perf/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/datarmnet-ext/sch/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/datarmnet-ext/offload/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/bt-kernel/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/dataipa/drivers/platform/msm/Module.symvers
${OUTPUT_BASE}/${MODEL}/vendor/qcom/opensource/audio-kernel/Module.symvers"

# Source preparation is sourced so its EXIT trap can restore temporary patches.
source "${SCRIPTS_DIR}/source_preparation.sh"

"${SCRIPTS_DIR}/prepare_build.sh"
update_submodules
record_common_state
validate_msm_state
snapshot_msm_wlan_link
snapshot_msm_defconfigs
import_kernelsu_next
apply_susfs_patches
apply_common_feature_patches
apply_fake_config_patch
"${SCRIPTS_DIR}/prepare_toolchain.sh"

"${SCRIPTS_DIR}/build_common.sh"
"${SCRIPTS_DIR}/build_msm.sh"
"${SCRIPTS_DIR}/build_vendor_boot.sh"
"${SCRIPTS_DIR}/build_dlkm.sh"
"${SCRIPTS_DIR}/build_anykernel3.sh"

echo "[done] ${ANYKERNEL_PACKAGE}"
