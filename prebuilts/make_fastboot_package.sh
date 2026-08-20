#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMPLATE_DIR="${SCRIPT_DIR}/fastboot"
OUTPUT_ZIP=""
STAGE_DIR=""

usage() {
    cat <<EOF
Usage:
  ${SCRIPT_NAME} OUTPUT_ZIP IMAGE_DIR

IMAGE_DIR must contain:
  boot.img
  vendor_boot.img
  vendor_dlkm.img
  system_dlkm.img

Example:
  ${SCRIPT_NAME} out/GoRhanHee_Kernel-kalama-dm3q-fastboot.zip \\
    out/msm-kalama-kalama-gki/packaged
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "required command not found: $1"
}

cleanup() {
    local exit_status=$?

    if (( exit_status != 0 )) && [[ -n "${OUTPUT_ZIP}" ]]; then
        rm -f -- "${OUTPUT_ZIP}" || true
    fi
    if [[ -n "${STAGE_DIR}" && -d "${STAGE_DIR}" ]]; then
        rm -rf -- "${STAGE_DIR}" || true
    fi

    return "${exit_status}"
}

main() {
    [[ $# -eq 2 ]] || {
        usage >&2
        exit 2
    }

    local output_zip="$1"
    local image_dir="$2"
    local output_dir
    local stage_dir
    local image

    if [[ "${output_zip}" != /* ]]; then
        output_zip="${PWD}/${output_zip}"
    fi
    if [[ "${image_dir}" != /* ]]; then
        image_dir="${PWD}/${image_dir}"
    fi
    OUTPUT_ZIP="${output_zip}"
    trap cleanup EXIT

    require_command zip

    [[ -d "${TEMPLATE_DIR}" ]] ||
        die "fastboot template not found: ${TEMPLATE_DIR}"
    [[ -d "${image_dir}" ]] ||
        die "image directory not found: ${image_dir}"

    output_dir="$(dirname "${output_zip}")"
    mkdir -p "${output_dir}"

    STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sm8550-fastboot.XXXXXX")"
    stage_dir="${STAGE_DIR}"

    for image in boot.img vendor_boot.img vendor_dlkm.img system_dlkm.img; do
        [[ -s "${image_dir}/${image}" ]] ||
            die "required image is missing or empty: ${image_dir}/${image}"
        cp "${image_dir}/${image}" "${stage_dir}/${image}"
        chmod 0644 "${stage_dir}/${image}"
    done

    for script in flash_windows.bat flash_macos.sh flash_linux.sh; do
        [[ -f "${TEMPLATE_DIR}/${script}" ]] ||
            die "fastboot installer script not found: ${TEMPLATE_DIR}/${script}"
        cp "${TEMPLATE_DIR}/${script}" "${stage_dir}/${script}"
    done
    chmod 0755 "${stage_dir}/flash_macos.sh" "${stage_dir}/flash_linux.sh"

    (
        cd "${stage_dir}"
        zip -r9 -q "${output_zip}" \
            boot.img \
            vendor_boot.img \
            vendor_dlkm.img \
            system_dlkm.img \
            flash_windows.bat \
            flash_macos.sh \
            flash_linux.sh
    )

    echo "Created ${output_zip}"
}

main "$@"
