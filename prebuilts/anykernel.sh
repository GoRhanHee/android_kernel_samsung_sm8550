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

split_boot;
if [ -f "$SPLITIMG/ramdisk.cpio" ]; then
  unpack_ramdisk;
  write_boot;
else
  flash_boot;
  flash_generic vendor_boot;
  flash_generic vendor_dlkm;
  flash_generic system_dlkm;
fi;
