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

sm8550_decode_vendor_fragment() {
  local stock="$1" fragment="$2" fragment_count="$3" output="$4";
  local page_size header_size ramdisk_size fragment_size offset;
  if cpio -it -F "$fragment" >/dev/null 2>&1; then
    cp -f "$fragment" "$output";
    return;
  fi;
  if "$BIN/magiskboot" decompress "$fragment" "$output"; then
    return 0;
  fi;
  rm -f "$output";

  # Some Samsung v4 images report a vendor ramdisk one byte larger than their
  # sole table fragment. magiskboot extracts only the table size, dropping the
  # last compressed byte; it then reports lz4_lg and cannot decompress it.
  [ "$fragment_count" -eq 1 ] || return 1;
  page_size="$("$BIN/busybox" od -An -tu4 -j 12 -N 4 "$stock" | "$BIN/busybox" tr -d '[:space:]')" || return 1;
  header_size="$("$BIN/busybox" od -An -tu4 -j 2096 -N 4 "$stock" | "$BIN/busybox" tr -d '[:space:]')" || return 1;
  ramdisk_size="$("$BIN/busybox" od -An -tu4 -j 24 -N 4 "$stock" | "$BIN/busybox" tr -d '[:space:]')" || return 1;
  case "$page_size:$header_size:$ramdisk_size" in *[!0-9:]*|:*|*:) return 1;; esac;
  fragment_size="$(wc -c < "$fragment")" || return 1;
  [ "$page_size" -gt 0 ] && [ "$header_size" -gt 0 ] &&
    [ "$ramdisk_size" -eq "$((fragment_size + 1))" ] || return 1;
  offset="$((((header_size + page_size - 1) / page_size) * page_size + ramdisk_size - 1))";
  cp -f "$fragment" "$output.compressed" || return 1;
  dd if="$stock" of="$output.tail" bs=1 skip="$offset" count=1 2>/dev/null || return 1;
  [ "$(wc -c < "$output.tail")" -eq 1 ] || return 1;
  cat "$output.tail" >> "$output.compressed" || return 1;
  rm -f "$output.tail";
  "$BIN/magiskboot" decompress "$output.compressed" "$output" || return 1;
  rm -f "$output.compressed";
}

sm8550_prepare_vendor_boot() (
  local work="$1" block="$2" modules="$3" output="$4";
  local fragment platform="" file name status entry fragment_count=0;
  mkdir -p "$work" && cd "$work" || exit 1;
  dd if="$block" of=stock.img bs=1048576 || exit 1;
  # Keep compressed components intact so unrelated v4 fragments do not change.
  "$BIN/magiskboot" unpack -n -h stock.img;
  status=$?;
  # Recent magiskboot returns 3 for a successfully unpacked vendor image.
  case "$status" in 0|3) ;; *) exit 1;; esac;
  for fragment in ramdisk.cpio vendor_ramdisk/*.cpio; do
    [ -f "$fragment" ] && fragment_count="$((fragment_count + 1))";
  done;
  for fragment in ramdisk.cpio vendor_ramdisk/*.cpio; do
    [ -f "$fragment" ] || continue;
    sm8550_decode_vendor_fragment stock.img "$fragment" "$fragment_count" candidate.cpio || {
      echo "Unable to decode vendor ramdisk fragment: $fragment" >&2;
      exit 1;
    };
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
