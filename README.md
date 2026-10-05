# H69K-MAX OpenWrt 云编译工程

面向 **恒领 HINLINK H69K-MAX**（Rockchip RK3568）的 OpenWrt 固件编译工程。
主机是 Windows 也能用 —— 编译在 GitHub Actions 的 Ubuntu runner 上完成。

| 项目 | 值 |
|---|---|
| 设备 | HINLINK H69K-MAX / OPC-H69K |
| SoC | Rockchip RK3568（4×Cortex-A55 + 1.0 TOPS NPU） |
| 内存 / 存储 | 4GB LPDDR4 / 32GB eMMC |
| 网口 | 1×1GbE（RTL8211F，RGMII）+ 2×2.5GbE（RTL8125B，PCIe） |
| 无线 | MT7916（mini-PCIe，`mt7915e` 驱动） |
| 5G | 移远 Quectel RM520N-GL |
| 其他 | USB2.0×1、HDMI2.0×1、SSD1306 OLED（I2C5）、PWM 风扇（40°C 起转） |

---

## 1. 为什么必须用云编译

OpenWrt / LEDE 的 buildroot **只能在 Linux 下编译**：

- 需要**大小写敏感**的文件系统（NTFS 不满足，`make` 会认错文件名）
- 需要 GNU make / POSIX 工具链 / `case` 敏感路径，Windows 原生环境无法提供
- 官方明确不支持 Windows 编译（WSL2、Docker、Linux 虚拟机或远程 Linux 才是正途）

本机情况：Windows 10，无 WSL、无 Docker、无 Hyper-V，且 `wsl --install` 需要管理员权限。
因此本工程把编译放到 GitHub Actions（免费、Ubuntu runner、4 核起），你只需要：

1. 把本目录推到自己的 GitHub 仓库
2. 点一次 `Run workflow`
3. 等 1.5–4 小时后下载固件

---

## 2. 设备支持来源（重要）

**主线 OpenWrt 与 ImmortalWrt 都没有 H69K 支持**，只有 H66K / H68K。
H69K 的设备定义目前**只存在于 `coolsnowwolf/lede`（Lean 分支）**及其下游：

| 源码树 | H69K 支持 | 设备名 | 说明 |
|---|---|---|---|
| **`coolsnowwolf/lede` (master)** | ✅ 原生 | `hinlink_opc-h69k` | 本工程使用 |
| `openwrt/openwrt` (25.12 / main) | ❌ | — | 只有 `hinlink_h66k` / `hinlink_h68k` |
| `immortalwrt/immortalwrt` | ❌ | — | 同上 |
| iStoreOS | ✅ | `hinlink_opc-h6xk` | H66K/H68K/H69K 三合一 profile |
| `smallprogram/OpenWrtAction` | ✅ | `hinlink_opc-h69k` | Lean 专用配置（本工程交叉核对过） |

LEDE 里的相关定义（已逐行核实）：

- `target/linux/rockchip/image/armv8.mk`
  ```make
  define Device/hinlink_opc-h69k
  $(call Device/hinlink_common)
    DEVICE_MODEL := OPC-H69K
    SOC := rk3568
    DEVICE_PACKAGES += kmod-hwmon-pwmfan kmod-mt7916-firmware kmod-usb-serial-option
  endef
  ```
- 设备树 `target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-opc-h69k.dts`
  （`compatible = "hinlink,opc-h69k", "rockchip,rk3568"`），共用基座 `rk3568-hinlink-opc.dtsi`
- U-Boot：`U-Boot/generic-rk3568`，镜像用 `pine64-img` 写入
  `generic-rk3568-idbloader.img`（扇区 0x40）与 `generic-rk3568-u-boot.itb`（扇区 0x4000）

### 关于 MINI / PRO / MAX 的差异

各源码树都**不区分** MINI/PRO/MAX —— 只有一个 profile，因为它们是
**同一块 PCB 搭配不同的 M.2 / mini-PCIe 模块**，模块在运行时枚举，
设备树里没有对应的模块节点。所以 **一个固件三种 SKU 通用**。

这也是本工程把 5G 的 **USB 与 PCIe 两条链路都编进去**的原因：

- 设备树只使能了 `pcie2x1`（WiFi 槽）、`pcie3x1`/`pcie3x2`（两个 2.5G 网卡）、USB 控制器
- RM520N-GL 到底从 M.2 座引出 USB 还是 PCIe/MHI，公开资料无法确定
- 两条链路共存无冲突（内核只绑定实际存在的那条），避免刷完机拨不上号再返工

| 链路 | 编入的驱动/工具 |
|---|---|
| USB（QMI/MBIM/NCM/RNDIS） | `kmod-usb-serial-option` `kmod-usb-serial-wwan` `kmod-usb-serial-qualcomm` `kmod-usb-net-qmi-wwan` `kmod-usb-net-cdc-mbim` `kmod-usb-net-cdc-ncm` `kmod-usb-net-rndis` `uqmi` `umbim` |
| PCIe / MHI | `kmod-pcie_mhi`（LEDE 自带的 Quectel 官方 PCIe MHI 驱动） |
| LuCI 界面 | `luci-proto-qmi` `luci-proto-mbim` `luci-proto-ncm` `luci-app-modemband` `luci-app-3ginfo-lite` `luci-app-sms-tool-js` `sms-tool` `picocom` |

