#!/bin/bash
# Uninstall Pix-Link LV-UAX04 (AIC8801) Linux Driver
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
fi

PKG="aic8801"
PKGVER="1.0"

echo "Removing AIC8801 driver..."

# Remove modules
modprobe -r aic8800_fdrv 2>/dev/null || true
modprobe -r aic_load_fw 2>/dev/null || true
modprobe -r btusb 2>/dev/null || true

# Remove DKMS module (if installed with --dkms)
if command -v dkms >/dev/null 2>&1; then
    dkms remove -m "$PKG" -v "$PKGVER" --all 2>/dev/null || true
fi
rm -rf "/usr/src/$PKG-$PKGVER"

# Remove firmware
rm -rf /lib/firmware/aic8800DC
rm -rf /lib/firmware/aic8800

# Remove kernel modules (manual install)
rm -f /lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800/aic_load_fw.ko
rm -f /lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800/aic8800_fdrv.ko
depmod -a

# Remove config
rm -f /etc/modules-load.d/aic8801.conf
rm -f /etc/modprobe.d/aic8801.conf
rm -f /etc/udev/rules.d/99-aic8801.rules
udevadm control --reload-rules

echo "Driver removed successfully."
