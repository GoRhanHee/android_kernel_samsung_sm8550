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

select_wlan_profile() {
  case "$DEVICE_CODENAME" in
    dm3q) WLAN_PROFILE=kiwi_v2;;
    dm1q|dm2q|q5q|b5q) WLAN_PROFILE=qca6490;;
    *) abort "Unsupported device profile: $DEVICE_CODENAME";;
  esac;
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

filter_wlan_modules() {
  local modules_dir="$1" load_file;

  for load_file in "$modules_dir/modules.load" "$modules_dir/modules.load.recovery"; do
    [ -f "$load_file" ] || continue;
    case "$WLAN_PROFILE" in
      qca6490) sed -i '/qca_cld3_kiwi_v2\.ko/d' "$load_file";;
      kiwi_v2) sed -i '/qca_cld3_qca6490\.ko/d' "$load_file";;
    esac;
  done;
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
  cat "$output" >"$fstab";
  rm -f "$output";
}

detect_device;
select_wlan_profile;
ui_print "- Device: $DEVICE_CODENAME";
ui_print "- WLAN profile: $WLAN_PROFILE";

# Flash the common kernel while preserving the stock boot ramdisk.
split_boot;
flash_boot;

# Repack the active device's own vendor_boot so its DTB, bootconfig, and all
# non-platform ramdisk fragments remain device-specific.
BLOCK=vendor_boot;
reset_ak;
split_boot;
unpack_ramdisk;

[ -d "$AKHOME/vrdtmp/ramdisk/lib/modules" ] ||
  abort "Packaged vendor ramdisk modules were not found. Aborting...";
rm -rf "$VENDORRD/ramdisk/lib/modules";
mkdir -p "$VENDORRD/ramdisk/lib/modules";
cp -af "$AKHOME/vrdtmp/ramdisk/lib/modules/." "$VENDORRD/ramdisk/lib/modules/";
filter_wlan_modules "$VENDORRD/ramdisk/lib/modules";
patch_dlkm_fstab "$VENDORRD/ramdisk/first_stage_ramdisk/fstab.qcom";
repack_ramdisk;
flash_boot;

cp -f "$AKHOME/vendor_dlkm_${WLAN_PROFILE}.img" "$AKHOME/vendor_dlkm.img" ||
  abort "Failed to select vendor_dlkm_${WLAN_PROFILE}.img. Aborting...";

"$BIN/lptools_static" unlimited-group ||
  abort "Failed to unlock dynamic partition group size.";

prepare_dlkm_partition vendor_dlkm;
flash_generic vendor_dlkm;
prepare_dlkm_partition system_dlkm;
flash_generic system_dlkm;
