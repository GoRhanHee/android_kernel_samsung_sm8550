#!/usr/bin/env bash

set -Eeuo pipefail

: "${CLANG_BIN:?CLANG_BIN is required}"
: "${DOWNLOAD_DIR:?DOWNLOAD_DIR is required}"
: "${KERNEL_PLATFORM:?KERNEL_PLATFORM is required}"
: "${TOOLCHAIN_URL:?TOOLCHAIN_URL is required}"

if [[ -x "${CLANG_BIN}" ]]; then
    echo "[toolchain] Using ${CLANG_BIN}"
    exit 0
fi

for command_name in wget tar; do
    command -v "${command_name}" >/dev/null 2>&1 || {
        echo "error: required command not found: ${command_name}" >&2
        exit 1
    }
done

mkdir -p "${DOWNLOAD_DIR}"
archive="$(mktemp "${DOWNLOAD_DIR}/sm8550-toolchain.XXXXXX.tar.xz")"
trap 'rm -f -- "${archive}"' EXIT

echo "[toolchain] Downloading ${TOOLCHAIN_URL}"
wget -q --show-progress --progress=dot:giga -O "${archive}" "${TOOLCHAIN_URL}"
echo "[toolchain] Extracting prebuilts into ${KERNEL_PLATFORM}"
tar -xf "${archive}" -C "${KERNEL_PLATFORM}" --strip-components=1 toolchain/prebuilts
[[ -x "${CLANG_BIN}" ]] || {
    echo "error: clang-${TOOLCHAIN_VERSION} was not found after extraction" >&2
    exit 1
}
