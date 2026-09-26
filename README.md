# Pix-Link LV-UAX04 / UAX-04 — Linux Driver (AIC8801)

Linux driver for the **Pix-Link LV-UAX04 (UAX-04)** Wi-Fi adapter with **AIC AIC8801** chipset.
Supports **Wi-Fi 6 (802.11ax)** up to **300 Mbps** and **Bluetooth 5.2**.

| Hardware | Spec |
|----------|------|
| **Adapter** | Pix-Link LV-UAX04 / UAX-04 |
| **Chipset** | AIC8801 (AIC Semiconductor) |
| **USB VID:PID** | Bootloader: `a69c:8800` → Operational: `a69c:8801` |
| **Wi-Fi** | 802.11a/b/g/n/ac/ax, 1T1R, 2.4 + 5 GHz |
| **Bluetooth** | BT 5.2 HCI via native `btusb` |
| **Interface** | USB 2.0 High Speed (480 Mbps) |

## Compatibility

| Kernel | Status |
|--------|--------|
| **5.4 – 7.2** | ✅ Tested (Ubuntu 26.04 kernel 7.0, CachyOS kernel 7.2.6) |
| **< 5.4** | ⚠️ Untested, should work |
| **> 7.2** | ⚠️ Untested, may need KERNEL_VERSION macro updates |

> **Clang-built kernels** (CachyOS, some Fedora/openSUSE setups): the module must be
> built with `make LLVM=1`, otherwise the build fails with unrecognized
> `-mllvm`/`-fsplit-lto-unit` options. `scripts/install.sh` detects this automatically.

## Installation

### Quick install (recommended)

```bash
git clone https://github.com/odragood/aic8801-linux-driver.git
cd aic8801-linux-driver
sudo ./scripts/install.sh          # normal install
sudo ./scripts/install.sh --dkms   # DKMS: auto-rebuilds on kernel updates
```

Uninstall with `sudo ./scripts/uninstall.sh`.

### Manual installation

```bash
# 1. Dependencies
sudo apt install -y build-essential linux-headers-$(uname -r) git wget bluez

# 2. Clone base driver
cd /tmp
git clone --depth=1 https://github.com/fqrious/aic8800-dkms.git
cd aic8800-dkms

# 3. Copy custom driver files
cp /path/to/driver/aicwf_compat_8800dc.c src/aic8800_fdrv/
cp /path/to/driver/aicwf_compat_8800dc.h src/aic8800_fdrv/
cp /path/to/driver/aicwf_usb.c src/aic8800_fdrv/
cp /path/to/driver/aicwf_usb.h src/aic8800_fdrv/
cp /path/to/driver/rwnx_platform.c src/aic8800_fdrv/
cp /path/to/driver/rwnx_platform.h src/aic8800_fdrv/
cp /path/to/driver/rwnx_main.c src/aic8800_fdrv/
cp /path/to/driver/rwnx_msg_tx.c src/aic8800_fdrv/
cp /path/to/driver/usb_host.c src/aic8800_fdrv/
cp /path/to/driver/aic_load_fw_aic_bluetooth_main.c src/aic_load_fw/aic_bluetooth_main.c
cp /path/to/driver/aic_load_fw_aicwf_usb.c src/aic_load_fw/aicwf_usb.c
cp /path/to/driver/aic_load_fw_aicwf_usb.h src/aic_load_fw/aicwf_usb.h
cp /path/to/driver/aicbluetooth.c src/aic_load_fw/
cp /path/to/driver/aicbluetooth.h src/aic_load_fw/
cp /path/to/driver/aicbluetooth_cmds.c src/aic_load_fw/
cp /path/to/driver/aicbluetooth_cmds.h src/aic_load_fw/

# 4. Compile (add LLVM=1 for clang-built kernels, e.g. CachyOS)
cd src
make -j$(nproc)            # gcc-built kernels
make LLVM=1 -j$(nproc)     # clang-built kernels

# 5. Install kernel modules
sudo mkdir -p /lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800
sudo cp aic_load_fw/aic_load_fw.ko /lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800/
sudo cp aic8800_fdrv/aic8800_fdrv.ko /lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800/
sudo depmod -a

# 6. Install Wi-Fi firmware
sudo mkdir -p /lib/firmware/aic8800DC
sudo cp /path/to/firmware/*8800dc* /path/to/firmware/lmacfw_rf_8800dc* /lib/firmware/aic8800DC/
echo -e 'country_code=00\ntx_power_2g=20\ntx_power_5g=20' | sudo tee /lib/firmware/aic8800DC/aic_userconfig_8800dc.txt

# 7. Install Bluetooth firmware (includes U03 chip revision files)
sudo mkdir -p /lib/firmware/aic8800
sudo cp /path/to/firmware/*.bin /lib/firmware/aic8800/

# 8. Userconfig
echo -e 'country_code=00\ntx_power_2g=20\ntx_power_5g=20' | sudo tee /lib/firmware/aic8800/aic_userconfig.txt

# 9. Load modules (IMPORTANT ORDER!)
sudo modprobe aic_load_fw
sleep 5
sudo modprobe aic8800_fdrv

# 10. (Optional) Auto-load on boot
sudo cp /path/to/scripts/99-aic8801.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
echo -e 'aic_load_fw\naic8800_fdrv' | sudo tee /etc/modules-load.d/aic8801.conf
```

