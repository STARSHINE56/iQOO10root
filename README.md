# iQOO 10 刷 KernelSU Root 完整教程

> 适用机型：**iQOO 10（V2217A / PD2217B）**
> 实测系统：**PD2217B_A_16.5.17.1.W10**（Android 16 / OriginOS，内核 5.10.246-gki-g02b2e21da816）
> 实测日期：2026-11-03
> 目标：在不影响日常使用、**不清除数据**的前提下，给 iQOO 10 刷入 **KernelSU（官方版）** 永久 root

---

## 目录

- [0. 先看这里：风险与底线](#0-先看这里风险与底线)
- [1. 必须搞懂的几个概念](#1-必须搞懂的几个概念)
- [2. 准备工作](#2-准备工作)
- [3. 第一阶段：确认现状（非常重要）](#3-第一阶段确认现状非常重要)
- [4. 第二阶段：拿到与当前系统匹配的原厂 boot](#4-第二阶段拿到与当前系统匹配的原厂-boot)
- [5. 第三阶段：用 KernelSU 给 boot 打补丁](#5-第三阶段用-kernelsu-给-boot-打补丁)
- [6. 第四阶段：刷入并验证](#6-第四阶段刷入并验证)
- [7. 第五阶段：收尾与清理](#7-第五阶段收尾与清理)
- [8. 救砖：出问题怎么救](#8-救砖出问题怎么救)
- [9. 常见问题与踩坑记录](#9-常见问题与踩坑记录)
- [10. 我的实测数据（可对照）](#10-我的实测数据可对照)
- [11. 日常注意事项清单](#11-日常注意事项清单)

---

## 0. 先看这里：风险与底线

### 0.1 一句话总结

> **iQOO 10 可以刷 root，但前提是：必须拿到一份与你当前系统版本完全匹配的原厂 boot.img。**
> 拿不到之前，**一个字节都不要往 boot 分区里写**。

### 0.2 为什么这么说（血的教训）

vivo / iQOO 有一个所有玩机党都必须知道的区别：

| 对比项 | 小米 / 一加 等 | vivo / iQOO |
|---|---|---|
| 分区布局 | A/B 双槽，`boot_a` + `boot_b` | **A-only 单槽**，只有 `boot` |
| 刷错 boot | 切到另一个槽就能救回来 | **没有备份槽，直接变砖** |
| 9008 / EDL 救砖 | 有公开 firehose，能自救 | **firehose 需要签名，拿不到** |
| 砖了的后果 | 自己能恢复 | **只能走售后换主板** |

而且实测确认：iQOO 10 的 bootloader **不允许回读 boot 分区**（我试了十几种 `fastboot oem` 命令、`fastboot fetch`，全部返回 unknown command / not supported），所以你**没有办法从手机里把原厂 boot 导出来**。

**结论：原厂 boot.img 只能从官方完整固件包里取，取不到就是不能刷。**

### 0.3 底线五条

1. **没拿到匹配版本的原厂 boot.img 之前，绝不刷 boot**
2. **绝不执行 `fastboot flashing lock`（回锁）**，vivo 回锁会校验签名，没签名就是砖
3. **绝不 OTA 系统更新**，更新会覆盖 boot，root 直接没，运气差开不了机
4. **不要刷别人分享的 boot.img**，哪怕型号一样、版本号差一点点也可能内核不匹配
5. **操作前保持 50% 以上电量**，刷机中途没电 = 砖

### 0.4 本教程已验证可行

本教程不是纸上谈兵，是我在真机上从头走通、并且最终 root 成功的完整记录（包括走过的弯路）。你可以直接按步骤来。

---

## 1. 必须搞懂的几个概念

### 1.1 为什么刷 root 要动 boot 分区

root 的本质是**让系统在内核启动阶段就带上提权能力**。当前主流的三种方案：

| 方案 | 原理 | 对 iQOO 10 是否可行 |
|---|---|---|
| **Magisk** | 改 boot 的 ramdisk，注入 magiskinit | 可行（传统方式） |
| **KernelSU（官方版）** | 往 boot 的 ramdisk 里塞一个 `kernelsu.ko` 内核模块，由改过的 init 在开机时加载 | ✅ **本教程采用** |
| **KernelSU 的 GKI 内核替换模式** | 用官方预编译内核整个替换掉原内核 | ❌ **绝对不要用**，会把 vivo 的定制内核换掉，vendor 驱动模块全部加载失败 |

**关键点**：KernelSU 的 **LKM 模式（Loadable Kernel Module）只往 ramdisk 里加东西，内核本体一个字节都不动**。这是它安全的原因——万一失败，系统照常能启动，只是没有 root。

### 1.2 KMI 是什么

KMI = Kernel Module Interface，谷歌 GKI 计划给内核模块定的"接口标准"。

KernelSU 在打补丁时需要你选一个 KMI，因为不同 KMI 的模块接口不一样：

```
android12-5.10
android13-5.10
android13-5.15
android14-5.15
android14-6.1
android15-6.6
```

iQOO 10 的选择：**`android12-5.10`**

理由：
- iQOO 10 是 **2022 年以 Android 12 首发**的机型
- 内核是 5.10.246，来自 android12-5.10 GKI 分支
- vivo 在系统跨版本升级（12 → 16）时**不会重构内核**，只更新 vendor 驱动，所以 KMI 一直停留在出厂时的 android12-5.10

### 1.3 vermagic 是什么，以及一个反直觉的结论

`vermagic` 是内核模块里记录的"我是给哪个内核编译的"标记。

我的实测环境：

| 对象 | vermagic |
|---|---|
| 你的内核 | `5.10.246-gki-g02b2e21da816` |
| KernelSU 打包的 kernelsu.ko | `5.10.252-dirty` |

**看到这个差异时，我一度判断"模块加载不了，root 会失败"——但实测证明这个判断是错的**：官方 KernelSU v3.3.1 的 5.10.252 模块，在 5.10.246 的内核上**照样 insmod 成功**。

原因：vivo 这份内核允许跨 minor 版本加载 LKM（同为 android12-5.10 GKI 分支，KMI 符号一致）。

**所以：vermagic 不一致不代表一定失败，以实际 `insmod` 结果为准，不要自己吓自己。**

---

## 2. 准备工作

### 2.1 硬件与软件清单

**必需：**

- iQOO 10 手机（电量 50%+）
- Windows 电脑（本教程用 Windows 演示，Linux/macOS 命令基本一致）
- 一根**能传数据的** USB 线（很多充电线只能充电）
- `adb` + `fastboot` 工具

**需要下载：**

| 文件 | 用途 | 获取方式 |
|---|---|---|
| `platform-tools` | adb / fastboot | Google 官方 |
| `KernelSU_v3.3.1.apk` | 官方管理器 | KernelSU GitHub Releases |
| **与你系统版本号完全一致的官方完整固件包** | 提取原厂 boot.img | 见 4.1 |

### 2.2 安装 adb / fastboot

**Windows：**

1. 下载 `platform-tools-latest-windows.zip`
2. 解压到比如 `D:\root\adb\`
3. 把该目录加入系统环境变量 PATH

**验证：**

```bash
adb version
fastboot --version
```

**提示**：如果你用 Git Bash / MSYS2（本教程就是），每次开新终端都要先执行：

```bash
export PATH="/d/root/adb:$PATH"
export MSYS_NO_PATHCONV=1
```

> ⚠️ **`MSYS_NO_PATHCONV=1` 这一行在 Git Bash 里是必须的！**
> 不加的话，`adb pull /storage/emulated/0/xxx` 里的路径会被 MSYS 自动改写成 Windows 路径，然后报 `failed to stat remote object`。这个坑我踩过，浪费了很久。

### 2.3 手机开启开发者选项与解锁

**第一步：开 USB 调试**

1. 设置 → 关于手机 → 连续点击"版本号"7 次 → 开启开发者模式
2. 设置 → 系统管理 → 开发者选项 → 打开 **USB 调试**

**第二步：确认 bootloader 已是解锁状态**

```bash
adb reboot bootloader
fastboot oem device-info
```

正常应看到：

```
(bootloader) Verity mode: true
(bootloader) Device unlocked: true
(bootloader) Device critical unlocked: true
```

> 如果 `Device unlocked: false`，说明还没解锁。
> vivo/iQOO 的官方解锁途径是 **"深度测试"**（vivo 社区申请，有时间和名额限制），解锁后设备会显示 orange 状态和开机警告。**本教程不涉及解锁步骤**，假设你已解锁。

**第三步：回到系统**

```bash
fastboot reboot
```

---

## 3. 第一阶段：确认现状（非常重要）

**这一步千万不要跳过。** 后面所有操作都依赖这里采集的数据。

### 3.1 采集系统与内核信息

```bash
adb devices
# 应输出: 10ACAN0UTQ001UA   device  （你的序列号会不同）

adb shell getprop ro.build.display.id
adb shell getprop ro.vivo.os.version
adb shell getprop ro.vivo.hardware.version
adb shell getprop ro.boot.verifiedbootstate
adb shell cat /proc/version
```

我的实测结果（供对照）：

```
PD2217B_A_16.5.17.1.W10          ← 系统版本号，记下来！
16.0
PD2217MA
orange                            ← bootloader 已解锁
Linux version 5.10.246-gki-g02b2e21da816 (build-user@build-host) ... #1 SMP PREEMPT ...
```

**把这两条抄在纸上：**

- 系统版本：`PD2217B_A________________`（你的）
- 内核版本：`5.10.246-gki-______________`（你的）

### 3.2 确认分区布局

```bash
adb shell ls -l /dev/block/by-name/ | grep -E "boot|recovery"
```

iQOO 10 实测只有：

```
boot          -> sde13
vendor_boot   -> ...
vm-bootsys    -> ...
```

**确认两件事：**

1. **没有 `boot_a` / `boot_b`** → 说明是 A-only 单槽，**没有退路**
2. 分区大小是 `0x6000000`（= 100,663,296 字节 = 96MB）

```bash
fastboot getvar partition-size:boot
# 应输出: partition-size:boot:  0x6000000
```

> 这个大小要记住！后面导出的 boot.img 必须正好是 100,663,296 字节。

### 3.3 检查手机上有没有历史 boot 文件

如果你以前折腾过，`Download` 目录里可能有旧 boot。**全部作废，不要用**：

```bash
adb shell ls -la /storage/emulated/0/Download/ | grep -i -E "boot|patched"
adb shell ls -la /storage/emulated/0/root/ 2>/dev/null
```

我的实测：手机里有 3 份旧 boot，内核分别是 `g8c3d0d7851ff`（更老）、`g31c52d0ba91c`（15.1 的），**全部与当前 17.1 系统不匹配**。用错了就是砖。

**关键判断方法**——用 grep 从文件里提取内核版本号：

```bash
grep -a -o -m1 "Linux version 5\.10\.246-gki-[a-z0-9]*" 你的boot.img
```

结果必须等于你 3.1 步记下的内核版本，**一个字都不能差**。

> ⚠️ 注意：手机重启后如果还没解锁屏幕，`/data` 是加密状态，`/storage/emulated/0` 会是空的。
> 所以 `ls` 之前**必须先点亮屏幕、解锁手机**。

### 3.4 关于"从手机 dump 原厂 boot"的死路

我花了很长时间验证：**iQOO 10 无法从手机导出原厂 boot**。以下是全部失败记录，你不要再试：

| 命令 | 结果 |
|---|---|
| `fastboot fetch boot` | Device does not support fetch command |
| `fastboot getvar max-fetch-size` | GetVar Variable Not found |
| `fastboot oem help` | unknown command |
| `fastboot oem list` | unknown command |
| `fastboot oem dump` | unknown command |
| `fastboot oem backup` | unknown command |
| `fastboot oem read` / `read_partition` | unknown command |
| `fastboot oem dump:boot` | unknown command |
| `fastboot oem sha256` | unknown command |
| `fastboot oem partition-info` | unknown command |
| `fastboot oem dumpgpt` | unknown command |
| `fastboot bbk` / `fastboot vivo` | usage: unknown command |

**唯一能用的是 `fastboot oem device-info`**（只返回解锁状态，不能读数据）。

至于 `adb shell dd if=/dev/block/sde13`？shell 用户是 `uid=2000`，没有读块设备的权限，直接 Permission denied。

**所以：放弃 dump，去固件包里拿。** 见下一节。

---

## 4. 第二阶段：拿到与当前系统匹配的原厂 boot

### 4.1 找到官方完整固件包

**唯一正确的来源：你手机上系统更新留下的 OTA 完整包。**

vivo/iQOO 的完整固件包（全量包）是 AOSP 格式的 `xxx.zip`，通常 9~10GB。

**怎么找：**

1. 手机文件管理里搜索 `*.zip`，或者看这几个目录：
   - `/storage/emulated/0/`
   - `/storage/emulated/0/Download/`
   - `/storage/emulated/0/ota/`
2. 文件名通常是一长串数字 + `.zip`（比如我的是 `202609181938278927e7f9835976f6c89de34891724461.zip`）
3. 大小约 9~10GB
4. 解开后看 `META-INF/com/android/metadata`

**怎么验证这个包是不是"你当前系统"的包：**

```bash
cat META-INF/com/android/metadata | grep -E "post-version|post-build|post-sdk"
```

实测我的 17.1 包内容：

```
post-version=PD2217_A_16.5.17.1.W10.V000L1     ← 必须与你 3.1 记的系统版本一致
post-build=vivo/PD2217/PD2217:16/BP2A.250605.031.A3/compiler260918151806:user/release-keys
post-sdk-level=36
post-security-patch-level=2026-09-01
anti-rollback-level=0                          ← 0 表示不会触发防回滚
```

> **找不到包怎么办？**
> - 去 vivo 官网服务支持页下载对应型号固件
> - 去 vivo 社区/售后要
> - **绝对不要**用别的版本号的包，哪怕只差一个小版本

### 4.2 从固件包里提取 boot.img

固件包是 AOSP block OTA 格式，`boot.img` 是**直接以文件形式**放在包里的（没有被压成 `.new.dat`），所以直接解压即可。

**Windows 直接用 7-Zip / WinRAR 打开 zip，把 `boot.img` 拖出来就行。**

**用命令行（Python，跨平台）：**

```python
# 只需标准库，无需第三方包
import zipfile
with zipfile.ZipFile(r"D:\root\ota\PD2217_165171.zip") as z:
    for n in z.namelist():
        if n.endswith("boot.img") and "vendor" not in n:
            with z.open(n) as f, open(r"D:\root\ota\e171\boot.img", "wb") as o:
                o.write(f.read())
            print("提取:", n)
```

包里的关键文件：

```
boot.img                    ← 我们要的（原厂内核+ramdisk）
firmware-update/vendor_boot.img
firmware-update/dtbo.img
firmware-update/vbmeta.img
firmware-update/vbmeta_system.img
firmware-update/NON-HLOS.bin   (基带)
firmware-update/abl.elf        (引导)
firmware-update/tz.mbn         (安全区)
firmware-update/recovery.img
system.new.dat / system.new.dat.1~.15 ...
```

**只需要 `boot.img`，其他都不要动。**

### 4.3 三重校验（必做）

```bash
# ① 文件大小必须是分区大小
ls -l boot.img
# 必须是 100663296 字节（96MB）

# ② 内核版本必须完全一致
grep -a -o -m1 "Linux version 5\.10\.246-gki-[a-z0-9]*" boot.img
# 必须等于你 3.1 步记下的内核版本

# ③ 记录 MD5，后面每一步都要对
md5sum boot.img
```

我的实测：

```
100663296 字节
内核: 5.10.246-gki-g02b2e21da816   ✅ 与系统一致
MD5:  e2ef812b46c3ec064179add293e394e0
```

**三条全部通过才能继续。任何一条不对，立刻停下。**

### 4.4 备份！备份！备份！

把这份原厂 boot.img 复制三份，存在不同地方：

```
D:\root\ota\e171\boot.img              ← 工作目录
U盘\iQOO10_backup\boot_orig.img        ← 移动介质
网盘\iQOO10_backup\boot_orig.img       ← 云端
```

**这份文件就是你唯一的命。丢了它，以后出任何问题都只能走售后。**

### 4.5 顺手把它推到手机上备份

```bash
export MSYS_NO_PATHCONV=1
adb push boot.img /sdcard/Download/boot_16.5.17.1_orig.img
adb shell md5sum /sdcard/Download/boot_16.5.17.1_orig.img
# 必须与 4.3 的 MD5 一致
```

---

## 5. 第三阶段：用 KernelSU 给 boot 打补丁

### 5.1 安装 KernelSU 管理器

推荐用**官方版 KernelSU**（`me.weishu.kernelsu`）：

1. 下载 `KernelSU_v3.3.1.apk`（GitHub Releases）
2. 安装到手机

> **为什么不用 KernelSU Next？**
> 我个人实测两种都试过，**官方 v3.3.1 一次成功**。Next（`com.rifsxd.ksunext`）首次刷入后出现过模块没加载的情况，重启后才正常。两者内核模块版本都基于 5.10.252 基线，功能都能用，但**只用其中一个，不要两个都装**（会抢 root 授权）。

### 5.2 在手机上打补丁

**注意：这一步必须在手机上做，PC 端做不了**（KernelSU 的补丁逻辑集成在 App 里）。

1. 先把原厂 boot 放到手机：
   ```bash
   adb push boot.img /sdcard/Download/boot_16.5.17.1_orig.img
   ```
2. 打开 **KernelSU** App
3. 首页会显示 **"未安装"**（正常，还没刷入）
4. 点 **"安装"** / **"Install"**
5. 选择 **"选择并修补一个文件"** / **"Select and Patch a File"**
6. 进入文件选择器 → `Download` → 选中 `boot_16.5.17.1_orig.img`
7. **弹出 KMI 选择时，选 `android12-5.10`**（理由见 1.2）
8. 等待处理，看日志

**成功时会看到这样的日志：**

```
  _  __                    _ ____  _   _ 
 | |/ /___ _ __ _ __   ___| / ___|| | | |
 | ' // _ \ '__| '_ \ / _ \ \___ \| | | |
 | . \  __/ |  | | | |  __/ |___) | |_| |
 |_|\_\___|_|  |_| |_|\___|_|____/ \___/ 

- Bootdevice: /data/data/me.weishu.kernelsu/cache/boot.img
- Preparing assets
- Unpacking boot image
- KMI: android12-5.10
- Adding KernelSU LKM
- Adding bundled LKM config
- Repacking boot image
- Output file is written to
- /storage/emulated/0/Download/kernelsu_patched_20261103_112911.img
- Done!
```

输出文件在 `/storage/emulated/0/Download/`。

### 5.3 打补丁后，补丁到底改了什么

这一步值得知道，方便你判断补丁是否正常。补丁后的 boot.img **内核完全没变**，只改了 ramdisk，具体是：

| 变化 | 说明 |
|---|---|
| 新增 `kernelsu.ko`（约 380KB） | KernelSU 的内核模块本体 |
| 新增 `ksu_config`（内容 `bundled=1`） | 标记使用内置模块 |
| `init`（原 2.7MB）→ 改名为 `init.real` | 保留原 init |
| 新 `init`（约 600KB） | KernelSU 的加载器：先 insmod kernelsu.ko，再 exec 原 init.real |

**内核本体、cmdline、fstab 全都没动**，这就是为什么"补丁失败也只是没 root，不会变砖"。

### 5.4 拉回 PC 做二次校验（强烈建议）

```bash
export MSYS_NO_PATHCONV=1
adb pull /storage/emulated/0/Download/kernelsu_patched_20261103_112911.img ./boot_patched.img
```

**校验三条：**

```bash
# ① 大小必须还是 100663296
ls -l boot_patched.img

# ② 内核版本必须与原厂一致（证明内核没被替换）
grep -a -o -m1 "Linux version 5\.10\.246-gki-[a-z0-9]*" boot_patched.img

# ③ 必须能找到 kernelsu 模块
grep -a -o -i -m3 "kernelsu" boot_patched.img | sort -u
# 应看到 KernelSU、kernelsu.ko
```

我的实测：

```
100663296 字节
内核: 5.10.246-gki-g02b2e21da816    ✅ 没变
含: KernelSU / kernelsu.ko          ✅
MD5: 1cfa59d12434e16523bce81589c1d8b0
```

---

## 6. 第四阶段：刷入并验证

### 6.1 刷入

```bash
export PATH="/d/root/adb:$PATH"
export MSYS_NO_PATHCONV=1

# ① 进 bootloader
adb reboot bootloader
sleep 10

# ② 确认设备在，且是解锁状态
fastboot devices
fastboot oem device-info | grep -i unlock
# 应看到 Device unlocked: true / Device critical unlocked: true

# ③ 刷 boot
fastboot flash boot boot_patched.img

# ④ 重启
fastboot reboot
```

**正常输出：**

```
Sending 'boot' (98304 KB)                          OKAY [  2.233s]
Writing 'boot'                                     OKAY [  0.259s]
Finished. Total time: 2.554s
Rebooting                                          OKAY [  0.002s]
```

### 6.2 验证 root 是否真的生效

**第一次开机可能比较慢（1~3 分钟），耐心等。**

**第一层验证：PC 端看内核模块（客观证据）**

```bash
# 等设备连上
for i in $(seq 1 20); do adb get-state 2>/dev/null | grep -q device && break; sleep 6; done

# 看内核模块是否加载
adb shell cat /proc/modules | grep -i kernelsu
```

**成功的样子：**

```
kernelsu 212992 2 - Live 0x0000000000000000 (O)
```

`Live` 就是加载成功。**看不到就是没成功**（此时系统仍能正常开机，只是没 root）。

**第二层验证：手机上确认管理器状态**

打开 KernelSU App，首页应显示 **"工作中"** / **"已安装"**。

**第三层验证：实际授权**

打开 MT管理器 / Termux / Shizuku 等需要 root 的 App，应当弹出 KernelSU 授权框，允许后执行：

```bash
su
id
# 应输出 uid=0(root)
```

> ⚠️ **注意：`adb shell` 里执行 `su` 会提示 `su: inaccessible or not found`，这是正常的！**
> KernelSU **不会**给 adb shell 提供 su（这是安全设计），root 只授予 App。不要因此以为没成功。

### 6.3 状态核对表

刷完后对照检查：

- [ ] `adb shell getprop ro.build.display.id` 系统版本没变
- [ ] `adb shell cat /proc/version` 内核版本没变
- [ ] `adb shell cat /proc/modules | grep kernelsu` 有 `Live`
- [ ] KernelSU App 显示"工作中"
- [ ] 某个 App 能成功申请到 root
- [ ] 数据还在（照片、微信记录都正常）

**全部打勾 = 成功。**

---

## 7. 第五阶段：收尾与清理

### 7.1 只保留一个管理器

如果你之前装过其他 root 管理器（KernelSU Next、Magisk 等），**必须只留一个**。

```bash
# 查看装了哪些
adb shell pm list packages | grep -i -E "kernelsu|ksunext|magisk"

# 卸载多余的（示例：KernelSU Next）
adb shell pm uninstall com.rifsxd.ksunext
# 如果报错，用：
adb shell pm uninstall --user 0 com.rifsxd.ksunext

# 确认已卸载
adb shell dumpsys package com.rifsxd.ksunext
# 应输出: Unable to find package
```

> 卸载旧管理器**不会**掉 root，因为 root 在内核侧，是从 boot 加载的。

### 7.2 清理手机上无用的旧文件

```bash
adb shell "cd /storage/emulated/0/Download && rm -f 旧的补丁镜像.img 旧的boot.img 旧日志.log"
```

**必须保留的：**

- `boot_<你的版本>_orig.img` — 原厂 boot，救命用
- `kernelsu_patched_<时间>.img` — 当前正在用的补丁（和已刷入的一致）

### 7.3 归档备份清单

以下文件**永远不要删**：

| 文件 | 说明 |
|---|---|
| 原厂 `boot.img` | md5 记下来，救砖唯一依靠 |
| 当前在用的补丁 `boot_patched.img` | 掉了 root 直接重刷 |
| 完整固件包 zip（可选） | 很占空间，但有它最安心 |

---

## 8. 救砖：出问题怎么救

### 8.1 情况一：刷完后 root 没生效，但系统能正常开机

**最常见、也最安全的情况。**

```bash
adb reboot bootloader
sleep 10
fastboot flash boot 原厂boot.img      # 刷回原厂
fastboot reboot
```

或者换个 KMI 重新打补丁再来一次：
- `android12-5.10` 失败 → 试 `android13-5.10`

### 8.2 情况二：卡在开机动画 / 无限重启

**别慌，此时 fastboot 通常还能进。**

1. 长按电源键 10~15 秒强制关机
2. **同时按住 音量减 + 电源键** 进入 bootloader（vivo/iQOO 一般是这个组合）
3. 电脑上确认：
   ```bash
   fastboot devices
   ```
4. 刷回原厂 boot：
   ```bash
   fastboot flash boot 原厂boot.img
   fastboot reboot
   ```

**只要能进 fastboot，就一定能救回来。**

### 8.3 情况三：连 fastboot 都进不去

这时只能：
- 尝试 **vivo 官方"恢复模式"**（音量加 + 电源键）
- 送 **vivo 售后**（说明是系统故障，别说刷机）

**这就是为什么原厂 boot.img 和"不要回锁"这两条底线这么重要。**

### 8.4 验证救砖是否成功

```bash
adb shell getprop ro.build.display.id     # 系统版本正常
adb shell cat /proc/modules | grep kernelsu   # 应该没有（root 没了，正常）
```

系统能正常用，就说明救回来了。

---

## 9. 常见问题与踩坑记录

### 9.1 连接类

**Q: `adb devices` 显示空 / `no devices found`**

- 检查 USB 线（要能传数据的）
- 手机上重新确认 USB 调试已开
- **手机屏幕必须点亮并解锁**（锁屏状态下 adb 会掉）
- 换 USB 口，优先插主板后置 USB 3.0

**Q: `adb pull` 报 `failed to stat remote object`**

**这是 Git Bash / MSYS2 的路径自动转换问题。** 必须加：

```bash
export MSYS_NO_PATHCONV=1
```

**Q: `/storage/emulated/0` 里 `ls` 是空的**

手机刚重启，`/data` 还加密着没解锁。**先点亮屏幕解锁手机**，再 ls。

### 9.2 刷机类

**Q: 打补丁时 KMI 选哪个？**

iQOO 10（5.10.246 内核，Android 12 首发）→ **`android12-5.10`**。失败再试 `android13-5.10`。

**Q: vermagic 不匹配（5.10.252 vs 5.10.246）会失败吗？**

**不会。** 实测能正常加载。这是本教程最重要的反直觉结论。

**Q: 刷入后 `/proc/modules` 里看不到 kernelsu**

- 先等 1~2 分钟（开机完成后再看）
- **重启一次**（我第一次就遇到这个，重启后模块出现了）
- 还是不行 → 换 KMI 重新打补丁

**Q: `adb shell su` 提示 not found**

正常。KernelSU 不向 adb shell 提供 root，只授予 App。

**Q: 能不能用 KernelSU 的 "GKI 内核替换" 模式？**

**不能！** 会把 vivo 定制内核整个换掉，vendor 驱动模块（wifi、相机、基带）全部加载失败，手机基本废掉。**只能用 LKM 模式**。

### 9.3 以后使用类

**Q: 系统推送更新了，能更吗？**

**不能。** OTA 会覆盖 boot 分区：
- 轻则 root 丢失
- 重则系统起不来（新系统 + 旧 boot 不匹配）

真要更新：先刷回原厂 boot → 更新 → 重新走一遍本教程。

**Q: 能回锁（`fastboot flashing lock`）吗？**

**绝对不能。** vivo 回锁会校验镜像签名，你的 boot 是改过的，签名不过 → 直接砖，且没有 firehose 自救。

**Q: 想换管理器怎么办？**

用新管理器重新打补丁 → 刷入 → 确认"工作中" → 卸载旧管理器。
（本教程就是这么从 KernelSU Next 换到官方 KernelSU 的。）

---

## 10. 我的实测数据（可对照）

### 10.1 设备信息

| 项目 | 值 |
|---|---|
| 型号 | iQOO 10（V2217A） |
| 硬件码 | PD2217B / PD2217MA |
| 系统 | `PD2217B_A_16.5.17.1.W10` |
| Android | 16（OriginOS，sdk 36） |
| 内核 | `5.10.246-gki-g02b2e21da816`（2026-09-15 编译） |
| 分区 | A-only 单槽，`boot` → `sde13`，大小 `0x6000000` |
| 解锁状态 | `orange`，unlocked: true，critical unlocked: true |

### 10.2 镜像文件对照表

| 文件 | 大小 | MD5 | 说明 |
|---|---|---|---|
| 原厂 boot | 100,663,296 | `e2ef812b46c3ec064179add293e394e0` | 救命镜像 |
| KernelSU Next 补丁 | 100,663,296 | `a69bd444a5a4e2fbc99827826bd7c4f0` | 备用 |
| **官方 KSU 补丁** | 100,663,296 | `1cfa59d12434e16523bce81589c1d8b0` | **当前在用** |

### 10.3 补丁后 ramdisk 内容对比

| 文件 | 原厂 | 补丁后 |
|---|---|---|
| `init` | 2,739,792 | 603,008（KSU 加载器） |
| `init.real` | — | 2,739,792（原 init） |
| `kernelsu.ko` | — | 379,016 |
| `ksu_config` | — | 9（`bundled=1`） |

### 10.4 最终状态

```
/proc/modules:  kernelsu 212992 2 - Live (O)     ✅
系统版本:        PD2217B_A_16.5.17.1.W10          ✅ 未变
内核版本:        5.10.246-gki-g02b2e21da816       ✅ 未变
数据:            完好，未清除                      ✅
管理器:          官方 KernelSU v3.3.1，显示"工作中" ✅
```

---

## 11. 日常注意事项清单

### 11.1 绝对不要做的事

| ❌ 禁止 | 原因 |
|---|---|
| OTA 系统更新 | 覆盖 boot，root 丢失，可能开不了机 |
| `fastboot flashing lock` 回锁 | 签名校验不过，直接砖，无自救手段 |
| 刷别人的 boot.img | 版本/内核不匹配 = 砖 |
| 刷 `vbmeta` / `abl` / `tz` 等分区 | 引导链破坏，砖 |
| 用 KernelSU 的 GKI 内核替换模式 | vendor 驱动全废 |
| 同时装多个 root 管理器 | 抢授权，易出怪问题 |
| 电量低于 30% 时刷机 | 中途断电 = 砖 |
| 删除电脑上的原厂 boot.img | 失去唯一自救手段 |

### 11.2 建议做的事

| ✅ 建议 | 原因 |
|---|---|
| 原厂 boot.img 存 3 份（本地+U盘+网盘） | 唯一救命文件 |
| md5 全部记录下来 | 校验用，判断文件是否损坏 |
| 每次刷前先 `fastboot oem device-info` | 确认解锁状态正常 |
| 刷前把重要数据备份到电脑 | 虽然本流程不清数据，但保险 |
| 保持一个能用的补丁镜像在手机上 | 掉了 root 直接重刷，不用重新打补丁 |
| 记录当前系统版本号 | 以后 OTA 后要重新匹配 boot |

### 11.3 系统更新时怎么办

vivo 推新系统时，正确流程是：

1. **先刷回原厂 boot**（这样 OTA 校验能过）
2. 完成 OTA 更新
3. 记录新系统版本号和内核版本
4. **重新找新版本固件包，提取新的原厂 boot.img**
5. 重新打补丁、重新刷入

**注意：新系统可能无法用旧的 boot.img，必须重新匹配。**

### 11.4 掉 root 了怎么办

先判断是不是 OTA 导致的：

```bash
adb shell cat /proc/modules | grep kernelsu     # 空 = 没 root
adb shell getprop ro.build.display.id           # 看系统版本有没有变
```

- **系统版本没变** → 直接重刷手上那份补丁 boot.img 即可
- **系统版本变了** → 说明 OTA 过了，必须重新按教程走一遍（找新版本原厂 boot）

---

## 附录 A：完整命令速查

```bash
# ===== 环境 =====
export PATH="/d/root/adb:$PATH"
export MSYS_NO_PATHCONV=1

# ===== 信息采集 =====
adb devices
adb shell getprop ro.build.display.id
adb shell getprop ro.boot.verifiedbootstate
adb shell cat /proc/version
adb shell ls -l /dev/block/by-name/ | grep boot
fastboot getvar partition-size:boot
fastboot oem device-info

# ===== 校验 boot 镜像 =====
ls -l boot.img                                    # 必须 100663296
grep -a -o -m1 "Linux version 5\.10\.246-gki-[a-z0-9]*" boot.img
md5sum boot.img

# ===== 推送到手机打补丁 =====
adb push boot.img /sdcard/Download/boot_orig.img
# → 手机上打开 KernelSU → 安装 → 选择并修补一个文件 → 选 android12-5.10

# ===== 拉回并校验补丁 =====
adb pull /storage/emulated/0/Download/kernelsu_patched_xxx.img ./boot_patched.img
ls -l boot_patched.img
grep -a -o -m1 "Linux version 5\.10\.246-gki-[a-z0-9]*" boot_patched.img
grep -a -o -i -m3 "kernelsu" boot_patched.img | sort -u

# ===== 刷入 =====
adb reboot bootloader
sleep 10
fastboot devices
fastboot oem device-info | grep -i unlock
fastboot flash boot boot_patched.img
fastboot reboot

# ===== 验证 =====
adb shell cat /proc/modules | grep -i kernelsu      # 要有 Live
adb shell getprop ro.build.display.id               # 系统版本没变
# 手机上看 KernelSU 显示"工作中"

# ===== 救砖（刷回原厂）=====
adb reboot bootloader
sleep 10
fastboot flash boot 原厂boot.img
fastboot reboot

# ===== 清理旧管理器 =====
adb shell pm uninstall com.rifsxd.ksunext
adb shell dumpsys package com.rifsxd.ksunext
```

---

## 附录 B：boot.img 结构笔记（进阶）

iQOO 10 的 boot.img 是 **vivo 定制的 AOSP boot header**，跟标准 Android boot image 头有差异，直接套标准解析器会解析失败（`page_size` 字段是 0）。实测结构：

| 偏移 | 内容 | 实测值 |
|---|---|---|
| 0x00 | magic | `ANDROID!` |
| 0x08 | kernel_size | 52,062,676 |
| 0x0C | ramdisk_size | 1,479,636（原厂）/ 1,975,388（补丁） |
| 0x14 | header_size | 1584 |
| 0x28 | header_version | 4 |
| 0x24 | page_size 字段 | **0（假的，实际是 4096）** |

实际布局：

```
0x0000  header (1584 字节)
0x1000  kernel 起始（52,062,676 字节，ARM64 Image，magic 在 +0x38）
0x31A8000  ramdisk 起始（lz4 legacy 帧，magic 02 21 4C 18）
...
```

ramdisk 解压后是 cpio newc 格式，字段偏移：`filesize@54`、`namesize@94`、`name@110`。

补丁前后 ramdisk 的差异就是 5.3 表格里那四项。

---

## 附录 C：致谢与声明

- 本教程基于 2026-11-03 在 iQOO 10（PD2217B，16.5.17.1）真机上的完整实测
- 所有命令、版本号、MD5 均为实测数据
- KernelSU 项目：https://github.com/tiann/KernelSU
- **刷机有风险，变砖无 firehose 可救。请确认你真的看懂第 0 节再动手。**

---

**最后更新：2026-11-03**
