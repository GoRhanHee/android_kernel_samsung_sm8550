# SUSFS 2.3.0 build-time patches

`./build.sh susfs <oneui|aosp>` applies these patches to the pinned KernelSU-Next
and common kernel trees. Source preparation reverts them after the build exits.

| Component | Branch | Pinned commit |
| --- | --- | --- |
| KernelSU-Next | `dev` | `b427a3f9c2421a443f961007bfce66b25486643f` |
| SUSFS | `gki-android13-5.15` | `0b5f96716cb2fc7b035dce2f06cb8a51e1b9b108` |

1. `0001-kernelsu-next-b427a3f-susfs-2.3.0.patch` adapts the current KernelSU-Next
   `dev` snapshot to the Android 13 / Linux 5.15 manual SUSFS hooks. It retains
   the scoped `ksu_driver_su` session FD, the current preinit runner, and the
   SUSFS priority UID filter command and package observer refresh.
2. `0002-susfs-2.3.0-android13-5.15-0b5f967.patch` ports the matching SUSFS
   kernel changes and source files to this Qualcomm/Samsung common tree. The
   mount hooks retain the Samsung KDP mount layout. The SELinux hooks retain
   the 5.15-compatible local wrappers.

The KernelSU-Next `avc_spoof` feature toggles the SUSFS static key in
`fs/susfs.c`; `security/selinux/avc.c` checks that key when formatting an AVC
audit record. SUSFS mode does not install a second AVC kprobe.

`custom_defconfigs/ksu_defconfig` and `custom_defconfigs/susfs_defconfig` are
merged in that order only for SUSFS mode. Vanilla and KernelSU-only modes do
not apply either SUSFS patch.
