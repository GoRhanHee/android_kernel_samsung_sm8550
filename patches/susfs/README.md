# SUSFS 2.3.0 build-time patches

These patches are applied only by `./build.sh <device> susfs` and are reverted
when the build exits.

1. `0001-kernelsu-next-3.4.0-susfs-2.3.0.patch` adds the KernelSU-Next-side
   SUSFS integration. It is rebased on KernelSU-Next 3.4.0 and connects the
   v2.3 post-exec path to the scoped `ksu_driver_su` session FD.
2. `0002-susfs-2.3.0-android13-5.15.patch` adds the kernel-side SUSFS 2.3.0
   implementation for the Android 13 / Linux 5.15 common tree.

The update tracks the `gki-android13-5.15` SUSFS branch at:

```text
b5acbf04aeff61ea1b0356ffdd7b142d36be4ff3
```

The kernel hooks are adapted to the Qualcomm/Samsung KDP include and mount
contexts in common tree `ca8bcd58fe1a`. The embedded `fs/susfs.c`,
`include/linux/susfs.h`, and `include/linux/susfs_def.h` come from that SUSFS
revision, including the SUS_KSTAT `f_flags` fix.

The build script pins the KernelSU-Next `v3.4.0` tag to:

```text
1a879d6a866f80b1fa1c1009a2ffa747873cbb5e
```

The integration preserves the 3.4.0 version-tag, bundled-LKM, SELinux wrapper,
non-root ambient-capability, and scoped driver-FD changes while replacing its
syscall-hook path with the Android 13 / Linux 5.15 SUSFS manual hooks.

The normal mode does not apply either patch.

The SUSFS mode keeps configuration separate from the common device config:
`custom_defconfigs/ksu_defconfig` enables KernelSU-Next, and
`custom_defconfigs/susfs_defconfig` enables the SUSFS 2.3.0 options. They are
merged in that order only for SUSFS mode.
