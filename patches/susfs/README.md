# SUSFS 2.3.0 build-time patches

These patches are applied only by `./build.sh <device> susfs` and are reverted
when the build exits.

1. `0001-kernelsu-next-85171fb-susfs-2.3.0.patch` adds the KernelSU-Next-side
   SUSFS integration. It is rebased on the pinned KernelSU-Next dev commit and connects the
   v2.3 post-exec path to the scoped `ksu_driver_su` session FD.
   The KernelSU-Next `avc_spoof` feature controls the SUSFS AVC audit hook in
   this mode, with no second kprobe installed.
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

The build script pins the KernelSU-Next `dev` branch snapshot from
2026-10-03 to:

```text
85171fb99ef33b652d3b09849637adb37537873f
```

The integration preserves the upstream version-tag, bundled-LKM, SELinux wrapper,
non-root ambient-capability, and scoped driver-FD changes while replacing its
syscall-hook path with the Android 13 / Linux 5.15 SUSFS manual hooks.

The normal mode does not apply either patch.

The SUSFS mode keeps configuration separate from the common device config:
`custom_defconfigs/ksu_defconfig` enables KernelSU-Next, and
`custom_defconfigs/susfs_defconfig` enables the SUSFS 2.3.0 options. They are
merged in that order only for SUSFS mode.
