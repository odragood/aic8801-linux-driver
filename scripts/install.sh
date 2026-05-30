#!/bin/bash
# Pix-Link LV-UAX04 / UAX-04 (AIC8801) Linux Driver Installer
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Run as root: sudo $0${NC}"; exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DRV_DIR="$PROJECT_DIR/driver"
FW_DIR="$PROJECT_DIR/firmware"

echo -e "${GREEN}=== Pix-Link LV-UAX04 (AIC8801) Linux Driver ===${NC}"

# Detect system
echo -e "\n${YELLOW}[1] Detecting system...${NC}"
. /etc/os-release 2>/dev/null || true
echo "  Distro: $ID $VERSION_ID"
echo "  Kernel: $(uname -r)"

# Install deps
echo -e "\n${YELLOW}[2] Installing dependencies...${NC}"
case $ID in
    ubuntu|debian|linuxmint|pop)
        apt-get update
        apt-get install -y build-essential linux-headers-$(uname -r) git dkms wget bluez
        ;;
    fedora|centos|rhel)
        dnf install -y kernel-devel-$(uname -r) git dkms wget make gcc bluez
        ;;
    arch|manjaro)
        pacman -S --noconfirm linux-headers git dkms wget base-devel bluez
        ;;
    *)
        echo -e "${YELLOW}Unknown distro. Install manually: build-essential, git, dkms, wget, bluez${NC}"
        ;;
esac

# Clone base driver
echo -e "\n${YELLOW}[3] Cloning base driver...${NC}"
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git clone --depth=1 https://github.com/fqrious/aic8800-dkms.git
cd aic8800-dkms

# Copy custom files
echo -e "\n${YELLOW}[4] Applying custom driver files...${NC}"
cp -v "$DRV_DIR/aicwf_compat_8800dc.c" src/aic8800_fdrv/
cp -v "$DRV_DIR/aicwf_compat_8800dc.h" src/aic8800_fdrv/
cp -v "$DRV_DIR/aicwf_usb.c" src/aic8800_fdrv/
cp -v "$DRV_DIR/aicwf_usb.h" src/aic8800_fdrv/
cp -v "$DRV_DIR/rwnx_platform.c" src/aic8800_fdrv/
cp -v "$DRV_DIR/rwnx_platform.h" src/aic8800_fdrv/
cp -v "$DRV_DIR/usb_host.c" src/aic8800_fdrv/
cp -v "$DRV_DIR/aic_load_fw_aic_bluetooth_main.c" src/aic_load_fw/aic_bluetooth_main.c
cp -v "$DRV_DIR/aic_load_fw_aicwf_usb.c" src/aic_load_fw/aicwf_usb.c
cp -v "$DRV_DIR/aic_load_fw_aicwf_usb.h" src/aic_load_fw/aicwf_usb.h
cp -v "$DRV_DIR/aicbluetooth.c" src/aic_load_fw/
cp -v "$DRV_DIR/aicbluetooth.h" src/aic_load_fw/
cp -v "$DRV_DIR/aicbluetooth_cmds.c" src/aic_load_fw/
cp -v "$DRV_DIR/aicbluetooth_cmds.h" src/aic_load_fw/

# Compile
echo -e "\n${YELLOW}[5] Compiling...${NC}"
cd src
make -j$(nproc)

# Install modules
echo -e "\n${YELLOW}[6] Installing kernel modules...${NC}"
mkdir -p /lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800
cp aic_load_fw/aic_load_fw.ko /lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800/
cp aic8800_fdrv/aic8800_fdrv.ko /lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800/
depmod -a

# Install Wi-Fi firmware
echo -e "\n${YELLOW}[7] Installing Wi-Fi firmware...${NC}"
mkdir -p /lib/firmware/aic8800DC
cp "$FW_DIR"/*8800dc* "$FW_DIR"/lmacfw_rf_8800dc* /lib/firmware/aic8800DC/ 2>/dev/null || true

# Install Bluetooth firmware
echo -e "\n${YELLOW}[8] Installing Bluetooth firmware...${NC}"
mkdir -p /lib/firmware/aic8800
cp "$FW_DIR"/fmacfw*.bin "$FW_DIR"/fw_patch*.bin "$FW_DIR"/fw_adid*.bin "$FW_DIR"/fw_ble* /lib/firmware/aic8800/ 2>/dev/null || true
cp "$FW_DIR"/fw_*u03* /lib/firmware/aic8800/ 2>/dev/null || true

# Userconfig
echo -e 'country_code=00\ntx_power_2g=20\ntx_power_5g=20' > /lib/firmware/aic8800/aic_userconfig.txt

# udev rules
echo -e "\n${YELLOW}[9] Configuring system...${NC}"
cp "$SCRIPT_DIR/99-aic8801.rules" /etc/udev/rules.d/
udevadm control --reload-rules

# Modules auto-load
cat > /etc/modules-load.d/aic8801.conf << 'EOF'
aic_load_fw
aic8800_fdrv
EOF

# Load modules
echo -e "\n${YELLOW}[10] Loading modules...${NC}"
modprobe aic_load_fw
sleep 5
modprobe aic8800_fdrv
sleep 2
modprobe btusb 2>/dev/null || true

echo ""
echo -e "${GREEN}=== Installation complete! ===${NC}"
echo ""
echo "  Wi-Fi:     iw dev wlx... link"
echo "  Bluetooth: hciconfig -a"
echo ""

rm -rf "$TMP_DIR"
