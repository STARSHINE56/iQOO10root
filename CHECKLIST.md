# 完成验收清单

> 逐条打勾。**任何一条没打勾，都不算「root 成功且安全」。**

## A. 刷机前（还没动手机时确认）

- [ ] `adb devices` 能看到设备
- [ ] `ro.boot.flash.locked = 0`（BL 已解锁）
- [ ] 记录下 `uname -r`：`________________`
- [ ] 确认是 A-only 单槽（无 `boot_a`）
- [ ] 拿到**与本机版本完全一致**的官方完整固件包
- [ ] 从包里提取出 `boot.img`
- [ ] 原厂 boot 三重校验通过（体积 / 内核版本 / MD5）
- [ ] 原厂 boot 已备份到 PC **两处**（本地 + 网盘/U 盘）
- [ ] 手机电量 > 50%
- [ ] 重要数据已备份（照片、微信等），以防万一

## B. 打补丁

- [ ] 原厂 boot 已 push 到手机
- [ ] KernelSU 管理器里选「选择并修补一个文件」
- [ ] KMI 选的是 **android12-5.10**
- [ ] 补丁产物已 pull 回 PC
- [ ] 补丁镜像校验通过：内核版本与原厂一致、含 kernelsu 特征
- [ ] 补丁镜像 MD5 已记录：`________________`

## C. 刷入

- [ ] `fastboot oem device-info` 显示 `Device unlocked: true`
- [ ] 只刷了 `boot` 分区，没碰 vbmeta / vendor_boot / dtbo / 其它
- [ ] 刷完正常开机（没有卡 logo、没有重启循环）

## D. 验证

- [ ] `adb shell cat /proc/modules | grep kernelsu` 有输出且含 `Live`
- [ ] `ro.build.display.id` 与刷前一致（数据没被清）
- [ ] KernelSU 管理器 App 显示「工作中」
- [ ] 随便找个需要 root 的 App，授权弹窗能正常弹出并授权成功
- [ ] 重启一次后 root 依然有效（验证持久化）

## E. 收尾

- [ ] 原厂 boot 备份保留（**永久保留，系统更新后还能救砖**）
- [ ] 记录当前系统版本号，用于以后核对
- [ ] 关闭系统自动更新（否则 OTA 会覆盖 boot，root 丢失）
- [ ] 知道救砖方法：`fastboot flash boot <原厂boot.img>`

## F. 红线自查（绝对不要做过）

- [ ] 没有执行过 `fastboot flashing lock`
- [ ] 没有执行过 `fastboot -w` / `erase userdata`
- [ ] 没有刷过任何 non-boot 分区
- [ ] 没有用过网上别人分享的 boot.img
