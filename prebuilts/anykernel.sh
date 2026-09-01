#!/bin/sh

### GoRhanHee Kernel AnyKernel3 installer

### AnyKernel setup
properties() { '
kernel.string=GoRhanHee Kernel for @@DEVICE_NAME@@
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=@@DEVICE_NAME@@
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
# Follow the WildKernels gki-2.0 GKI flow: boot images with no ramdisk
# (ramdisk stored in vendor_boot) must skip ramdisk unpack/repack.
BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
NO_MAGISK_CHECK=1;
NO_VBMETA_PARTITION_PATCH=1;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

prepare_dlkm_partition() {
  local partition="$1" name;

  # Samsung DLKM partitions are logical partitions in super. Recovery can
  # leave their device-mapper nodes mounted/read-only, so recreate the
  # mapping before handing the partition to flash_generic.
  "$BIN/httools_static" umount "$partition" >/dev/null 2>&1 || true;
  umount -l "/$partition" >/dev/null 2>&1 || true;

  if [ -e /dev/block/by-name/super -o -e /dev/block/bootdevice/by-name/super ]; then
    name="$partition$SLOT";
    "$BIN/lptools_static" unmap "$name" >/dev/null 2>&1 || true;
    "$BIN/lptools_static" map "$name" ||
      abort "Mapping $name failed. Aborting...";
  fi;
}

split_boot;
if [ -f "$SPLITIMG/ramdisk.cpio" ]; then
  unpack_ramdisk;
  repack_ramdisk;
fi;

flash_boot;
flash_generic vendor_boot;

# Allow logical DLKM growth to use physical super free space when the group quota is full.
"$BIN/lptools_static" unlimited-group ||
  abort "Failed to unlock dynamic partition group size.";

prepare_dlkm_partition vendor_dlkm;
flash_generic vendor_dlkm;
prepare_dlkm_partition system_dlkm;
flash_generic system_dlkm;
