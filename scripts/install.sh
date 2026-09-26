#!/bin/bash
# Pix-Link LV-UAX04 / UAX-04 (AIC8801) Linux Driver Installer
#
# Usage: sudo ./install.sh [--dkms]
#   --dkms   Install as a DKMS module (rebuilt automatically on kernel updates)
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Run as root: sudo $0${NC}"; exit 1
fi

USE_DKMS=0
for arg in "$@"; do
    case "$arg" in
        --dkms) USE_DKMS=1 ;;
        *) echo -e "${RED}Unknown option: $arg${NC}"; echo "Usage: sudo $0 [--dkms]"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DRV_DIR="$PROJECT_DIR/driver"
FW_DIR="$PROJECT_DIR/firmware"
PKG="aic8801"
PKGVER="1.0"

echo -e "${GREEN}=== Pix-Link LV-UAX04 (AIC8801) Linux Driver ===${NC}"
if [ "$USE_DKMS" = 1 ]; then
    echo -e "${GREEN}Mode: DKMS${NC}"
fi

# Detect system
echo -e "\n${YELLOW}[1] Detecting system...${NC}"
. /etc/os-release 2>/dev/null || true
echo "  Distro: $ID $VERSION_ID"
echo "  Kernel: $(uname -r)"

# Kernel headers (skip if already present, e.g. CachyOS with linux-cachyos-headers)
if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
    echo -e "\n${YELLOW}[2] Installing kernel headers...${NC}"
    case $ID in
        ubuntu|debian|linuxmint|pop) apt-get update && apt-get install -y linux-headers-$(uname -r) ;;
        fedora|centos|rhel)          dnf install -y kernel-devel-$(uname -r) ;;
        arch|manjaro|cachyos|endeavouros|garuda) pacman -S --noconfirm linux-headers ;;
        *) echo -e "${RED}Install kernel headers for $(uname -r) manually.${NC}"; exit 1 ;;
    esac
else
    echo "  Kernel headers OK: /lib/modules/$(uname -r)/build"
fi

# Install deps
echo -e "\n${YELLOW}[3] Installing dependencies...${NC}"
case $ID in
    ubuntu|debian|linuxmint|pop)
        apt-get update
        apt-get install -y build-essential git wget bluez
        if [ "$USE_DKMS" = 1 ]; then apt-get install -y dkms; fi
        ;;
    fedora|centos|rhel)
        dnf install -y git wget make gcc bluez
        if [ "$USE_DKMS" = 1 ]; then dnf install -y dkms; fi
        ;;
    arch|manjaro|cachyos|endeavouros|garuda)
        pacman -S --noconfirm --needed git wget base-devel bluez
        if [ "$USE_DKMS" = 1 ]; then pacman -S --noconfirm --needed dkms; fi
        ;;
    *)
        echo -e "${YELLOW}Unknown distro. Install manually: build-essential, git, wget, bluez${NC}"
        ;;
esac

# Clone base driver
echo -e "\n${YELLOW}[4] Cloning base driver...${NC}"
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git clone --depth=1 https://github.com/fqrious/aic8800-dkms.git
cd aic8800-dkms

# Copy custom files
echo -e "\n${YELLOW}[5] Applying custom driver files...${NC}"
cp -v "$DRV_DIR/aicwf_compat_8800dc.c" src/aic8800_fdrv/
cp -v "$DRV_DIR/aicwf_compat_8800dc.h" src/aic8800_fdrv/
cp -v "$DRV_DIR/aicwf_usb.c" src/aic8800_fdrv/
cp -v "$DRV_DIR/aicwf_usb.h" src/aic8800_fdrv/
cp -v "$DRV_DIR/rwnx_platform.c" src/aic8800_fdrv/
cp -v "$DRV_DIR/rwnx_platform.h" src/aic8800_fdrv/
cp -v "$DRV_DIR/rwnx_main.c" src/aic8800_fdrv/
cp -v "$DRV_DIR/rwnx_msg_tx.c" src/aic8800_fdrv/
cp -v "$DRV_DIR/usb_host.c" src/aic8800_fdrv/
cp -v "$DRV_DIR/aic_load_fw_aic_bluetooth_main.c" src/aic_load_fw/aic_bluetooth_main.c
cp -v "$DRV_DIR/aic_load_fw_aicwf_usb.c" src/aic_load_fw/aicwf_usb.c
cp -v "$DRV_DIR/aic_load_fw_aicwf_usb.h" src/aic_load_fw/aicwf_usb.h
cp -v "$DRV_DIR/aicbluetooth.c" src/aic_load_fw/
cp -v "$DRV_DIR/aicbluetooth.h" src/aic_load_fw/
cp -v "$DRV_DIR/aicbluetooth_cmds.c" src/aic_load_fw/
cp -v "$DRV_DIR/aicbluetooth_cmds.h" src/aic_load_fw/

