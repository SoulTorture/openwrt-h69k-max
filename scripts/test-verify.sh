#!/bin/bash
# Replicates the workflow's 校验关键配置符号 step using the real config files
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"

# Build a stub .config that has all REQUIRED symbols + most requested, minus one optional
cat > /tmp/.config.stub <<'EOF'
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_hinlink_opc-h69k=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_TARGET_EXT4_BLOCKSIZE_4K=y
CONFIG_PACKAGE_u-boot-generic-rk3568=y
CONFIG_PACKAGE_rkbin-rk3568=y
CONFIG_PACKAGE_kmod-mt7916-firmware=y
CONFIG_PACKAGE_kmod-mt7915e=y
CONFIG_PACKAGE_kmod-hwmon-pwmfan=y
CONFIG_PACKAGE_kmod-pcie_mhi=y
CONFIG_PACKAGE_kmod-usb-serial-option=y
CONFIG_PACKAGE_kmod-usb-serial-wwan=y
CONFIG_PACKAGE_kmod-usb-serial-qualcomm=y
CONFIG_PACKAGE_kmod-usb-acm=y
CONFIG_PACKAGE_kmod-usb-net=y
CONFIG_PACKAGE_kmod-usb-net-qmi-wwan=y
CONFIG_PACKAGE_kmod-usb-net-cdc-mbim=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ncm=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ether=y
CONFIG_PACKAGE_kmod-usb-net-cdc-subset=y
CONFIG_PACKAGE_kmod-usb-net-rndis=y
CONFIG_PACKAGE_wwan=y
CONFIG_PACKAGE_uqmi=y
CONFIG_PACKAGE_umbim=y
CONFIG_PACKAGE_luci-proto-qmi=y
CONFIG_PACKAGE_luci-proto-mbim=y
CONFIG_PACKAGE_luci-proto-ncm=y
CONFIG_PACKAGE_luci-app-modemband=y
CONFIG_PACKAGE_modemband=y
CONFIG_PACKAGE_luci-app-3ginfo-lite=y
CONFIG_PACKAGE_sms-tool=y
CONFIG_PACKAGE_luci-app-sms-tool-js=y
CONFIG_PACKAGE_picocom=y
# NOTE: CONFIG_PACKAGE_kmod-mt76-connac intentionally absent to test WARNING path
# NOTE: CONFIG_PACKAGE_luci-app-fancontrol intentionally absent (not in LEDE feeds)
EOF

cp /tmp/.config.stub /tmp/.config

cat "$ROOT/config/h69k-max.config" "$ROOT/config/5g-rm520n.config" \
  | sed -n 's/^\(CONFIG_[A-Za-z0-9_-]*\)=y$/\1/p' | sort -u > /tmp/wanted.txt
echo "本仓库请求的符号数: $(wc -l < /tmp/wanted.txt)"
printf '%s\n' $(cat /tmp/wanted.txt) > /tmp/requested.txt
echo "requested.txt 行数: $(wc -l < /tmp/requested.txt)"

hard_list='CONFIG_PACKAGE_u-boot-generic-rk3568 CONFIG_PACKAGE_rkbin-rk3568 CONFIG_PACKAGE_kmod-mt7916-firmware CONFIG_PACKAGE_kmod-mt7915e CONFIG_PACKAGE_kmod-hwmon-pwmfan'

hard_fail=0
warn_count=0

while read -r sym; do
  [ -z "$sym" ] && continue
  case " $hard_list " in
    *" $sym "*) is_hard=1 ;;
    *) case "$sym" in CONFIG_TARGET_*) is_hard=1 ;; *) is_hard=0 ;; esac ;;
  esac
  if grep -q "^${sym}=y$" /tmp/.config; then
    echo "[OK] ${sym}"
  elif [ "$is_hard" -eq 1 ]; then
    echo "::error::必须项缺失: ${sym}"
    hard_fail=$((hard_fail+1))
  else
    echo "::warning::可选包未生效: ${sym}"
    warn_count=$((warn_count+1))
  fi
done < /tmp/requested.txt

echo "==== 必须项缺失: ${hard_fail}   可选包未生效: ${warn_count} ===="
[ "$hard_fail" -eq 0 ]
