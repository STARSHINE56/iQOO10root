#!/usr/bin/env bash
# G5 刷入 —— 带门禁的 boot 刷写（只刷 boot，绝不碰其它分区）
# 用法: bash 30_flash_and_verify.sh <patched.img>
set -u
IMG="${1:-}"
if [ -z "$IMG" ]; then
  echo "用法: $0 <patched.img>"
  exit 1
fi
if [ ! -f "$IMG" ]; then
  echo "文件不存在: $IMG"
  exit 2
fi

export MSYS_NO_PATHCONV=1 2>/dev/null || true

echo "===== G5 刷入门禁 ====="
echo "[0] 目标镜像: $IMG"
SZ=$(stat -c %s "$IMG" 2>/dev/null || wc -c < "$IMG")
echo "    大小: $SZ 字节"
echo "    MD5 : $(md5sum "$IMG" | awk '{print $1}')"
echo
read -r -p "确认已跑过 G3/G4 校验，且 uname -r 与镜像匹配？输入 YES 继续: " ans
if [ "$ans" != "YES" ]; then
  echo "已取消（未做任何改动，安全）"
  exit 1
fi

echo
echo "[1] 进入 bootloader"
adb reboot bootloader || { echo "adb reboot bootloader 失败"; exit 1; }
sleep 6
fastboot devices
fastboot oem device-info
echo
echo ">>> 请人工确认上面输出包含 'Device unlocked: true'"
read -r -p "确认已解锁？输入 YES 继续: " ans2
if [ "$ans2" != "YES" ]; then
  echo "已取消（未刷写，安全）"
  exit 1
fi

echo
echo "[2] 刷入 boot（只刷 boot）"
fastboot flash boot "$IMG"
RC=$?
if [ $RC -ne 0 ]; then
  echo "❌ 刷入失败 (exit $RC)。不要重复刷，先记录报错原文。"
  echo "   逃生: fastboot flash boot <原厂boot.img> && fastboot reboot"
  exit $RC
fi

echo
echo "[3] 重启"
fastboot reboot
echo "[4] 等待开机并验证（最多 180 秒）"
adb wait-for-device
i=0
while [ $i -lt 60 ]; do
  if [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
    break
  fi
  sleep 3
  i=$((i+1))
done

echo "----- 验证 -----"
echo "系统版本: $(adb shell getprop ro.build.display.id 2>/dev/null | tr -d '\r')"
echo "内核    : $(adb shell uname -r 2>/dev/null | tr -d '\r')"
MOD=$(adb shell cat /proc/modules 2>/dev/null | grep -i kernelsu | tr -d '\r')
if [ -n "$MOD" ]; then
  echo "✅ KernelSU 模块已加载: $MOD"
else
  echo "⚠️ 暂未看到 kernelsu 模块，重启一次再看（常见时序问题）"
fi
echo "提示: adb shell su 报 not found 属正常，KernelSU 只授权 App。"
