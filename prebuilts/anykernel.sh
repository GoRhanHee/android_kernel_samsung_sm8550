#!/bin/sh

### GoRhanHee SM8550 universal kernel AnyKernel3 installer

properties() { '
kernel.string=GoRhanHee Kernel for Samsung SM8550
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=dm1q
device.name2=dm2q
device.name3=dm3q
device.name4=q5q
device.name5=b5q
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
NO_MAGISK_CHECK=1;
NO_VBMETA_PARTITION_PATCH=1;

. tools/ak3-core.sh;
. "$BIN/sm8550-repack.sh";

detect_device() {
  local value;

  for property in ro.product.device ro.product.vendor.device ro.product.system.device ro.boot.hardware.sku; do
    value="$(getprop "$property" 2>/dev/null)";
    case "$value" in
      *dm1q*) DEVICE_CODENAME=dm1q; return 0;;
      *dm2q*) DEVICE_CODENAME=dm2q; return 0;;
      *dm3q*) DEVICE_CODENAME=dm3q; return 0;;
      *q5q*) DEVICE_CODENAME=q5q; return 0;;
      *b5q*) DEVICE_CODENAME=b5q; return 0;;
    esac;
  done;
  abort "Unable to identify a supported Samsung SM8550 device. Aborting...";
}

prepare_dlkm_partition() {
  local partition="$1" name;

  "$BIN/httools_static" umount "$partition" >/dev/null 2>&1 || true;
  umount -l "/$partition" >/dev/null 2>&1 || true;

  if [ -e /dev/block/by-name/super -o -e /dev/block/bootdevice/by-name/super ]; then
    name="$partition$SLOT";
    "$BIN/lptools_static" unmap "$name" >/dev/null 2>&1 || true;
    "$BIN/lptools_static" map "$name" ||
      abort "Mapping $name failed. Aborting...";
  fi;
}

patch_dlkm_fstab() {
  local fstab="$1" output="$1.tmp";

  [ -f "$fstab" ] || abort "vendor_boot fstab.qcom was not found. Aborting...";
  awk '
    BEGIN { OFS = "\t" }
    $1 == "vendor_dlkm" || $1 == "system_dlkm" {
      count = split($5, flags, ",")
      value = ""
      for (i = 1; i <= count; i++) {
        if (flags[i] ~ /^avb(=|$)/)
          continue
        value = value (value == "" ? "" : ",") flags[i]
      }
      $5 = value
    }
    { print }
  ' "$fstab" >"$output" || abort "Failed to patch DLKM AVB flags. Aborting...";
  cat "$output" >"$fstab" || abort "Failed to write patched fstab.";
  rm -f "$output" || abort "Failed to remove temporary fstab.";
}

detect_device;
ui_print "- Device: $DEVICE_CODENAME";

BOOT_BLOCK="$BLOCK";
VENDOR_BOOT_BLOCK="";
for partition in "vendor_boot$SLOT" vendor_boot; do
  for directory in /dev/block/by-name /dev/block/bootdevice/by-name; do
    if [ -e "$directory/$partition" ]; then
      VENDOR_BOOT_BLOCK="$directory/$partition";
      break 2;
    fi;
  done;
done;
[ -n "$VENDOR_BOOT_BLOCK" ] || abort "vendor_boot partition was not found.";
[ -d "$AKHOME/sm8550_ramdisk/ramdisk/lib/modules" ] ||
  abort "Packaged vendor ramdisk modules were not found.";

# Prepare both images before writing any partition. No AK3 VENDORRD/vrdtmp
# assumptions: magiskboot retains the stock DTB, bootconfig and other fragments.
sm8550_prepare_boot "$AKHOME/repack-boot" "$BOOT_BLOCK" "$AKHOME/Image" "$AKHOME/boot-prepared.img" ||
  abort "Preparing boot failed. No partitions have been written.";
sm8550_prepare_vendor_boot "$AKHOME/repack-vendor" "$VENDOR_BOOT_BLOCK" \
  "$AKHOME/sm8550_ramdisk/ramdisk/lib/modules" "$AKHOME/vendor-boot-prepared.img" ||
  abort "Preparing vendor_boot failed. No partitions have been written.";
sm8550_check_image_size "$AKHOME/boot-prepared.img" "$AKHOME/repack-boot/stock.img" boot;
sm8550_check_image_size "$AKHOME/vendor-boot-prepared.img" "$AKHOME/repack-vendor/stock.img" vendor_boot;

[ -s "$AKHOME/vendor_dlkm.img" ] || abort "vendor_dlkm image is missing.";
[ -s "$AKHOME/system_dlkm.img" ] || abort "system_dlkm image is missing.";

sm8550_flash_prepared "$AKHOME/boot-prepared.img" "$BOOT_BLOCK" "$AKHOME/repack-boot/stock.img" boot;
sm8550_flash_prepared "$AKHOME/vendor-boot-prepared.img" "$VENDOR_BOOT_BLOCK" "$AKHOME/repack-vendor/stock.img" vendor_boot;

"$BIN/lptools_static" unlimited-group ||
  abort "Failed to unlock dynamic partition group size.";

prepare_dlkm_partition vendor_dlkm;
flash_generic vendor_dlkm;
prepare_dlkm_partition system_dlkm;
flash_generic system_dlkm;
