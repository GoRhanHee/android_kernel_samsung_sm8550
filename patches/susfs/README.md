# SUSFS 2.2.0 build-time patches

These patches are applied only by `./build.sh <device> susfs` and are reverted
when the build exits.

1. `0001-kernelsu-next-susfs-2.2.0.patch` adds the KernelSU-Next-side SUSFS
   toolkit integration based on the referenced KSU-Next patch.
2. `0002-susfs-2.2.0-android13-5.15.patch` adds the kernel-side SUSFS 2.2.0
   implementation for the Android 13 / Linux 5.15 common tree.

The kernel patch is adapted to the Qualcomm/KDP include context in common tree
`1e002335c86aa199b42d877bb41ff6d9e18122e7`. It contains the v2.2.0 headers and
implementation, rather than the newer v2.3 definitions.

The build script pins KernelSU-Next to:

```text
36aa55c521e509449bfe48bae0ab8c397174c1cb
```

The normal mode does not apply either patch.

The SUSFS mode keeps configuration separate from the common device config:
`custom_defconfigs/ksu_defconfig` enables KernelSU-Next, and
`custom_defconfigs/susfs_defconfig` enables the SUSFS 2.2.0 options. They are
merged in that order only for SUSFS mode.
