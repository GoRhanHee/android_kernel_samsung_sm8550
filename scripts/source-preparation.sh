#!/usr/bin/env bash

# Sourced by build.sh so the EXIT trap can restore every temporary source
# change after all child build scripts finish.

: "${SOURCE_DIR:?SOURCE_DIR is required}"
: "${KERNEL_PLATFORM:?KERNEL_PLATFORM is required}"
: "${PACKAGING_WORK_DIR:?PACKAGING_WORK_DIR is required}"
: "${KERNEL_MODE:?KERNEL_MODE is required}"

COMMON_FEATURE_PATCH_FILES=(
    "${SOURCE_DIR}/patches/common/ntsync/ntsync_base.patch"
    "${SOURCE_DIR}/patches/common/ntsync/ntsync_compat_android13-5.15.patch"
    "${SOURCE_DIR}/patches/common/bbrv3/0001-net-tcp-backport-BBRv3-to-android13-5.15.patch"
    "${SOURCE_DIR}/patches/common/bbg/0001-baseband-guard.patch"
    "${SOURCE_DIR}/patches/common/optimization/0001-optimized-mem-operations.patch"
    "${SOURCE_DIR}/patches/common/optimization/0002-file-struct-8bytes-align.patch"
    "${SOURCE_DIR}/patches/common/optimization/0003-reduce-cache-pressure.patch"
    "${SOURCE_DIR}/patches/common/optimization/0004-mem-opt-prefetch.patch"
    "${SOURCE_DIR}/patches/common/optimization/0005-arm64-optimize-memcmp-sm8550-5.15.patch"
    "${SOURCE_DIR}/patches/common/optimization/0006-int-sqrt.patch"
    "${SOURCE_DIR}/patches/common/optimization/0007-reduce-gc-thread-sleep-time.patch"
    "${SOURCE_DIR}/patches/common/optimization/0008-alarmtimer-wakeup-timeout-sm8550-5.15.patch"
    "${SOURCE_DIR}/patches/common/optimization/0009-add-timeout-wakelocks-globally.patch"
    "${SOURCE_DIR}/patches/common/optimization/0010-f2fs-reduce-congestion.patch"
    "${SOURCE_DIR}/patches/common/optimization/0011-reduce-freeze-timeout.patch"
    "${SOURCE_DIR}/patches/common/optimization/0012-clear-page-16bytes-align.patch"
    "${SOURCE_DIR}/patches/common/optimization/0013-cpufreq-scaling-min-freq-limit-sm8550-5.15.patch"
    "${SOURCE_DIR}/patches/common/optimization/0014-adjust-cpu-scan-order.patch"
    "${SOURCE_DIR}/patches/common/optimization/0015-avoid-extra-s2idle-wake-attempts.patch"
    "${SOURCE_DIR}/patches/common/optimization/0016-disable-cache-hot-buddy.patch"
    "${SOURCE_DIR}/patches/common/optimization/0017-f2fs-enlarge-min-fsync-blocks.patch"
    "${SOURCE_DIR}/patches/common/optimization/0018-increase-ext4-default-commit-age.patch"
    "${SOURCE_DIR}/patches/common/optimization/0019-increase-sk-mem-packets-sm8550-5.15.patch"
    "${SOURCE_DIR}/patches/common/optimization/0020-reduce-pci-pme-wakeups-sm8550-5.15.patch"
    "${SOURCE_DIR}/patches/common/optimization/0021-silence-irq-cpu-logspam-sm8550-5.15.patch"
    "${SOURCE_DIR}/patches/common/optimization/0022-silence-system-logspam.patch"
)
FAKE_CONFIG_PATCH_TARGETS=(
    "${KERNEL_PLATFORM}/common"
    "${KERNEL_PLATFORM}/msm-kernel"
)