## Architecture

```
USB connects as PID 0x8800 (bootloader)
         │
         ▼
aic_load_fw.ko loads firmware:
  • fmacfw.bin (combined Wi-Fi + BT)
  • fw_adid_u03.bin (ADID calibration)
  • fw_patch_u03.bin (patch data)
  • fw_patch_table_u03.bin (BT patch table)
  • aic_userconfig.txt
         │
         ▼ chip reboots as PID 0x8801
         │
    ┌────┴────┐
    │         │
    ▼         ▼
 MI_00      MI_02
 Bluetooth  WLAN
 btusb.ko   aic8800_fdrv.ko
 (native!)  (FullMAC)
```

## Wi-Fi Speed

| Channel width | PHY Rate (HE) | Real throughput |
|---------------|--------------|-----------------|
| 20 MHz        | 143 Mbps     | ~100 Mbps       |
| 40 MHz        | 287 Mbps     | **~229 Mbps**   |
| 80 MHz*       | 600 Mbps     | ~400+ Mbps      |

_*Depends on router supporting 80 MHz on 5 GHz band._

## Verification

```bash
# Wi-Fi
ip link show                   # wlx... or wlan0
iw dev wlx... link             # Connection status
iw dev wlx... station dump     # Statistics

# Bluetooth
hciconfig -a                   # hci0 UP RUNNING
bluetoothctl
  power on
  scan on
  devices
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Stuck at PID 8800 | `sudo modprobe aic_load_fw` |
| PID 8801 no Wi-Fi | `sudo modprobe aic8800_fdrv` |
| BT not showing up | `sudo modprobe -r btusb && sudo modprobe btusb` |
| PID 5721/5722 | `sudo usb_modeswitch -K -v a69c -p 5721` |
| Build fails with `unrecognized command-line option '-mllvm'` | Clang-built kernel: compile with `make LLVM=1` |
| Wi-Fi "unavailable" in NetworkManager after reloading the module | `sudo systemctl restart wpa_supplicant` |
| Driver gone after a kernel update | Reinstall, or use `sudo ./scripts/install.sh --dkms` |
| Firmware U03 missing | Download from [radxa-pkg/aic8800](https://github.com/radxa-pkg/aic8800/tree/main/src/USB/driver_fw/fw/aic8800) |

## Firmware Structure

### Wi-Fi (`/lib/firmware/aic8800DC/`)
```
fw_patch_8800dc_u02.bin
fw_patch_table_8800dc_u02.bin
lmacfw_rf_8800dc.bin
fmacfw_calib_8800dc_u02.bin
fmacfw_patch_8800dc_u02.bin
fmacfw_patch_tbl_8800dc_u02.bin
fw_adid_8800dc_u02.bin
aic_userconfig_8800dc.txt
```

### Bluetooth (`/lib/firmware/aic8800/`)
```
fmacfw.bin
fmacfw_rf.bin
fw_patch.bin
fw_patch_table.bin
fw_adid.bin
fw_adid_u03.bin         # Required for U03 chip revision
fw_patch_u03.bin        # Required for U03 chip revision
fw_patch_table_u03.bin  # Required for U03 chip revision
fw_ble_scan.bin
fw_ble_scan_ad_filter_dcdc.bin
fw_ble_scan_ad_filter_ldo.bin
aic_userconfig.txt
```

## Credits

- **Base driver**: [fqrious/aic8800-dkms](https://github.com/fqrious/aic8800-dkms) (GPL-2.0)
- **Firmware**: [radxa-pkg/aic8800](https://github.com/radxa-pkg/aic8800)
- **Bluetooth**: Linux kernel native (`btusb.ko`)
- **Reverse engineering**: Windows drivers `aicloadfw.sys` + `aicusbwifi.sys`

## License

GPL-2.0
# aic8801-linux-driver
