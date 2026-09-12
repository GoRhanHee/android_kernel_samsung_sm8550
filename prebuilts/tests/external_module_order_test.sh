#!/bin/bash
# Exercise the real staging/filtering/trimming code. Fake .ko contents only
# require depmod to be stubbed; no module order operations are mocked.
set -eo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
source "${BUILD_UTILS_UNDER_TEST:-$repo_root/kernel_platform/build/build_utils.sh}"
run_depmod() { :; }
fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT
export ROOT_DIR="$fixture_root"
export DO_NOT_STRIP_MODULES="" TRIM_UNUSED_MODULES=1

run_case() (
    local variant="$1" stage="$fixture_root/$1/src/lib/modules/test-release"
    export EXT_MODULES='../vendor/secure normal'
    export KBUILD_EXT_MODULES="$EXT_MODULES" EXT_MODULES_MAKEFILE=""
    mkdir -p "$stage/kernel" "$stage/extra/../vendor/secure" "$stage/extra/normal"
    printf 'core contents\n' > "$stage/kernel/core.ko"
    printf 'secure contents including signature fixture\n' > "$stage/vendor/secure/smcinvoke_dlkm.ko"
    printf 'second contents\n' > "$stage/vendor/secure/tz_log_dlkm.ko"
    printf 'normal contents\n' > "$stage/extra/normal/normal.ko"
    printf 'excluded contents\n' > "$stage/vendor/secure/unused.ko"
    printf 'kernel/core.ko\n' > "$stage/modules.order"
    touch "$stage/modules.builtin"
    printf 'core.ko\nsmcinvoke_dlkm.ko\ntz_log_dlkm.ko\nnormal.ko\n' > "$fixture_root/$variant/requested"
    if [[ "$variant" != legacy ]]; then
        printf 'extra/../vendor/secure/smcinvoke_dlkm.ko\nextra/../vendor/secure/tz_log_dlkm.ko\nextra/../vendor/secure/unused.ko\n' > "$stage/vendor/secure/modules.order.fixture"
        printf 'extra/normal/normal.ko\n' > "$stage/extra/normal/modules.order.fixture"
    fi
    if [[ "$variant" == missing-record ]]; then
        rm "$stage/extra/normal/modules.order.fixture"
        if (create_modules_staging "$fixture_root/$variant/requested" "$fixture_root/$variant/src" "$fixture_root/$variant/dest" ""); then
            echo 'FAIL: missing configured module order was accepted' >&2
            exit 1
        fi
        exit 0
    fi
    create_modules_staging "$fixture_root/$variant/requested" "$fixture_root/$variant/src" "$fixture_root/$variant/dest" ""
    local dest="$fixture_root/$variant/dest/lib/modules/test-release"
    if [[ "$variant" == recorded ]]; then
        printf 'kernel/core.ko\nvendor/secure/smcinvoke_dlkm.ko\nvendor/secure/tz_log_dlkm.ko\nextra/normal/normal.ko\n' > "$fixture_root/$variant/expected"
    else
        printf 'kernel/core.ko\nextra/normal/normal.ko\nvendor/secure/smcinvoke_dlkm.ko\nvendor/secure/tz_log_dlkm.ko\n' > "$fixture_root/$variant/expected"
    fi
    cmp "$fixture_root/$variant/expected" "$dest/modules.load"
    for module in kernel/core.ko vendor/secure/smcinvoke_dlkm.ko vendor/secure/tz_log_dlkm.ko extra/normal/normal.ko; do
        cmp "$stage/$module" "$dest/$module"
    done
    test ! -e "$dest/vendor/secure/unused.ko"
)
for variant in recorded legacy missing-record; do
    run_case "$variant"
done
echo 'PASS: external module order, parent paths, requested filtering, trimming, unchanged module bytes, legacy fallback, and missing-record rejection'