COMMON_HEAD_BEFORE=""
COMMON_STATUS_BEFORE=""
MSM_HEAD_BEFORE=""
MSM_STATUS_BEFORE=""
MSM_DEFCONFIG_BACKUP_DIR=""
MSM_DEFCONFIG_SNAPSHOT_TAKEN=0
MSM_DEFCONFIG_FILES=()
MSM_WLAN_LINK_PREEXISTING=0
MSM_WLAN_LINK_TARGET=""
KSU_SETUP_SCRIPT=""
KSU_RESTORE_PATCH=""
KSU_IMPORT_STARTED=0
KSU_REUSE_EXISTING=0
SUSFS_KSU_PATCH_APPLIED=0
SUSFS_KERNEL_PATCH_APPLIED=0
COMMON_FEATURE_PATCHES_APPLIED=0
FAKE_CONFIG_PATCHES_APPLIED=0

die() {
    echo "error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

update_submodules() {
    require_command git
    git -C "${SOURCE_DIR}" rev-parse --show-toplevel >/dev/null 2>&1 ||
        die "source directory is not a git worktree: ${SOURCE_DIR}"

    echo "[submodule] Synchronizing configured URLs"
    git -C "${SOURCE_DIR}" submodule sync --recursive
    echo "[submodule] Initializing recorded revisions"
    git -C "${SOURCE_DIR}" submodule update --init --depth=1 --recursive --checkout
    echo "[submodule] Enabling configured branch fetches"
    git -C "${SOURCE_DIR}" submodule foreach --recursive \
        'git config --replace-all remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"'
    echo "[submodule] Updating configured branches"
    git -C "${SOURCE_DIR}" submodule update --init --remote --depth=1 --recursive --checkout
}

record_common_state() {
    local common_dir="${KERNEL_PLATFORM}/common"
    local top_level

    [[ -e "${common_dir}/.git" ]] || die "common submodule is not initialized"
    top_level="$(git -C "${common_dir}" rev-parse --show-toplevel 2>/dev/null)" ||
        die "common submodule is not initialized"
    [[ "${top_level}" -ef "${common_dir}" ]] || die "invalid common submodule root"

    COMMON_HEAD_BEFORE="$(git -C "${common_dir}" rev-parse HEAD)"
    COMMON_STATUS_BEFORE="$(git -C "${common_dir}" status --porcelain=v1 --untracked-files=all)"
    [[ -z "${COMMON_STATUS_BEFORE}" ]] || die "common submodule must be clean before the build"

    if [[ -d "${common_dir}/KernelSU-Next" || -d "${common_dir}/KernelSU" ||
          -e "${common_dir}/drivers/kernelsu" ]]; then
        [[ "${KERNEL_MODE}" != "vanilla" ]] ||
            die "vanilla mode requires a common tree without KernelSU"
        KSU_REUSE_EXISTING=1
        echo "[KernelSU] Reusing the existing integration"
    elif [[ "${KERNEL_MODE}" == "vanilla" ]]; then
        echo "[KernelSU-Next] Disabled for vanilla mode"
    else
        echo "[KernelSU-Next] A pinned temporary integration will be imported"
    fi
    trap cleanup_sources EXIT
}

validate_msm_state() {
    local msm_dir="${KERNEL_PLATFORM}/msm-kernel"
    local configured_branch tracking_ref tracking_head top_level

    [[ -e "${msm_dir}/.git" ]] || die "msm-kernel submodule is not initialized"
    top_level="$(git -C "${msm_dir}" rev-parse --show-toplevel 2>/dev/null)" ||
        die "msm-kernel submodule is not initialized"
    [[ "${top_level}" == "${msm_dir}" ]] || die "invalid msm-kernel submodule root"

    MSM_HEAD_BEFORE="$(git -C "${msm_dir}" rev-parse HEAD)"
    MSM_STATUS_BEFORE="$(git -C "${msm_dir}" status --porcelain=v1 --untracked-files=all)"
    [[ -z "${MSM_STATUS_BEFORE}" ]] || die "msm-kernel submodule must be clean before the build"

    configured_branch="$(git -C "${SOURCE_DIR}" config -f .gitmodules \
        --get submodule.kernel_platform/msm-kernel.branch 2>/dev/null || true)"
    tracking_ref="refs/remotes/origin/${configured_branch}"
    if [[ -n "${configured_branch}" ]] &&
       git -C "${msm_dir}" show-ref --verify --quiet "${tracking_ref}"; then
        tracking_head="$(git -C "${msm_dir}" rev-parse "${tracking_ref}")"
        [[ "${MSM_HEAD_BEFORE}" == "${tracking_head}" ]] ||
            die "msm-kernel HEAD does not match ${tracking_ref}"
    fi
    echo "[submodule] msm-kernel ${MSM_HEAD_BEFORE} is initialized and clean"
}

snapshot_msm_wlan_link() {
    local wlan_link="${KERNEL_PLATFORM}/msm-kernel/.wlan-qcacld"
    if [[ -L "${wlan_link}" ]]; then
        MSM_WLAN_LINK_PREEXISTING=1
        MSM_WLAN_LINK_TARGET="$(readlink -- "${wlan_link}")"
    elif [[ -e "${wlan_link}" ]]; then
        die "msm-kernel .wlan-qcacld exists but is not a symlink"
    fi
}

snapshot_msm_defconfigs() {
    local msm_dir="${KERNEL_PLATFORM}/msm-kernel"
    local relative_path backup_path

    MSM_DEFCONFIG_BACKUP_DIR="${PACKAGING_WORK_DIR}/msm-defconfigs.before"
    mkdir -p "${MSM_DEFCONFIG_BACKUP_DIR}"
    while IFS= read -r relative_path; do
        [[ -n "${relative_path}" ]] || continue
        backup_path="${MSM_DEFCONFIG_BACKUP_DIR}/${relative_path}"
        mkdir -p "$(dirname "${backup_path}")"
        cp -a -- "${msm_dir}/${relative_path}" "${backup_path}"
        MSM_DEFCONFIG_FILES+=("${relative_path}")
    done < <(git -C "${msm_dir}" ls-files -- 'arch/arm64/configs/vendor/*defconfig')
    MSM_DEFCONFIG_SNAPSHOT_TAKEN=1
}

import_kernelsu_next() {
    local common_dir="${KERNEL_PLATFORM}/common"
    local changed_file

    [[ "${KERNEL_MODE}" != "vanilla" ]] || return 0
    (( KSU_REUSE_EXISTING == 0 )) || return 0
    require_command curl

    KSU_SETUP_SCRIPT="${PACKAGING_WORK_DIR}/kernelsu-next-setup.sh"
    KSU_RESTORE_PATCH="${PACKAGING_WORK_DIR}/kernelsu-next-common.patch"
    curl -fLSs --retry 3 -o "${KSU_SETUP_SCRIPT}" "${KSU_SETUP_URL}"
    KSU_IMPORT_STARTED=1
    (cd "${common_dir}" && bash "${KSU_SETUP_SCRIPT}" "${KSU_NEXT_REF}")

    git -C "${common_dir}" diff --binary --full-index >"${KSU_RESTORE_PATCH}"
    [[ -s "${KSU_RESTORE_PATCH}" ]] || die "KernelSU setup did not modify the common kernel"
    while IFS= read -r changed_file; do
        case "${changed_file}" in
            drivers/Kconfig|drivers/Makefile) ;;
            *) die "KernelSU setup changed an unexpected file: ${changed_file}" ;;
        esac
    done < <(git -C "${common_dir}" diff --name-only)
    [[ -L "${common_dir}/drivers/kernelsu" && -d "${common_dir}/KernelSU-Next" ]] ||
        die "KernelSU setup did not create the expected integration"
}

