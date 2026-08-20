# Deprecated recovery-flashable package

The active build and CI distribution no longer generate or recommend this
recovery installer. Kernel images are now distributed as a fastbootd package
with separate Windows, macOS, and Linux installers:

- `prebuilts/fastboot/flash_windows.bat`
- `prebuilts/fastboot/flash_macos.sh`
- `prebuilts/fastboot/flash_linux.sh`

See [`prebuilts/fastboot/README.md`](../fastboot/README.md) and the repository
README for the supported installation flow. The legacy template remains in
this directory only for historical reference and is not called by `build.sh`.