---

## 3. 目录结构

```
openwrt-h69k-max/
├─ .github/workflows/build-h69k-max.yml   # 云编译工作流（核心）
├─ config/
│  ├─ h69k-max.config                     # 设备/镜像/无线/风扇/网卡 配置
│  └─ 5g-rm520n.config                     # RM520N-GL 5G 双栈配置
├─ scripts/build-cloud.ps1                # 一键推送 + 触发编译（Windows）
└─ README.md
```

---

## 4. 开始编译

### 方式 A：一键脚本（推荐）

需要先装 git；装 GitHub CLI 可以全自动建仓库并触发编译：

```powershell
winget install --id Git.Git -e --source winget
winget install --id GitHub.cli -e --source winget
gh auth login          # 首次使用需登录 GitHub

cd D:\AI\H69k\openwrt-h69k-max
.\scripts\build-cloud.ps1 -RepoName openwrt-h69k-max
```

### 方式 B：手动

```powershell
cd D:\AI\H69k\openwrt-h69k-max
git init ; git branch -M main
git add -A
git commit -m "H69K-MAX OpenWrt build"
git remote add origin https://github.com/<你的用户名>/openwrt-h69k-max.git
git push -u origin main
```

然后在网页上：**Actions → Build OpenWrt H69K-MAX → Run workflow**。

### 可调参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `kernel` | `6.18` | rockchip 目标只支持 **6.18（默认）/ 6.12（测试）**；MT7916 建议 6.18 |
| `rootfs_size_mb` | `4020` | rootfs 分区大小；32GB eMMC 可给到 `8192` |
| `make_release` | `true` | 发布到 Release（需 `contents: write`，工作流已声明） |

### 编译耗时

GitHub runner 4 核，首次全量编译（含 U-Boot、内核、工具链）约 **1.5–4 小时**。

> 工作流内置**配置符号校验**：`make defconfig` 之后会逐个检查本工程的
> `CONFIG_PACKAGE_*` 是否真的生效。包名写错或该源码树没有这个包，会**立刻报错**
> 并打印实际生效的相关配置，不会产出一个"看起来成功但缺驱动"的固件。

---

## 5. 产物

编译完成后在 **Release** 或 **Actions → Artifacts** 下载：

| 文件 | 用途 |
|---|---|
| `openwrt-<版本>-rockchip-armv8-hinlink_opc-h69k-squashfs-sysupgrade.img.gz` | **完整磁盘镜像**（含 U-Boot），用于写 eMMC / TF 卡 |
| `*.manifest` | 固件内包清单，核对驱动是否齐全 |
| `SHA256SUMS.txt` | 校验值，刷机前请核对 |
| `lede-commit.txt` | 本次编译对应的 LEDE commit，便于溯源 |

`sha256sum` 校验（Windows）：

```powershell
Get-FileHash -Algorithm SHA256 .\openwrt-*-hinlink_opc-h69k-squashfs-sysupgrade.img.gz
```

---

## 6. 刷机

> ⚠️ 刷机会清空 eMMC。开始前请备份原厂固件与重要数据。
> 建议**先用 TF 卡验证固件能正常启动**，确认无误后再刷 eMMC。

### 6.1 TF 卡启动（推荐先做，可逆）

1. 解压得到 `.img`
2. 用 **balenaEtcher** 或 `dd` 写入 TF 卡
   ```bash
   # Linux / WSL
   sudo dd if=openwrt-*-hinlink_opc-h69k-squashfs-sysupgrade.img of=/dev/sdX bs=4M status=progress conv=fsync
   ```
3. 断电，插入 TF 卡，上电
4. 不插 TF 卡时机器会从板载 eMMC 启动，所以这一步不会破坏原系统

默认管理地址 **192.168.1.1**（`CONFIG_TARGET_PREINIT_IP`）。
首次登录用 root；若默认无密码，请在 LuCI 里**立刻设置密码**。

### 6.2 刷入 eMMC（Maskrom 方式）

H69K 的 eMMC 刷写走 Rockchip Maskrom + RKDevTool：

1. 断电，**取出 TF 卡**
2. 按住机身侧面**针孔按键**不放，用 Type-C 线连接电脑
3. 松开按键，RKDevTool 状态应显示 **MASKROM**
4. 先加载 `H6XK-Boot-Loader.bin`（H66K/H68K/H69K **共用**同一 bootloader），点击**擦除 Flash**
5. 在「下载镜像」页指定：
   - boot 分区 → `H6XK-Boot-Loader.bin`
   - system 分区 → 解压后的 OpenWrt `.img`
6. 点击**执行**，等待完成
7. **恢复 12V ≥2A 正常供电**（不要用电脑 Type-C 供电跑系统），首次开机约 3–5 分钟

所需工具：`Rockchip_DriverAssistant`（驱动）+ `RKDevTool`。

### 6.3 已在跑 OpenWrt 时（in-place 升级）