apply_one_patch() {
    local tree="$1" patch_file="$2" fuzz="$3" label="$4"
    [[ -f "${patch_file}" ]] || die "${label} patch not found: ${patch_file}"
    echo "[${label}] Applying $(basename "${patch_file}")"
    (cd "${tree}" && patch --batch --forward --fuzz="${fuzz}" \
        --no-backup-if-mismatch --dry-run -p1 <"${patch_file}" >/dev/null) ||
        die "${label} patch does not apply: ${patch_file}"
    (cd "${tree}" && patch --batch --forward --fuzz="${fuzz}" \
        --no-backup-if-mismatch -p1 <"${patch_file}")
}

apply_susfs_patches() {
    [[ "${KERNEL_MODE}" == "susfs" ]] || return 0
    local common_dir="${KERNEL_PLATFORM}/common"
    local kernelsu_dir="${common_dir}/KernelSU-Next"
    [[ -d "${kernelsu_dir}" ]] || die "KernelSU-Next tree not found for SUSFS"
    apply_one_patch "${kernelsu_dir}" "${SUSFS_KSU_PATCH_FILE}" 0 SUSFS
    SUSFS_KSU_PATCH_APPLIED=1
    apply_one_patch "${common_dir}" "${SUSFS_KERNEL_PATCH_FILE}" 0 SUSFS
    SUSFS_KERNEL_PATCH_APPLIED=1
}

