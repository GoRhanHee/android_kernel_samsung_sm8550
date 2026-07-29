#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PATCHER="${REPO_ROOT}/prebuilts/patch_vendor_dlkm_fstab.sh"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

cat > "${WORK_DIR}/fstab.qcom" <<'EOF'
system	/system	erofs	ro	avb=vbmeta_system,wait,logical,first_stage_mount,avb_keys=/avb/q-gsi.avbpubkey
vendor	/vendor	erofs	ro	avb,wait,logical,first_stage_mount
vendor_dlkm	/vendor_dlkm	erofs	ro	avb,wait,logical,first_stage_mount
system_dlkm	/system_dlkm	erofs	ro	avb,wait,logical,first_stage_mount
/dev/block/by-name/prism	/prism	ext4	ro	avb,nofail,first_stage_mount
EOF
touch -d "@1234567890" "${WORK_DIR}/fstab.qcom"

"${PATCHER}" "${WORK_DIR}/fstab.qcom"

cat > "${WORK_DIR}/expected" <<'EOF'
system	/system	erofs	ro	avb=vbmeta_system,wait,logical,first_stage_mount,avb_keys=/avb/q-gsi.avbpubkey
vendor	/vendor	erofs	ro	avb,wait,logical,first_stage_mount
vendor_dlkm	/vendor_dlkm	erofs	ro	wait,logical,first_stage_mount
system_dlkm	/system_dlkm	erofs	ro	avb,wait,logical,first_stage_mount
/dev/block/by-name/prism	/prism	ext4	ro	avb,nofail,first_stage_mount
EOF

diff -u "${WORK_DIR}/expected" "${WORK_DIR}/fstab.qcom"
[[ "$(stat -c %Y "${WORK_DIR}/fstab.qcom")" == "1234567890" ]] || {
    echo "fstab timestamp was not preserved" >&2
    exit 1
}
echo "vendor_dlkm-only AVB patch test passed"
