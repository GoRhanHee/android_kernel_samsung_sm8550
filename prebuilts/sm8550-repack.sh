#!/bin/sh

# Use magiskboot's image/CPIO interface rather than branch-specific AK3
# vendor ramdisk variables. All preparation functions run before flashing.
sm8550_prepare_boot() (
  local work="$1" block="$2" image="$3" output="$4";
  mkdir -p "$work" && cd "$work" || exit 1;
  dd if="$block" of=stock.img bs=1048576 || exit 1;
  "$BIN/magiskboot" unpack -n -h stock.img || exit 1;
  cp -f "$image" kernel || exit 1;
  PATCHVBMETAFLAG=false "$BIN/magiskboot" repack stock.img "$output";
)

sm8550_prepare_vendor_boot() (
  local work="$1" block="$2" modules="$3" output="$4";
  local fragment platform="" file name status entry;
  mkdir -p "$work" && cd "$work" || exit 1;
  dd if="$block" of=stock.img bs=1048576 || exit 1;
  # Keep compressed components intact so unrelated v4 fragments do not change.
  "$BIN/magiskboot" unpack -n -h stock.img;
  status=$?;
  # Recent magiskboot returns 3 for a successfully unpacked vendor image.
  case "$status" in 0|3) ;; *) exit 1;; esac;
  for fragment in ramdisk.cpio vendor_ramdisk/*.cpio; do
    [ -f "$fragment" ] || continue;
    rm -f candidate.cpio;
    "$BIN/magiskboot" decompress "$fragment" candidate.cpio ||
      cp -f "$fragment" candidate.cpio || exit 1;
    if "$BIN/magiskboot" cpio candidate.cpio "exists first_stage_ramdisk/fstab.qcom"; then
      [ -z "$platform" ] || {
        echo "Multiple vendor ramdisks contain fstab.qcom" >&2;
        exit 1;
      };
      platform="$fragment";
      cp -f candidate.cpio platform.cpio || exit 1;
    fi;
  done;
  [ -n "$platform" ] || {
    echo "No vendor ramdisk contains first_stage_ramdisk/fstab.qcom" >&2;
    exit 1;
  };
  "$BIN/magiskboot" cpio platform.cpio "extract first_stage_ramdisk/fstab.qcom $work/fstab.qcom" || exit 1;
  patch_dlkm_fstab "$work/fstab.qcom" || exit 1;
  cp -a "$modules" "$work/modules" || exit 1;

  # One CPIO operation keeps unrelated content, modes and ownership intact.
  # magiskboot normalizes timestamps in the updated archive to zero.
  # Package paths and filenames have no whitespace (magiskboot command syntax).
  # The bundled magiskboot accepts single-entry rm, but its recursive flag
  # parser can abort. List the original CPIO and remove module entries singly.
  cpio -it -F platform.cpio > module-entries || exit 1;
  set --;
  while IFS= read -r entry; do
    case "$entry" in
      lib/modules|lib/modules/*|./lib/modules|./lib/modules/*)
        set -- "$@" "rm $entry";;
    esac;
  done < module-entries;
  if ! "$BIN/magiskboot" cpio platform.cpio "exists lib"; then
    set -- "$@" "mkdir 0755 lib";
  fi;
  set -- "$@" "mkdir 0755 lib/modules";
  for file in "$work/modules/"*; do
    [ -f "$file" ] || exit 1;
    name="${file##*/}";
    set -- "$@" "add 0644 lib/modules/$name $file";
  done;
  set -- "$@" "add 0644 first_stage_ramdisk/fstab.qcom $work/fstab.qcom";
  "$BIN/magiskboot" cpio platform.cpio "$@" || exit 1;
  cp -f platform.cpio "$platform" || exit 1;
  PATCHVBMETAFLAG=false "$BIN/magiskboot" repack stock.img "$output";
)

sm8550_check_image_size() {
  local image="$1" stock="$2" label="$3" size capacity;
  [ -s "$image" ] || abort "Prepared $label image is missing.";
  size="$(wc -c < "$image")";
  capacity="$(wc -c < "$stock")";
  [ "$size" -le "$capacity" ] ||
    abort "New $label image ($size bytes) exceeds partition capacity ($capacity bytes).";
}

sm8550_flash_prepared() {
  local image="$1" block="$2" stock="$3" label="$4" capacity isro;
  capacity="$(wc -c < "$stock")";
  # Extend the prepared file with zeroes, without erasing the target first.
  dd if=/dev/zero of="$image" bs=1 count=0 seek="$capacity" ||
    abort "Failed to pad $label image.";
  isro="$(blockdev --getro "$block" 2>/dev/null)";
  blockdev --setrw "$block" 2>/dev/null;
  ui_print "- Flashing $label";
  dd if="$image" of="$block" bs=1048576 conv=notrunc,fsync ||
    abort "Flashing $label failed.";
  [ "$isro" != 1 ] || blockdev --setro "$block" 2>/dev/null;
}