apply_common_feature_patches() {
    local patch_file
    require_command patch
    for patch_file in "${COMMON_FEATURE_PATCH_FILES[@]}"; do
        apply_one_patch "${KERNEL_PLATFORM}/common" "${patch_file}" 1 "common patches"
        COMMON_FEATURE_PATCHES_APPLIED=$((COMMON_FEATURE_PATCHES_APPLIED + 1))
    done
}

apply_fake_config_patch() {
    local kernel_dir
    for kernel_dir in "${FAKE_CONFIG_PATCH_TARGETS[@]}"; do
        apply_one_patch "${kernel_dir}" "${FAKE_CONFIG_PATCH_FILE}" 1 "fake config"
        FAKE_CONFIG_PATCHES_APPLIED=$((FAKE_CONFIG_PATCHES_APPLIED + 1))
    done
}

restore_msm_state() {
    local msm_dir="${KERNEL_PLATFORM}/msm-kernel"
    local wlan_link="${msm_dir}/.wlan-qcacld"
    local relative_path current_target
    local cleanup_status=0

    if (( MSM_DEFCONFIG_SNAPSHOT_TAKEN == 1 )); then
        for relative_path in "${MSM_DEFCONFIG_FILES[@]}"; do
            rm -f -- "${msm_dir}/${relative_path}" || cleanup_status=1
            cp -a -- "${MSM_DEFCONFIG_BACKUP_DIR}/${relative_path}" \
                "${msm_dir}/${relative_path}" || cleanup_status=1
        done
        MSM_DEFCONFIG_SNAPSHOT_TAKEN=0
    fi

    if (( MSM_WLAN_LINK_PREEXISTING == 1 )); then
        current_target="$(readlink -- "${wlan_link}" 2>/dev/null || true)"
        if [[ "${current_target}" != "${MSM_WLAN_LINK_TARGET}" ]]; then
            if [[ ! -e "${wlan_link}" || -L "${wlan_link}" ]]; then
                rm -f -- "${wlan_link}" || cleanup_status=1
                ln -s -- "${MSM_WLAN_LINK_TARGET}" "${wlan_link}" ||
                    cleanup_status=1
            else
                cleanup_status=1
            fi
        fi
    elif [[ -L "${wlan_link}" ]]; then
        rm -- "${wlan_link}" || cleanup_status=1
    elif [[ -e "${wlan_link}" ]]; then
        echo "error: build created a non-symlink .wlan-qcacld; refusing to remove it" >&2
        cleanup_status=1
    fi
    return "${cleanup_status}"
}

