# AI 执行指令包 —— iQOO 10 (PD2217B) 刷 KernelSU Root

> **这份文件是写给「接手的 AI」看的。**
> 把整个仓库丢给任意 AI（Claude / GPT / Gemini / 本地模型），让它**先完整读完本文件**，
> 再按下面的门禁（Gate）流程执行，就能把一台 iQOO 10 从「未 root」做到「root 成功且数据不丢」。
>
> 给用户的用法：把本文件路径或仓库链接发给 AI，加一句「按 AI_AGENT.md 执行」。

---

## 0. 你的角色与边界

你是**执行型 agent**，在一台 Windows PC + 一台 iQOO 10 手机上完成刷机。
你必须严格遵守门禁机制：**上一道门禁未通过，绝不进入下一阶段。**

### 五条铁律（违反任何一条都可能造成不可恢复的砖）

1. **boot 不匹配，绝不刷。** 原厂 boot 的内核版本必须与手机 `uname -r` 完全一致，否则停止并询问用户。
2. **绝不回锁。** 永不执行 `fastboot flashing lock` / `fastboot oem lock`。vivo 无签名 firehose，回锁校验签名 = 砖。
3. **绝不清数据。** 不执行 `fastboot -w`、`fastboot erase userdata`、`fastboot erase metadata`、恢复出厂。
4. **每步都要校验。** 每个操作后必须实际验证输出（md5 / 版本号 / `/proc/modules`），不能「返回 0 就当成功」。
5. **不确定就问。** 任何与 [docs/事实卡.md](docs/事实卡.md) 不符的输出、任何没见过的报错，停下来把原文贴给用户，不要猜测性重试。

### 你绝对不能做的事

- 不刷 `vbmeta`、不刷 `vendor_boot`、不刷 `dtbo`、不刷 `abl`/`xbl` 等任何 bootloader 分区
- 不用网上别人分享的 boot.img（哪怕型号一样）
- 不在未确认 `Device unlocked: true` 的情况下 flash
- 不执行除 `fastboot oem device-info` 之外的任何 `oem` 命令（该机型其余 oem 子命令全部不可用）

---

## 1. 前置输入（开工前必须向用户确认）

| 项 | 说明 | 缺失时怎么办 |
|---|---|---|
| 手机能连 adb | `adb devices` 显示 device | 让用户开 USB 调试并点授权弹窗 |
| 当前系统固件完整包 | **与本机版本完全一致的官方 OTA 完整包 zip**（约 9~10 GB） | 让用户提供；或从手机 `/storage/emulated/0/` 找 `*.zip` |
| PC 有 adb/fastboot | 能用即可 | 下载 platform-tools |
| PC 有 Python 3 | 校验脚本需要 | 装 Python 3.8+ |

> ⚠️ **最关键的一条**：整条流程对「原厂 boot」是**硬依赖**。
> 没有匹配当前系统的固件包，流程走不下去 —— 不要尝试用其它版本的 boot 硬刷。

---

## 2. 门禁流程（G1 → G6）

每个门禁都是：**做什么 → 怎么验 → 不通过怎么办**。

### G1 环境自检

```bash
bash scripts/10_env_check.sh
```

**通过标准**：`[PASS]` 覆盖 adb / fastboot / 设备在线 / BL 已解锁 / 存在 boot 分区 / A-only 单槽。
**不通过**：不要继续，按脚本提示修环境（USB 线、驱动、授权弹窗）。

---

### G2 采集手机事实（一切判断的基础）

逐条执行并**记录下来**：

```bash
adb shell getprop ro.build.display.id        # 系统版本，如 PD2217B_A_16.5.17.1.W10
adb shell uname -r                           # 内核，如 5.10.246-gki-g02b2e21da816
adb shell getprop ro.boot.flash.locked       # 必须为 0
adb shell getprop ro.boot.verifiedbootstate  # 通常 orange
adb shell getprop ro.vivo.hardware.version   # PD2217MA
adb shell ls -l /dev/block/by-name/ | grep -E 'boot|vbmeta'
```

**通过标准**：
- `ro.boot.flash.locked = 0`（已解锁 BL）
- 分区表里**只有 `boot`，没有 `boot_a`/`boot_b`**（A-only 单槽，该机型特性）
- 记下 `uname -r`，后续所有校验都以它为准

**不通过**：BL 未解锁 → 停止，让用户先在开发者选项里解锁（会清数据，由用户决定）。

---

### G3 提取并校验原厂 boot（最容易出错的一步）

固件包是 **AOSP block OTA**，`boot.img` 通常**直接就在 zip 根目录**：

```bash
unzip -l PD2217_*.zip | grep -E 'boot.img|metadata'
unzip -o PD2217_*.zip boot.img -d ./out
unzip -p PD2217_*.zip META-INF/com/android/metadata | head -20
```

