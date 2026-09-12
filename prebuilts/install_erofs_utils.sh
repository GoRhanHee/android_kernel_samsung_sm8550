#!/usr/bin/env bash

set -Eeuo pipefail

readonly EROFS_VERSION="1.8.10"
readonly EROFS_COMMIT="51b5939b5f783221310d25146e6a2019ba8129b6"

(( $# == 1 )) || { echo "usage: $0 <installation directory>" >&2; exit 1; }
mkdir -p "$1"
INSTALL_DIR="$(cd "$1" && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sm8550-erofs-utils.XXXXXX")"
readonly INSTALL_DIR WORK_DIR
trap 'rm -rf -- "${WORK_DIR}"' EXIT

git clone --depth=1 --branch "v${EROFS_VERSION}" \
    https://github.com/erofs/erofs-utils.git "${WORK_DIR}/source"
[[ "$(git -C "${WORK_DIR}/source" rev-parse HEAD)" == "${EROFS_COMMIT}" ]] || {
    echo "error: erofs-utils source does not match the pinned commit" >&2
    exit 1
}

cd "${WORK_DIR}/source"
./autogen.sh
./configure --prefix="${INSTALL_DIR}" \
    --enable-lz4 --with-selinux --with-uuid \
    --disable-fuse --disable-lzma --without-zlib \
    --without-libdeflate --without-libzstd
make -j"$(nproc)"
make install

echo "[packaging] Installed erofs-utils ${EROFS_VERSION} in ${INSTALL_DIR}"