if [ "$USE_DKMS" = 1 ]; then
    # Stage sources and register with DKMS
    echo -e "\n${YELLOW}[6] Setting up DKMS module $PKG-$PKGVER...${NC}"
    SRC="/usr/src/$PKG-$PKGVER"
    rm -rf "$SRC"
    mkdir -p "$SRC"
    cp -a "$TMP_DIR/aic8800-dkms/src/." "$SRC/"
    cp "$SCRIPT_DIR/dkms.conf" "$SCRIPT_DIR/dkms-build.sh" "$SRC/"
    chmod 755 "$SRC/dkms-build.sh"
    find "$SRC" -type f \( -name '*.o' -o -name '*.ko' -o -name '.*.cmd' \
        -o -name '*.mod' -o -name '*.mod.c' -o -name 'modules.order' \
        -o -name 'Module.symvers' \) -delete
    rm -rf "$SRC/.tmp_versions"
    dkms remove -m "$PKG" -v "$PKGVER" --all 2>/dev/null || true
    dkms add -m "$PKG" -v "$PKGVER"
    dkms build -m "$PKG" -v "$PKGVER"
    dkms install -m "$PKG" -v "$PKGVER" --force
else
    # Compile
    echo -e "\n${YELLOW}[6] Compiling...${NC}"
    cd src
    if grep -q '^CONFIG_CC_IS_CLANG=y' "/lib/modules/$(uname -r)/build/.config" 2>/dev/null; then
        echo "  Clang-built kernel detected, building with LLVM=1"
        make LLVM=1 -j$(nproc)
    else
        make -j$(nproc)
    fi

    # Install modules
    echo -e "\n${YELLOW}[7] Installing kernel modules...${NC}"
    mkdir -p /lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800
    cp aic_load_fw/aic_load_fw.ko /lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800/
    cp aic8800_fdrv/aic8800_fdrv.ko /lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800/
    depmod -a
fi

# Install Wi-Fi firmware
echo -e "\n${YELLOW}[8] Installing Wi-Fi firmware...${NC}"
mkdir -p /lib/firmware/aic8800DC
cp "$FW_DIR"/*8800dc* "$FW_DIR"/lmacfw_rf_8800dc* /lib/firmware/aic8800DC/ 2>/dev/null || true
echo -e 'country_code=00\ntx_power_2g=20\ntx_power_5g=20' > /lib/firmware/aic8800DC/aic_userconfig_8800dc.txt

# Install Bluetooth firmware
echo -e "\n${YELLOW}[9] Installing Bluetooth firmware...${NC}"
mkdir -p /lib/firmware/aic8800
cp "$FW_DIR"/fmacfw*.bin "$FW_DIR"/fw_patch*.bin "$FW_DIR"/fw_adid*.bin "$FW_DIR"/fw_ble* /lib/firmware/aic8800/ 2>/dev/null || true
echo -e 'country_code=00\ntx_power_2g=20\ntx_power_5g=20' > /lib/firmware/aic8800/aic_userconfig.txt

# udev rules
echo -e "\n${YELLOW}[10] Configuring system...${NC}"
cp "$SCRIPT_DIR/99-aic8801.rules" /etc/udev/rules.d/
udevadm control --reload-rules

# Modules auto-load
cat > /etc/modules-load.d/aic8801.conf << 'EOF'
aic_load_fw
aic8800_fdrv
EOF

# Load modules
echo -e "\n${YELLOW}[11] Loading modules...${NC}"
modprobe aic_load_fw
sleep 5
modprobe aic8800_fdrv
sleep 2
modprobe btusb 2>/dev/null || true
rfkill unblock wifi 2>/dev/null || true

echo ""
echo -e "${GREEN}=== Installation complete! ===${NC}"
echo ""
echo "  Wi-Fi:     nmcli device wifi connect \"SSID\" password \"PASSWORD\""
echo "  Bluetooth: bluetoothctl"
if [ "$USE_DKMS" = 1 ]; then
    echo "  DKMS:      dkms status"
fi
echo ""

rm -rf "$TMP_DIR"