提取后**必须做三重校验**，三条全过才允许进入 G4：

```bash
python scripts/20_verify_boot.py out/boot.img --expect-uname 5.10.246-gki-g02b2e21da816
```

1. **体积** = `100663296` 字节（96 MB，分区 `0x6000000`）
2. **内核版本字串**：镜像里必须能搜到与 `uname -r` 一致的 `Linux version ...`
3. **MD5**：记录下来，刷机前后都用它核对

**不通过**：固件包版本不对 → 回去找正确版本，**禁止将就**。

---

### G4 打补丁（这一步必须人工参与）

KernelSU 打补丁是**在手机 App 里点**的，AI 无法代替。你要精准指导用户：

1. 把校验过的 boot 推到手机：`adb push out/boot.img /sdcard/Download/boot_stock.img`
2. 让用户打开 **KernelSU 管理器 → 安装 → 选择并修补一个文件 → 选 boot_stock.img**
3. **KMI 必须选 `android12-5.10`**（5.10 内核的通用 KMI，选错会导致无法启动）
4. 补丁产物在 `/sdcard/Download/kernelsu_patched_*.img`
5. 你 `adb pull` 回来，再校验一次：

```bash
python scripts/20_verify_boot.py patched.img --expect-uname 5.10.246-gki-g02b2e21da816 --expect-patched
```

**通过标准**：`--expect-patched` 模式下，内核字节不变，只有 ramdisk 变大（新增 `init` / `kernelsu.ko` / `ksu_config`）。

---

### G5 刷入

```bash
bash scripts/30_flash_and_verify.sh patched.img
```

脚本内部强制顺序：`adb reboot bootloader` → `fastboot oem device-info` 确认 unlocked → `fastboot flash boot` → `fastboot reboot`。
**任何一步失败立即停止，不要盲目重刷第二次。**

---

### G6 验证 root 真实性

```bash
adb shell cat /proc/modules | grep kernelsu     # 必须看到 kernelsu ... Live
adb shell getprop ro.build.display.id           # 必须与 G2 记录一致（数据未清）
```

**通过标准**：`/proc/modules` 里有 `kernelsu ... Live (O)`，且系统版本没变。

> **重要的反直觉点**：`adb shell su` 报 `inaccessible or not found` 是**正常的**。
> KernelSU 只把 root 授予 App，不给 adb shell —— 不要把这个当成失败。

最后让用户打开 KernelSU，确认显示「工作中」，并跑一次授权弹窗测试。

---

## 3. 什么时候必须停下来问用户

以下场景**必须停下**，把原文输出贴给用户：

1. 任何 `getprop` 结果与事实卡不一致
2. 固件包里找不到 `boot.img`
3. 打补丁后的镜像内核版本变了（说明补丁方式错误）
4. `fastboot flash` 输出里出现 `FAILED` / `not allowed` / `Preflash validation failed`
5. 刷完开机卡 logo 超过 5 分钟
6. adb 掉线超过 2 次（通常锁屏导致，让用户解锁屏幕并设「充电时不锁屏」）

---

## 4. 已知坑（省得重踩）

| 现象 | 原因 | 处理 |
|---|---|---|
| `adb pull` 报 `failed to stat remote object` | Git Bash 把 `/sdcard/...` 当本地路径改写 | `export MSYS_NO_PATHCONV=1` |
| `fastboot fetch boot` 不支持 | vivo 阉割了 oem 子命令 | 走固件包提取，别试 dump |
| 补丁模块 vermagic 是 `5.10.252-dirty`，内核是 `5.10.246` | vivo 内核允许跨 minor 加载 LKM | **能加载就别管**，以 `/proc/modules` 为准 |
| 刷完 `/proc/modules` 暂时没有 kernelsu，重启后有了 | 加载时序问题 | 重启一次再验证 |
| `adb devices` 时有时无 | 屏幕休眠/锁屏 | 解锁屏幕 + 设「充电时不锁屏」 |
| 手机重启后 `/storage/emulated/0` 是空的 | /data 尚未解密 | 让用户先解锁屏幕 |

---

## 5. 失败与救砖

任何阶段失败，**第一原则是保住 fastboot**。只要能进 fastboot，就一定能恢复：

```bash
adb reboot bootloader
fastboot devices
fastboot oem device-info              # 确认 unlocked: true
fastboot flash boot stock_boot.img    # 刷回原厂 boot
fastboot reboot
```

只要原厂 boot 备份还在，就是安全的。**这就是为什么 G3 的备份是整条流程的命根子。**

---

## 6. 交付前的最终检查

见 [CHECKLIST.md](CHECKLIST.md)，逐条打勾后才算完成。
