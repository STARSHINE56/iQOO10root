#!/usr/bin/env bash
# G1 环境自检 —— 全部 PASS 才可进入 G2
set -u
PASS=0; FAIL=0
ok(){ echo "[PASS] $1"; PASS=$((PASS+1)); }
no(){ echo "[FAIL] $1"; FAIL=$((FAIL+1)); }
info(){ echo "[INFO] $1"; }

echo "===== iQOO 10 root 环境自检 ====="
export MSYS_NO_PATHCONV=1 2>/dev/null || true

if command -v adb >/dev/null 2>&1; then
  ok "adb: $(adb version 2>/dev/null | head -1)"
else
  no "找不到 adb（把 platform-tools 加进 PATH）"
fi

if command -v fastboot >/dev/null 2>&1; then
  ok "fastboot: $(fastboot --version 2>&1 | head -1)"
else
  no "找不到 fastboot"
fi

if command -v python >/dev/null 2>&1; then
  ok "python: $(python --version 2>&1)"
elif command -v python3 >/dev/null 2>&1; then
  ok "python3: $(python3 --version 2>&1)"
else
  no "找不到 python（校验脚本要用）"
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "无 adb，跳过设备检查"
  exit 1
fi

STATE=$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')
if [ -n "${STATE:-}" ]; then
  ok "设备在线: $STATE"
  echo "----- 关键属性 -----"
  for p in ro.build.display.id ro.boot.flash.locked ro.boot.verifiedbootstate ro.vivo.hardware.version; do
    printf '%-34s = %s\n' "$p" "$(adb shell getprop "$p" 2>/dev/null | tr -d '\r')"
  done
  printf '%-34s = %s\n' "uname -r" "$(adb shell uname -r 2>/dev/null | tr -d '\r')"

  LOCK=$(adb shell getprop ro.boot.flash.locked 2>/dev/null | tr -d '\r')
  if [ "$LOCK" = "0" ]; then
    ok "BL 已解锁 (flash.locked=0)"
  else
    no "BL 未解锁 (flash.locked=$LOCK) —— 不要继续"
  fi

  if adb shell 'ls /dev/block/by-name/boot' >/dev/null 2>&1; then
    ok "存在 boot 分区"
    if adb shell 'ls /dev/block/by-name/boot_a' >/dev/null 2>&1; then
      info "检测到 boot_a —— 双槽机型，本流程按 A-only 设计，需调整"
    else
      ok "确认 A-only 单槽（无 boot_a）"
    fi
  else
    no "找不到 boot 分区"
  fi
else
  no "没有在线设备（检查 USB 调试、授权弹窗、换线）"
  adb devices
fi

echo "================================"
echo "结果: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "✅ 可以进入 G2"
  exit 0
else
  echo "❌ 先修环境，别往下走"
  exit 1
fi