reverse_applied_patches() {
    local index tree
    local cleanup_status=0
    for ((index = FAKE_CONFIG_PATCHES_APPLIED - 1; index >= 0; index--)); do
        tree="${FAKE_CONFIG_PATCH_TARGETS[index]}"
        (cd "${tree}" && patch --batch --fuzz=1 --no-backup-if-mismatch \
            -R -p1 <"${FAKE_CONFIG_PATCH_FILE}") || cleanup_status=1
    done
    FAKE_CONFIG_PATCHES_APPLIED=0

    if (( SUSFS_KERNEL_PATCH_APPLIED == 1 )); then
        (cd "${KERNEL_PLATFORM}/common" && patch --batch --fuzz=0 \
            --no-backup-if-mismatch -R -p1 <"${SUSFS_KERNEL_PATCH_FILE}") ||
            cleanup_status=1
        SUSFS_KERNEL_PATCH_APPLIED=0
    fi
    if (( SUSFS_KSU_PATCH_APPLIED == 1 )); then
        (cd "${KERNEL_PLATFORM}/common/KernelSU-Next" && patch --batch --fuzz=0 \
            --no-backup-if-mismatch -R -p1 <"${SUSFS_KSU_PATCH_FILE}") ||
            cleanup_status=1
        SUSFS_KSU_PATCH_APPLIED=0
    fi

    for ((index = COMMON_FEATURE_PATCHES_APPLIED - 1; index >= 0; index--)); do
        (cd "${KERNEL_PLATFORM}/common" && patch --batch --fuzz=1 \
            --no-backup-if-mismatch -R -p1 <"${COMMON_FEATURE_PATCH_FILES[index]}") ||
            cleanup_status=1
    done
    COMMON_FEATURE_PATCHES_APPLIED=0
    return "${cleanup_status}"
}

remove_temporary_kernelsu() {
    local common_dir="${KERNEL_PLATFORM}/common"
    local kernelsu_dir="${common_dir}/KernelSU-Next"
    local kernelsu_link="${common_dir}/drivers/kernelsu"
    local fallback_patch="${PACKAGING_WORK_DIR}/kernelsu-next-common-fallback.patch"
    local cleanup_status=0

    (( KSU_IMPORT_STARTED == 1 )) || return 0
    if [[ -s "${KSU_RESTORE_PATCH}" ]]; then
        git -C "${common_dir}" apply --reverse "${KSU_RESTORE_PATCH}" ||
            cleanup_status=1
    elif ! git -C "${common_dir}" diff --quiet; then
        git -C "${common_dir}" diff --binary --full-index >"${fallback_patch}"
        git -C "${common_dir}" apply --reverse "${fallback_patch}" ||
            cleanup_status=1
    fi
    if [[ ! -e "${kernelsu_link}" || -L "${kernelsu_link}" ]]; then
        rm -f -- "${kernelsu_link}" || cleanup_status=1
    else
        cleanup_status=1
    fi
    if [[ -L "${kernelsu_dir}" ]]; then
        echo "error: refusing to recursively remove KernelSU symlink" >&2
        cleanup_status=1
    elif [[ -d "${kernelsu_dir}" ]]; then
        rm -rf -- "${kernelsu_dir}" || cleanup_status=1
    elif [[ -e "${kernelsu_dir}" ]]; then
        echo "error: refusing to remove unexpected KernelSU path" >&2
        cleanup_status=1
    fi
    KSU_IMPORT_STARTED=0
    return "${cleanup_status}"
}

verify_source_state() {
    local current_head current_status
    if [[ -n "${COMMON_HEAD_BEFORE}" ]]; then
        current_head="$(git -C "${KERNEL_PLATFORM}/common" rev-parse HEAD)"
        current_status="$(git -C "${KERNEL_PLATFORM}/common" status --porcelain=v1 --untracked-files=all)"
        [[ "${current_head}" == "${COMMON_HEAD_BEFORE}" &&
           "${current_status}" == "${COMMON_STATUS_BEFORE}" ]] || return 1
    fi
    if [[ -n "${MSM_HEAD_BEFORE}" ]]; then
        current_head="$(git -C "${KERNEL_PLATFORM}/msm-kernel" rev-parse HEAD)"
        current_status="$(git -C "${KERNEL_PLATFORM}/msm-kernel" status --porcelain=v1 --untracked-files=all)"
        [[ "${current_head}" == "${MSM_HEAD_BEFORE}" &&
           "${current_status}" == "${MSM_STATUS_BEFORE}" ]] || return 1
    fi
}

cleanup_sources() {
    local build_status=$?
    local cleanup_status=0
    trap - EXIT
    reverse_applied_patches || cleanup_status=1
    remove_temporary_kernelsu || cleanup_status=1
    restore_msm_state || cleanup_status=1
    verify_source_state || cleanup_status=1
    if (( cleanup_status != 0 )); then
        echo "error: failed to restore build-time kernel source changes" >&2
        return 1
    fi
    return "${build_status}"
}