设备当前已是 OpenWrt/LEDE 时，直接上传 sysupgrade 镜像即可：

```bash
# 上传到 /tmp 后
sysupgrade -T /tmp/openwrt-*-hinlink_opc-h69k-squashfs-sysupgrade.img.gz   # 先自检
sysupgrade -n /tmp/openwrt-*-hinlink_opc-h69k-squashfs-sysupgrade.img.gz   # 不保留配置升级
```

---

## 7. 刷完后的检查清单

```bash
# 1. 网卡：应看到 eth0(1G) / eth1 / eth2(2.5G)
ip -br link
ethtool eth1 | head -20

# 2. 无线 MT7916：应出现 mt7915e 与两个 radio
dmesg | grep -i mt7915
wifi status

# 3. 5G 模块枚举（USB 或 PCIe 链路二选一）
lsusb
lspci -nn
dmesg | grep -iE 'qmi|mbim|mhi|option|quectel'

# 4. 风扇（40°C 起转）
sensors 2>/dev/null || cat /sys/class/thermal/thermal_zone*/temp
cat /sys/class/hwmon/hwmon*/pwm1 2>/dev/null
```

在 LuCI 里拨号：**网络 → 接口 → 添加新接口**，协议选
*QMI 蜂窝 / MBIM 蜂窝 / NCM*（取决于模块实际枚举出的链路），
`/dev/cdc-wdm0` 或 `wwan0` 即为模块对应的设备。

> 5G 模块兼容性在不同固件/模块批次上仍有差异，这是社区已知问题；
> 本工程同时编入 QMI 与 MBIM 两套协议，就是为了让你在两个协议间切换排查，
> 而不必重新编译。

---

## 8. 常见问题

**Q: 为什么不用主线 OpenWrt / ImmortalWrt？**
A: 两者都只有 H66K/H68K 的设备定义，没有 H69K。H69K 的风扇温控、SATA 供电等
差异（`rk3568-opc-h69k.dts` 相对 H68K 多了 PWM 风扇 + 40°C 起转 + 5V SATA 供电轨）
只在 LEDE 里有。

**Q: 编译报 `CONFIG_PACKAGE_xxx 未生效`？**
A: 工作流把符号分成两级校验：
- **必须项**（目标平台、U-Boot、rkbin、MT7916 固件/驱动、PWM 风扇等）缺失会
  **直接失败**并打印实际生效的相关配置；
- **可选包**缺失只给出 `::warning::`，不会阻断编译。
看到可选包的 warning 就说明该包在这版源码树里不存在，按日志里的对照调整
`config/*.config` 即可（本工程默认选用的包名都已逐一核对过 LEDE master、
coolsnowwolf/packages 与 luci@openwrt-25.12 的 Makefile）。

**Q: 能编 AIC8800D80 的版本吗？**
A: 可以。LEDE 有 `package/kernel/aic8800`（源自 `radxa-pkg/aic8800`），
按网卡接线方式在 `config/h69k-max.config` 里加：
```make
CONFIG_PACKAGE_kmod-aic8800-pcie=y   # mini-PCIe/PCIe 接法
CONFIG_PACKAGE_aic8800-pcie-firmware=y
# 或 SDIO 接法：
# CONFIG_PACKAGE_kmod-aic8800-sdio=y
# CONFIG_PACKAGE_aic8800-sdio-firmware=y
```
注意：LEDE 的 H69K 设备定义**不会**自动选中这些包，必须手工添加。
你的 MAX 是 MT7916，用不上。

**Q: 编出来能用 `sysupgrade` 直接刷到原厂固件上吗？**
A: 原厂固件不是 OpenWrt，**不能**。原厂 → OpenWrt 走 §6.2 的 Maskrom 方式，
或先 §6.1 用 TF 卡启动验证。

---

## 9. 参考来源

- LEDE 设备定义（H69K）：<https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/rockchip/image/armv8.mk>
- LEDE 镜像/U-Boot 写入逻辑：<https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/rockchip/image/Makefile>
- LEDE U-Boot 设备表：<https://raw.githubusercontent.com/coolsnowwolf/lede/master/package/boot/uboot-rockchip/Makefile>
- 上游 H69K 配置样例（交叉核对用）：<https://raw.githubusercontent.com/smallprogram/OpenWrtAction/main/config/leanlede_config/H69K.config>
- 主线 OpenWrt 仅有 H66K/H68K 的提交：<https://git-03.infra.openwrt.org/openwrt/openwrt/commit/?id=cf84e8ee8668623e267f778a5dd090dfad18de37>
- H69K 硬件拆解（RTL8125BG / MT7916 / MAX 与 MAX+ 差异）：<https://www.smyz.net/luyouqi/19693.html>
- eMMC Maskrom 刷机说明（H66K/H68K/H69K/H28K）：<https://www.wifilu.com/2447.html>
- 社区 H69K 项目（含厂商 DTS 与刷机笔记）：<https://github.com/jjjjn9595-star/h69k>
- KWRT + 官方 OpenWrt 25.12 的 H69K 双栈 5G 配置参考：<https://github.com/dannyqin/h69k-kwrt-custom>
