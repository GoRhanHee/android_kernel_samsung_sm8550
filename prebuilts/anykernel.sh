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
# The GKI Image is repacked into the active boot partition. The remaining
# images are flashed by flash_generic in the same order as the reference AK3
# installer; absent optional partitions are ignored by AnyKernel3.
BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
NO_MAGISK_CHECK=1;
NO_VBMETA_PARTITION_PATCH=1;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

dump_boot;
flash_boot;
flash_generic vendor_boot;
flash_generic vendor_dlkm;
flash_generic system_dlkm;
